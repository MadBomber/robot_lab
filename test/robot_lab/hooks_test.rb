# frozen_string_literal: true

require "test_helper"

HookTestResponse = Data.define(:content, :tool_calls, :stop_reason) do
  def initialize(content:, tool_calls: nil, stop_reason: "end_turn")
    super
  end
end

class RobotLab::HooksTest < Minitest::Test
  def setup
    RobotLab.clear_hooks!
  end

  def teardown
    RobotLab.clear_hooks!
  end

  def test_global_robot_and_per_run_hooks_fire_in_order_with_dot_context
    events = []
    robot = hooked_robot("hooked")

    RobotLab.on(:before_run, namespace: :global) do |ctx|
      ctx.local.seen = true
      events << [:global_before, ctx.robot.name, ctx.request, ctx.local.seen]
      ctx.request = "changed"
    end

    robot.on(:after_run, namespace: :robot) do |ctx|
      events << [:robot_after, ctx.response.reply, ctx.ext(:global).seen]
    end

    result = robot.run(
      "original",
      hooks: {
        namespace: :runtime,
        before_run: proc { |ctx| events << [:runtime_before, ctx.request] }
      }
    )

    assert_equal "changed response", result.reply
    assert_equal [
      [:global_before, "hooked", "original", true],
      [:runtime_before, "changed"],
      [:robot_after, "changed response", true]
    ], events
  end

  def test_around_run_hooks_wrap_the_robot_run
    events = []
    robot = hooked_robot("around")

    RobotLab.on(:around_run, namespace: :global) do |ctx, &block|
      events << [:global_open, ctx.robot.name]
      block.call
      events << :global_close
    end

    robot.on(:around_run, namespace: :robot) do |_ctx, &block|
      events << :robot_open
      block.call
      events << :robot_close
    end

    robot.run("go")

    assert_equal [[:global_open, "around"], :robot_open, :robot_close, :global_close], events
  end

  def test_on_error_fires_and_reraises
    errors = []
    robot = build_robot(name: "error_bot", system_prompt: "raise")
    robot.instance_variable_get(:@chat).define_singleton_method(:ask) { |_message = nil, **_kwargs| raise "boom" }

    RobotLab.on(:on_error, namespace: :global) do |ctx|
      errors << [ctx.robot.name, ctx.error.message]
    end

    assert_raises(RuntimeError) { robot.run("explode") }
    assert_equal [%w[error_bot boom]], errors
  end

  def test_network_task_and_network_scoped_robot_hooks_fire
    events = []
    robot = hooked_robot("worker")
    network = RobotLab::Network.new(name: "hooks")
    network.on(:before_run, namespace: :network) { |ctx| events << [:network_robot, ctx.network.name, ctx.task.name] }
    network.task(:worker, robot, depends_on: :none)

    RobotLab.on(:before_network_run, namespace: :global) { |ctx| events << [:network_start, ctx.network.name] }
    RobotLab.on(:before_task, namespace: :global) { |ctx| events << [:task_start, ctx.task_name, ctx.robot.name] }

    network.run(message: "hello")

    assert_equal [
      [:network_start, "hooks"],
      [:task_start, :worker, "worker"],
      [:network_robot, "hooks", :worker]
    ], events
  end

  def test_tool_call_hooks_can_observe_and_short_circuit
    events = []
    tool = Class.new(RobotLab::Tool) do
      def execute(**)
        "called"
      end
    end.new

    RobotLab.on(:around_tool_call, namespace: :global) do |ctx|
      events << [ctx.tool_name, ctx.tool_args]
      ctx.tool_result = "short"
    end

    assert_equal "short", tool.call({ "value" => 1 })
    assert_equal [[tool.name, { "value" => 1 }]], events
  end

  def test_per_run_tool_hooks_are_available_during_robot_run
    events = []
    tool = Class.new(RobotLab::Tool) do
      def execute(**)
        "called"
      end
    end.new
    robot = hooked_robot("tool_bot")
    tool.robot = robot

    per_run_hooks = {
      around_tool_call: proc do |ctx|
        events << ctx.tool_name
        ctx.tool_result = "short"
      end
    }

    RobotLab.with_hook_scope([RobotLab.hooks, robot.hooks], per_run_hooks) do
      assert_equal "short", tool.call({})
    end

    assert_equal [tool.name], events
  end

  private

  def hooked_robot(name)
    build_robot(name: name, system_prompt: "hook test").tap do |robot|
      robot.instance_variable_get(:@chat).define_singleton_method(:ask) do |message = nil, **_kwargs, &_block|
        HookTestResponse.new(content: "#{message} response")
      end
    end
  end
end
