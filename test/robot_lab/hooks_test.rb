# frozen_string_literal: true

require "test_helper"

HookTestResponse = Data.define(:content, :tool_calls, :stop_reason) do
  def initialize(content:, tool_calls: nil, stop_reason: "end_turn")
    super
  end
end

# ---------------------------------------------------------------------------
# Handler classes used across tests. Each stores events in a class-level
# @events reference set by each test before registering.
# ---------------------------------------------------------------------------

class GlobalBeforeHook < RobotLab::Hook
  self.namespace = :global
  @events = nil
  class << self
    attr_accessor :events

    def before_run(ctx)
      ctx.local.seen = true
      events << [:global_before, ctx.robot.name, ctx.request, ctx.local.seen]
      ctx.request = "changed"
    end
  end
end

class RobotAfterHook < RobotLab::Hook
  self.namespace = :robot
  @events = nil
  class << self
    attr_accessor :events

    def after_run(ctx)
      events << [:robot_after, ctx.response.reply, ctx.ext(:global).seen]
    end
  end
end

class RuntimeBeforeHook < RobotLab::Hook
  self.namespace = :runtime
  @events = nil
  class << self
    attr_accessor :events

    def before_run(ctx)
      events << [:runtime_before, ctx.request]
    end
  end
end

class GlobalAroundHook < RobotLab::Hook
  self.namespace = :global
  @events = nil
  class << self
    attr_accessor :events

    def around_run(ctx, &block)
      events << [:global_open, ctx.robot.name]
      block.call
      events << :global_close
    end
  end
end

class RobotAroundHook < RobotLab::Hook
  self.namespace = :robot
  @events = nil
  class << self
    attr_accessor :events

    def around_run(_ctx, &block)
      events << :robot_open
      block.call
      events << :robot_close
    end
  end
end

class GlobalErrorHook < RobotLab::Hook
  self.namespace = :global
  @errors = nil
  class << self
    attr_accessor :errors

    def on_error(ctx)
      errors << [ctx.robot.name, ctx.error.message]
    end
  end
end

class NetworkRobotBeforeHook < RobotLab::Hook
  self.namespace = :network
  @events = nil
  class << self
    attr_accessor :events

    def before_run(ctx)
      events << [:network_robot, ctx.network.name, ctx.task.name]
    end
  end
end

class GlobalNetworkRunHook < RobotLab::Hook
  self.namespace = :global
  @events = nil
  class << self
    attr_accessor :events

    def before_network_run(ctx)
      events << [:network_start, ctx.network.name]
    end
  end
end

class GlobalTaskHook < RobotLab::Hook
  self.namespace = :global
  @events = nil
  class << self
    attr_accessor :events

    def before_task(ctx)
      events << [:task_start, ctx.task_name, ctx.robot.name]
    end
  end
end

class ShortCircuitToolHook < RobotLab::Hook
  self.namespace = :global
  @events = nil
  class << self
    attr_accessor :events

    def around_tool_call(ctx)
      events << [ctx.tool_name, ctx.tool_args]
      ctx.tool_result = "short"
    end
  end
end

class PerRunToolHook < RobotLab::Hook
  self.namespace = :per_run
  @events = nil
  class << self
    attr_accessor :events

    def around_tool_call(ctx)
      events << ctx.tool_name
      ctx.tool_result = "short"
    end
  end
end

# ---------------------------------------------------------------------------

class RobotLab::HooksTest < Minitest::Test
  def setup
    RobotLab.clear_hooks!
  end

  def teardown
    RobotLab.clear_hooks!
  end

  def test_global_robot_and_per_run_hooks_fire_in_order_with_dot_context
    events = []
    GlobalBeforeHook.events = events
    RobotAfterHook.events   = events
    RuntimeBeforeHook.events = events

    robot = hooked_robot("hooked")
    RobotLab.on(GlobalBeforeHook)
    robot.on(RobotAfterHook)

    result = robot.run("original", hooks: RuntimeBeforeHook)

    assert_equal "changed response", result.reply
    assert_equal [
      [:global_before, "hooked", "original", true],
      [:runtime_before, "changed"],
      [:robot_after, "changed response", true]
    ], events
  end

  def test_around_run_hooks_wrap_the_robot_run
    events = []
    GlobalAroundHook.events = events
    RobotAroundHook.events  = events

    robot = hooked_robot("around")
    RobotLab.on(GlobalAroundHook)
    robot.on(RobotAroundHook)

    robot.run("go")

    assert_equal [[:global_open, "around"], :robot_open, :robot_close, :global_close], events
  end

  def test_on_error_fires_and_reraises
    errors = []
    GlobalErrorHook.errors = errors

    robot = build_robot(name: "error_bot", system_prompt: "raise")
    robot.instance_variable_get(:@chat).define_singleton_method(:ask) { |_message = nil, **_kwargs| raise "boom" }

    RobotLab.on(GlobalErrorHook)

    assert_raises(RuntimeError) { robot.run("explode") }
    assert_equal [%w[error_bot boom]], errors
  end

  def test_network_task_and_network_scoped_robot_hooks_fire
    events = []
    NetworkRobotBeforeHook.events  = events
    GlobalNetworkRunHook.events    = events
    GlobalTaskHook.events          = events

    robot   = hooked_robot("worker")
    network = RobotLab::Network.new(name: "hooks")
    network.on(NetworkRobotBeforeHook)
    network.task(:worker, robot, depends_on: :none)

    RobotLab.on(GlobalNetworkRunHook)
    RobotLab.on(GlobalTaskHook)

    network.run(message: "hello")

    assert_equal [
      [:network_start, "hooks"],
      [:task_start, :worker, "worker"],
      [:network_robot, "hooks", :worker]
    ], events
  end

  def test_tool_call_hooks_can_observe_and_short_circuit
    events = []
    ShortCircuitToolHook.events = events

    tool = Class.new(RobotLab::Tool) do
      def execute(**)
        "called"
      end
    end.new

    RobotLab.on(ShortCircuitToolHook)

    assert_equal "short", tool.call({ "value" => 1 })
    assert_equal [[tool.name, { "value" => 1 }]], events
  end

  def test_per_run_tool_hooks_are_available_during_robot_run
    events = []
    PerRunToolHook.events = events

    tool = Class.new(RobotLab::Tool) do
      def execute(**)
        "called"
      end
    end.new
    robot = hooked_robot("tool_bot")
    tool.robot = robot

    RobotLab.with_hook_scope([RobotLab.hooks, robot.hooks], [PerRunToolHook]) do
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
