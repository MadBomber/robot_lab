# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    # What happens between the model asking for a tool and the tool answering
    # when the tool is not a RobotLab::Tool: MCP tools and plain
    # RubyLLM::Tool instances.
    #
    # - The hook bridge runs the robot's +:tool_call+ hooks around the chat's
    #   execution of such tools (RobotLab::Tool runs them itself in #call),
    #   and turns an MCP transport failure mid-call into an error result so
    #   the model can recover instead of the run aborting.
    # - The settlement loop answers what ruby_llm pauses a run for: tool
    #   calls that require approval, MCP input requests (elicitation), and
    #   long-running MCP tasks. A run never returns half-finished.
    #
    # Owns:    nothing (uses @chat, @tool_approval, @on_tool_approval, @on_input_request)
    # Reads:   @name
    module ToolCallGating
      # How long a run waits for long-running MCP tasks before giving up.
      MCP_TASK_TIMEOUT = 300

      private

      # Wrap the chat's execute_tool so foreign tools get :tool_call hooks.
      # Prepended on the chat's singleton class, the bridge sits ahead of the
      # per-run doom-loop singleton method (install_doom_loop_detection) and
      # calls through to it with +super+.
      def install_tool_hook_bridge
        robot  = self
        bridge = Module.new do
          define_method(:execute_tool) do |tool_call|
            robot.send(:bridge_tool_call, tool_call) { super(tool_call) }
          end
          private :execute_tool
        end
        @chat.singleton_class.prepend(bridge)
      end

      # Run :tool_call hooks around a chat-executed tool call. Yields to the
      # chat's own execution; the PAUSED sentinel it returns for approvals,
      # input requests and tasks passes through untouched.
      # :reek:TooManyStatements -- context build, hook wrap and the MCP rescue are one guarded dispatch.
      def bridge_tool_call(tool_call)
        tool = @chat.tools[tool_call.name.to_sym]
        return yield if tool.nil? || tool.is_a?(RobotLab::Tool)

        context = ToolCallHookContext.new(tool: tool, tool_args: tool_call.arguments, robot: self,
                                          mcp_server: mcp_server_for(tool))
        scope = RobotLab.current_hook_scope || {}
        RobotLab::Hooks.run(:tool_call, context,
                            registries: scope[:registries] || hook_registries,
                            per_run_hooks: scope[:per_run_hooks]) do
          context.tool_result = yield
        rescue RubyLLM::MCP::Error => e
          context.tool_error  = e
          context.tool_result = { error: "#{tool.name}: #{e.message}" }
        end
        context.tool_result
      end

      # Keep completing the chat until nothing waits on the outside world:
      # decide approvals, answer input requests, wait on tasks, complete again.
      #
      # @param response [RubyLLM::Message] what ask returned
      # @return [RubyLLM::Message] the final response
      def settle_pending_tool_calls(response, &)
        deadline = nil
        while @chat.waiting?
          decide_pending_approvals
          answer_pending_inputs
          deadline = wait_for_mcp_tasks(deadline)
          response = @chat.complete(&)
        end
        response
      end

      def decide_pending_approvals
        @chat.pending_approvals.each do |tool_call|
          approve_tool_call?(tool_call) ? @chat.approve(tool_call) : @chat.deny(tool_call)
        end
      end

      # Approval policy: an on_tool_approval Proc decides; else tool_approval
      # :approve allows; else deny with a warning naming the two settings.
      #
      # @param tool_call [RubyLLM::ToolCall]
      # @return [Boolean]
      def approve_tool_call?(tool_call)
        return @on_tool_approval.call(tool_call) ? true : false if @on_tool_approval
        return true if @tool_approval == :approve

        RobotLab.config.logger.warn(
          "Robot '#{@name}' denied tool call '#{tool_call.name}': it requires approval. " \
          'Pass tool_approval: :approve or on_tool_approval: to allow it.'
        )
        false
      end

      def answer_pending_inputs
        @chat.pending_inputs.each { |request| settle_input_request(request) }
      end

      # An on_input_request Proc answers a request with a Hash of field
      # values (or +true+ to accept a URL request); anything else declines.
      #
      # @param request [RubyLLM::MCP::InputRequest]
      def settle_input_request(request)
        answer = @on_input_request&.call(request)
        case answer
        when Hash then @chat.answer(request, **answer.transform_keys(&:to_sym))
        when true then @chat.answer(request)
        else
          RobotLab.config.logger.warn(
            "Robot '#{@name}' declined an MCP input request (#{request.message}); set on_input_request: to answer it."
          )
          @chat.decline(request)
        end
      end

      # Sleep one poll interval when tool calls wait on MCP tasks, tracking a
      # deadline across calls so a stuck task cannot hang the run.
      #
      # @param deadline [Float, nil] monotonic time to give up at, once a task has been seen
      # @return [Float, nil] the deadline to carry forward
      def wait_for_mcp_tasks(deadline)
        tasks = @chat.pending_tasks
        return nil if tasks.empty?

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        deadline ||= now + MCP_TASK_TIMEOUT
        raise_mcp_task_timeout!(tasks) if now > deadline

        sleep(tasks.filter_map(&:poll_interval).min || 1)
        deadline
      end

      def raise_mcp_task_timeout!(tasks)
        names = tasks.map { |task| task.tool_call&.name }.compact.join(', ')
        raise MCPError.new("MCP task(s) for #{names} did not finish within #{MCP_TASK_TIMEOUT}s", retryable: true)
      end
    end
  end
end
