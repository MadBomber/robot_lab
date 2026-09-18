# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    module Hooking
      # :reek:LongParameterList -- the documented Robot#run public API: each keyword is a distinct run-scoped override.
      # :reek:TooManyStatements -- the run lifecycle (memory writer swap, hook wrap, budget, cleanup) is one
      #   deliberate orchestrator; flog gates its complexity.
      def run(message = nil, network: nil, task: nil, network_memory: nil, network_config: nil,
              memory: nil, mcp: :none, tools: :none, hooks: nil, **kwargs, &block)
        run_memory = resolve_run_memory(memory, network: network, network_memory: network_memory)
        previous_writer = run_memory.current_writer
        run_memory.current_writer = @name
        context = RunHookContext.new(
          robot: self,
          network: network,
          task: task,
          memory: run_memory,
          config: @config,
          request: message
        )

        registries = hook_registries(network)

        begin
          RobotLab.with_hook_scope(registries, hooks) do
            RobotLab::Hooks.run(:run, context, registries: registries, per_run_hooks: hooks) do
              run_context = kwargs.except(:with)
              prepare_tools(message: context.request, mcp: mcp, tools: tools,
                            network: network, network_config: network_config)
              rerender_template(run_context) if @template && run_context.any?
              reservation = reserve_budget!
              response = invoke_ask(context: context, kwargs: kwargs, hooks: hooks, block: block)
              result = build_result(response, run_memory)
              reconcile_budget!(reservation, response: response, result: result)
              enforce_token_budget!
              enforce_cost_budget!
              result
            end
          end
        ensure
          remove_doom_loop_detection
          restore_tool_call_callback if @config.max_tool_rounds
          run_memory.current_writer = previous_writer
        end
      end

      def on(handler_class, context: nil)
        @hooks.on(handler_class, context: context)
      end

      private

      def hook_registries(network = nil)
        [RobotLab.hooks, network&.hooks, @hooks]
      end

      # Arm the per-run circuit breaker checked by the chat's before_tool_call
      # dispatcher (see Robot#register_chat_callbacks). Raises ToolLoopError
      # once tool calls exceed @config.max_tool_rounds. ruby_llm 2.0 callbacks
      # are additive and cannot be removed, so the breaker toggles a flag the
      # permanent dispatcher consults instead of swapping callbacks per run.
      def install_circuit_breaker
        @circuit_breaker_call_count = 0
        @circuit_breaker_armed = true
      end

      # Disarm the circuit breaker after a run.
      def restore_tool_call_callback
        @circuit_breaker_armed = false
      end

      # Count a tool call against max_tool_rounds and raise once exceeded.
      def enforce_circuit_breaker!
        max = @config.max_tool_rounds
        @circuit_breaker_call_count += 1
        return if @circuit_breaker_call_count <= max

        raise ToolLoopError,
              "Circuit breaker triggered: #{@circuit_breaker_call_count} tool calls exceeded " \
              "max_tool_rounds (#{max})"
      end
    end
  end
end
