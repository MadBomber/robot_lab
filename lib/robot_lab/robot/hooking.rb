# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    module Hooking
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
              response = invoke_ask(context: context, kwargs: kwargs, hooks: hooks, block: block)
              result = build_result(response, run_memory)
              enforce_token_budget!
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
    end
  end
end
