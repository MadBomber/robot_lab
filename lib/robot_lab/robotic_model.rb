# frozen_string_literal: true

module RobotLab
  # Wrapper around ruby_llm for LLM inference
  #
  # RoboticModel provides a unified interface for LLM calls, handling:
  # - Message format conversion via adapters
  # - Tool registration and execution
  # - Streaming support
  #
  # @example Basic usage
  #   model = RoboticModel.new("claude-sonnet-4", provider: :anthropic)
  #   messages = [TextMessage.new(role: :user, content: "Hello!")]
  #   response = model.infer(messages, [])
  #
  # @example With tools
  #   model.infer(messages, [weather_tool], tool_choice: "auto")
  #
  class RoboticModel
    attr_reader :model_id, :provider, :adapter

    def initialize(model_id, provider: nil)
      @model_id = model_id
      @provider = provider || detect_provider(model_id)
      @adapter = Adapters::Registry.for(@provider)
    end

    # Perform inference with messages and optional tools
    #
    # @param messages [Array<Message>] Conversation messages
    # @param tools [Array<Tool>] Available tools
    # @param tool_choice [String, Symbol] Tool selection mode
    # @param streaming [Proc, nil] Streaming callback
    # @return [InferenceResponse]
    #
    def infer(messages, tools = [], tool_choice: "auto", streaming: nil, &block)
      chat = create_chat

      # Register tools if any
      if tools.any?
        ruby_llm_tools = create_ruby_llm_tools(tools)
        chat = chat.with_tools(*ruby_llm_tools)
      end

      # Add system message if present
      system_content = @adapter.extract_system_message(messages)

      # Build conversation
      conversation = @adapter.conversation_messages(messages)
      conversation.each do |msg|
        add_message_to_chat(chat, msg)
      end

      # Make the request
      response = if block_given? || streaming
                   chat.ask(conversation.last&.content || "", &(block || streaming))
                 else
                   chat.ask(conversation.last&.content || "")
                 end

      # Parse response
      output = @adapter.parse_response(response)

      InferenceResponse.new(
        output: output,
        raw: response,
        model: model_id,
        provider: provider
      )
    end

    # Quick ask without full message array
    #
    # @param prompt [String] User prompt
    # @param system [String, nil] System prompt
    # @param tools [Array<Tool>] Available tools
    # @return [InferenceResponse]
    #
    def ask(prompt, system: nil, tools: [], &block)
      messages = []
      messages << TextMessage.new(role: "system", content: system) if system
      messages << TextMessage.new(role: "user", content: prompt)

      infer(messages, tools, &block)
    end

    private

    def create_chat
      RubyLLM.chat(model: model_id, provider: provider)
    end

    def create_ruby_llm_tools(tools)
      tools.map do |tool|
        # Create a dynamic RubyLLM::Tool subclass
        create_tool_class(tool)
      end
    end

    def create_tool_class(tool)
      # Build a RubyLLM::Tool subclass dynamically
      tool_definition = tool

      klass = Class.new(RubyLLM::Tool) do
        description tool_definition.description || ""

        # Add parameters from schema
        schema = tool_definition.to_json_schema
        if schema[:parameters] && schema[:parameters][:properties]
          schema[:parameters][:properties].each do |prop_name, prop_def|
            required = schema[:parameters][:required]&.include?(prop_name.to_s)
            param prop_name.to_sym,
                  type: prop_def[:type] || "string",
                  desc: prop_def[:description],
                  required: required
          end
        end

        define_method(:execute) do |**kwargs|
          # This is called by ruby_llm when the tool is invoked
          # We return the kwargs for now - actual execution happens in Robot
          kwargs
        end
      end

      # Store reference to our tool for later execution
      klass.define_singleton_method(:robot_lab_tool) { tool_definition }
      klass
    end

    def add_message_to_chat(chat, msg)
      case msg
      when TextMessage
        if msg.user?
          chat.add_message(role: :user, content: msg.content)
        elsif msg.assistant?
          chat.add_message(role: :assistant, content: msg.content)
        end
      when ToolResultMessage
        # Tool results are handled by ruby_llm internally
      end
    end

    def detect_provider(model_id)
      case model_id.to_s.downcase
      when /^claude/, /^anthropic/
        :anthropic
      when /^gpt/, /^o1/, /^o3/, /^chatgpt/
        :openai
      when /^gemini/
        :gemini
      when /^llama/, /^mistral/, /^mixtral/
        :ollama
      else
        RobotLab.configuration.default_provider
      end
    end
  end

  # Response from LLM inference
  #
  class InferenceResponse
    attr_reader :output, :raw, :model, :provider

    def initialize(output:, raw:, model:, provider:)
      @output = output
      @raw = raw
      @model = model
      @provider = provider
    end

    # Get the stop reason from the last output message
    #
    # @return [String, nil]
    #
    def stop_reason
      output.last&.stop_reason
    end

    # Check if inference stopped naturally
    #
    # @return [Boolean]
    #
    def stopped?
      stop_reason == "stop"
    end

    # Check if inference wants to call tools
    #
    # @return [Boolean]
    #
    def wants_tools?
      stop_reason == "tool" || output.any?(&:tool_call?)
    end

    # Get all tool calls from the response
    #
    # @return [Array<ToolMessage>]
    #
    def tool_calls
      output.select(&:tool_call?).flat_map(&:tools)
    end

    # Get the text content
    #
    # @return [String, nil]
    #
    def text_content
      output.select(&:text?).map(&:content).join
    end
  end
end
