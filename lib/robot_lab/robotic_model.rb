# frozen_string_literal: true

module RobotLab
  # Thread-local storage for capturing tool executions during RubyLLM auto-execution.
  #
  # Stores tool execution records in thread-local storage so they can be
  # retrieved after an LLM inference call completes.
  #
  class ToolExecutionCapture
    # Returns the captured tool executions for the current thread.
    #
    # @return [Array<Hash>] array of execution records
    def self.captured
      Thread.current[:robot_lab_tool_executions] ||= []
    end

    # Clears the captured tool executions for the current thread.
    #
    # @return [Array] empty array
    def self.clear!
      Thread.current[:robot_lab_tool_executions] = []
    end

    # Records a tool execution.
    #
    # @param tool_name [String] name of the executed tool
    # @param tool_id [String] unique identifier for this execution
    # @param input [Hash] input parameters passed to the tool
    # @param output [Object] the tool's return value
    # @return [Array<Hash>] the updated captured array
    def self.record(tool_name:, tool_id:, input:, output:)
      captured << {
        tool_name: tool_name,
        tool_id: tool_id,
        input: input,
        output: output
      }
    end
  end

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
    # @!attribute [r] model_id
    #   @return [String] the LLM model identifier
    # @!attribute [r] provider
    #   @return [Symbol] the LLM provider (:anthropic, :openai, :gemini, etc.)
    # @!attribute [r] adapter
    #   @return [Adapters::Base] the adapter for message conversion
    attr_reader :model_id, :provider, :adapter

    # Creates a new RoboticModel instance.
    #
    # @param model_id [String] the model identifier
    # @param provider [Symbol, nil] the provider (auto-detected if not specified)
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
      chat = chat.with_instructions(system_content) if system_content

      # Build conversation (excluding the last user message since ask() will add it)
      conversation = @adapter.conversation_messages(messages)
      conversation[0...-1].each do |msg|
        add_message_to_chat(chat, msg)
      end

      # Make the request (ask adds the user message)
      user_content = conversation.last&.content || ""

      # Clear tool execution capture before making the request
      ToolExecutionCapture.clear!

      response = if block_given? || streaming
                   chat.ask(user_content, &(block || streaming))
                 else
                   chat.ask(user_content)
                 end

      # Parse response
      output = @adapter.parse_response(response)

      # Build captured tool results from auto-executed tools
      captured_tool_results = build_captured_tool_results(tools)

      InferenceResponse.new(
        output: output,
        raw: response,
        model: model_id,
        provider: provider,
        captured_tool_results: captured_tool_results
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
      tool_name = tool.name

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
          # Call the handler directly (bypassing Tool#call which requires context)
          # Handlers should use **_context pattern to accept but ignore context
          output = tool_definition.handler.call(kwargs, robot: nil, network: nil, step: nil)

          # Record the execution for later retrieval
          ToolExecutionCapture.record(
            tool_name: tool_name,
            tool_id: SecureRandom.uuid,
            input: kwargs,
            output: output
          )

          output
        end
      end

      # Set the class name so RubyLLM can identify the tool
      # RubyLLM converts class names to snake_case for tool identification
      class_name = tool_name.split("_").map(&:capitalize).join
      klass.define_singleton_method(:name) { class_name }

      # Also define instance method for name (used by some RubyLLM code paths)
      klass.define_method(:name) { tool_name }

      # Store reference to our tool for later execution
      klass.define_singleton_method(:robot_lab_tool) { tool_definition }
      klass
    end

    def build_captured_tool_results(tools)
      ToolExecutionCapture.captured.map do |capture|
        _tool = tools.find { |t| t.name == capture[:tool_name] }
        tool_message = ToolMessage.new(
          id: capture[:tool_id],
          name: capture[:tool_name],
          input: capture[:input]
        )
        ToolResultMessage.new(
          tool: tool_message,
          content: { data: capture[:output] }
        )
      end
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
        RobotLab.config.ruby_llm.provider
      end
    end
  end

  # Response from LLM inference.
  #
  # Contains the parsed output, raw response, and any captured tool results.
  #
  class InferenceResponse
    # @!attribute [r] output
    #   @return [Array<Message>] parsed output messages
    # @!attribute [r] raw
    #   @return [Object] the raw response from RubyLLM
    # @!attribute [r] model
    #   @return [String] the model that generated the response
    # @!attribute [r] provider
    #   @return [Symbol] the provider that handled the request
    # @!attribute [r] captured_tool_results
    #   @return [Array<ToolResultMessage>] tool executions that were auto-executed
    attr_reader :output, :raw, :model, :provider, :captured_tool_results

    # Creates a new InferenceResponse instance.
    #
    # @param output [Array<Message>] parsed output messages
    # @param raw [Object] raw response from RubyLLM
    # @param model [String] model identifier
    # @param provider [Symbol] provider identifier
    # @param captured_tool_results [Array<ToolResultMessage>] captured results
    def initialize(output:, raw:, model:, provider:, captured_tool_results: [])
      @output = output
      @raw = raw
      @model = model
      @provider = provider
      @captured_tool_results = captured_tool_results
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
