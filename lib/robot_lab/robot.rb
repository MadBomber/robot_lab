# frozen_string_literal: true

module RobotLab
  # LLM-powered robot using ruby_llm-template for prompts
  #
  # Robot is a thin wrapper around RubyLLM.chat that provides:
  # - Template-based prompts via ruby_llm-template
  # - Build-time context (static robot configuration)
  # - Run-time context (per-request dynamic data)
  # - Tool integration via RubyLLM::Tool
  #
  # @example Simple robot with template
  #   robot = Robot.new(
  #     name: "helper",
  #     template: :helper,
  #     context: { company_name: "Acme Corp" }
  #   )
  #   result = robot.run(message: "Hello!", user_name: "Alice")
  #
  # @example Robot with tools
  #   robot = Robot.new(
  #     name: "support",
  #     template: :support,
  #     context: { policies: POLICIES },
  #     tools: [OrderLookup, RefundProcessor]
  #   )
  #
  class Robot
    attr_reader :name, :description, :template, :model, :tools

    def initialize(
      name:,
      template:,
      context: {},
      description: nil,
      tools: [],
      model: nil,
      on_tool_call: nil,
      on_tool_result: nil
    )
      @name = name.to_s
      @template = template
      @build_context = context
      @description = description
      @tools = Array(tools)
      @model = model || RobotLab.configuration.default_model
      @on_tool_call = on_tool_call
      @on_tool_result = on_tool_result
    end

    # Run the robot with the given context
    #
    # @param network [NetworkRun, nil] Network context if running in network
    # @param state [State, nil] Shared state
    # @param run_context [Hash] Context for rendering user template
    # @return [RobotResult]
    #
    def run(network: nil, state: nil, **run_context)
      state ||= network&.state || State.new

      # Merge build context + run context
      full_context = resolve_context(@build_context, network: network)
                       .merge(run_context)

      # Build chat with template and tools
      chat = build_chat(full_context)

      # Execute and return result
      response = chat.complete

      build_result(response, state)
    end

    def to_h
      {
        name: name,
        description: description,
        template: template,
        tools: tools.map { |t| t.respond_to?(:name) ? t.name : t.to_s },
        model: model.respond_to?(:model_id) ? model.model_id : model
      }.compact
    end

    private

    def resolve_context(context, network:)
      case context
      when Proc then context.call(network: network)
      when Hash then context
      else {}
      end
    end

    def build_chat(context)
      model_id = @model.respond_to?(:model_id) ? @model.model_id : @model.to_s

      chat = RubyLLM.chat(model: model_id)
      chat = chat.with_template(@template, **context)
      chat = chat.with_tools(*@tools) if @tools.any?

      # Add callbacks if provided
      chat = chat.on_tool_call(&@on_tool_call) if @on_tool_call
      chat = chat.on_tool_result(&@on_tool_result) if @on_tool_result

      chat
    end

    def build_result(response, _state)
      output = if response.respond_to?(:content) && response.content
                 [TextMessage.new(role: "assistant", content: response.content)]
               else
                 []
               end

      tool_calls = response.respond_to?(:tool_calls) ? (response.tool_calls || []) : []

      RobotResult.new(
        robot_name: @name,
        output: output,
        tool_calls: normalize_tool_calls(tool_calls),
        stop_reason: response.respond_to?(:stop_reason) ? response.stop_reason : nil
      )
    end

    def normalize_tool_calls(tool_calls)
      return [] unless tool_calls

      tool_calls.map do |tc|
        if tc.is_a?(Hash)
          ToolResultMessage.new(
            tool: tc,
            content: tc[:result] || tc["result"]
          )
        else
          tc
        end
      end
    end
  end
end
