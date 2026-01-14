# frozen_string_literal: true

module RobotLab
  # LLM-powered robot with tools and lifecycle hooks
  #
  # Robot is the core execution unit in RobotLab. Each robot has:
  # - A system prompt (can be static or dynamic)
  # - Optional tools it can invoke
  # - Optional model override (otherwise uses network default)
  # - Optional MCP servers for external tools
  # - Lifecycle hooks for customization
  # - Access to shared memory within a network
  #
  # @example Simple robot
  #   robot = Robot.new(
  #     name: "helper",
  #     system: "You are a helpful assistant"
  #   )
  #   result = robot.run("What is 2 + 2?")
  #
  # @example Robot with tools
  #   robot = Robot.new(
  #     name: "weather_robot",
  #     system: "You help users with weather information",
  #     tools: [weather_tool, forecast_tool]
  #   )
  #
  # @example Robot using memory
  #   # Within a tool handler or lifecycle hook:
  #   def handle(input, robot:, network:, memory:, **)
  #     memory.remember(:last_query, input[:query])
  #     previous = memory.shared.recall(:user_preference)
  #     # ...
  #   end
  #
  class Robot
    # Execution states
    EXECUTION_STATES = %i[idle initializing inferring executing_tools completed failed].freeze

    attr_reader :name, :description, :model, :mcp_servers, :lifecycle,
                :tool_choice, :assistant_message, :execution_state

    def initialize(
      name:,
      system:,
      description: nil,
      tools: [],
      model: nil,
      mcp_servers: [],
      lifecycle: nil,
      tool_choice: "auto",
      assistant_message: nil
    )
      @name = name.to_s
      @description = description
      @system = normalize_system_prompt(system)
      @tools = ToolManifest.new(tools)
      @model = model
      @mcp_servers = Array(mcp_servers)
      @lifecycle = lifecycle || Lifecycle.new
      @tool_choice = tool_choice
      @assistant_message = assistant_message
      @mcp_clients = []
      @execution_state = :idle
    end

    # Access to tools manifest
    #
    # @return [ToolManifest]
    #
    def tools
      @tools
    end

    # Get scoped memory for this robot
    #
    # Returns a ScopedMemory accessor for this robot's namespace.
    # The robot can also access shared memory via memory.shared.
    #
    # @param state [State] The state containing the memory
    # @return [ScopedMemory]
    #
    def memory(state)
      state.memory.scoped(@name.to_sym)
    end

    # Run the robot with input
    #
    # @param input [String, UserMessage] User input
    # @param network [NetworkRun, nil] Network context if running in network
    # @param state [State, nil] Shared state
    # @param streaming_context [Streaming::Context, nil] For event streaming
    # @param max_iter [Integer] Maximum tool call iterations
    # @return [RobotResult]
    #
    def run(input, network: nil, state: nil, streaming_context: nil, max_iter: nil)
      max_iter ||= RobotLab.configuration.max_tool_iterations
      user_message = UserMessage.from(input)
      state ||= network&.state || State.new

      @execution_state = :initializing

      begin
        # Initialize MCP tools if needed
        init_mcp if @mcp_servers.any?

        # Build initial prompt
        prompt = build_prompt(user_message, network)
        history = state.format_history

        # Lifecycle: on_start
        start_result = @lifecycle.call_on_start(
          robot: self,
          network: network,
          memory: memory(state),
          prompt: prompt,
          history: history
        )

        if start_result[:stop]
          @execution_state = :completed
          return RobotResult.new(
            robot_name: @name,
            output: [],
            tool_calls: [],
            prompt: prompt,
            history: history
          )
        end

        prompt = start_result[:prompt]
        history = start_result[:history]

        @execution_state = :inferring

        # Inference loop
        iter = 0
        inference = nil
        all_tool_results = []

        loop do
          # Perform inference
          inference = perform_inference(prompt + history)

          # Collect any tool results that were auto-executed by RubyLLM
          if inference.respond_to?(:captured_tool_results) && inference.captured_tool_results.any?
            all_tool_results.concat(inference.captured_tool_results)
          end

          # Lifecycle: on_response
          inference_result = RobotResult.new(
            robot_name: @name,
            output: inference.output,
            tool_calls: all_tool_results
          )
          @lifecycle.call_on_response(robot: self, network: network, memory: memory(state), result: inference_result)

          # Check if we should stop
          break if inference.stopped? || iter >= max_iter
          break unless inference.wants_tools?

          # Execute tools
          @execution_state = :executing_tools
          tool_results = invoke_tools(inference, network: network, state: state, streaming_context: streaming_context)
          all_tool_results.concat(tool_results)

          # Add to history for next iteration
          history = history + inference.output + tool_results

          @execution_state = :inferring
          iter += 1
        end

        @execution_state = :completed

        # Build final result
        result = RobotResult.new(
          robot_name: @name,
          output: inference&.output || [],
          tool_calls: all_tool_results,
          prompt: prompt,
          history: history,
          raw: inference&.raw
        )

        # Lifecycle: on_finish
        @lifecycle.call_on_finish(robot: self, network: network, memory: memory(state), result: result)

        result
      rescue StandardError => e
        @execution_state = :failed
        raise InferenceError, "Robot #{@name} failed: #{e.message}"
      ensure
        @execution_state = :idle unless @execution_state == :completed
      end
    end

    # Get the resolved system prompt
    #
    # @param network [NetworkRun, nil]
    # @return [String]
    #
    def system_prompt(network: nil)
      case @system
      when Proc
        @system.call(network: network)
      else
        @system.to_s
      end
    end

    # Check if robot is enabled in current context
    #
    # @param network [NetworkRun, nil]
    # @param state [State, nil] State containing memory
    # @return [Boolean]
    #
    def enabled?(network: nil, state: nil)
      mem = state ? memory(state) : nil
      @lifecycle.enabled?(robot: self, network: network, memory: mem)
    end

    def to_h
      {
        name: name,
        description: description,
        tools: tools.names,
        model: model&.model_id,
        mcp_servers: mcp_servers.map { |s| s[:name] },
        lifecycle: lifecycle.to_h,
        tool_choice: tool_choice
      }.compact
    end

    private

    def normalize_system_prompt(system)
      case system
      when Proc
        system
      when String
        system
      else
        system.to_s
      end
    end

    def build_prompt(user_message, network)
      messages = []

      # System message
      system_content = system_prompt(network: network)
      if user_message.system_prompt
        system_content = "#{system_content}\n\n#{user_message.system_prompt}"
      end
      messages << TextMessage.new(role: "system", content: system_content)

      # User message
      messages << TextMessage.new(role: "user", content: user_message.content)

      # Optional assistant prefix
      if @assistant_message
        messages << TextMessage.new(role: "assistant", content: @assistant_message)
      end

      messages
    end

    def perform_inference(messages)
      active_model = @model || RobotLab.configuration.default_model
      active_model = RoboticModel.new(active_model) if active_model.is_a?(String)

      active_model.infer(messages, @tools.to_a, tool_choice: @tool_choice)
    end

    def invoke_tools(inference, network:, state:, streaming_context: nil)
      tool_calls = inference.tool_calls
      results = []

      tool_calls.each do |tool_call|
        tool = @tools[tool_call.name]

        unless tool
          raise ToolNotFoundError, "Tool not found: #{tool_call.name}. " \
                                   "Available tools: #{@tools.names.join(', ')}"
        end

        # Stream tool start event
        streaming_context&.publish_event(
          event: "part.created",
          data: { type: "tool-call", tool_name: tool_call.name }
        )

        # Execute tool with memory context
        output = tool.call(
          tool_call.input,
          robot: self,
          network: network,
          memory: memory(state)
        )

        # Stream tool result
        streaming_context&.publish_event(
          event: "tool_call.output.delta",
          data: { tool_name: tool_call.name, delta: output.to_json }
        )

        results << ToolResultMessage.new(
          tool: tool_call,
          content: output.is_a?(Hash) && output.key?(:error) ? output : { data: output }
        )
      end

      results
    end

    def init_mcp
      return if @mcp_clients.size >= @mcp_servers.size

      @mcp_servers.each do |server|
        client = MCP::Client.new(server)
        client.connect

        # List tools and add to manifest
        begin
          mcp_tools = client.list_tools
          mcp_tools.each do |mcp_tool|
            tool_name = "#{server[:name]}-#{mcp_tool[:name]}"
            @tools.add(Tool.new(
              name: tool_name,
              description: mcp_tool[:description],
              parameters: mcp_tool[:input_schema],
              mcp: { server: server, tool: mcp_tool },
              handler: ->(input, **_opts) { client.call_tool(mcp_tool[:name], input) }
            ))
          end
        rescue StandardError => e
          RobotLab.configuration.logger.warn("MCP tool discovery failed for #{server[:name]}: #{e.message}")
        end

        @mcp_clients << client
      end
    end
  end
end
