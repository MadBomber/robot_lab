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

# ---------------------------------------------------------------------------
# Compaction hook handler classes
# ---------------------------------------------------------------------------

class BeforeCompactionHook < RobotLab::Hook
  self.namespace = :before_compaction_hook
  @events = nil
  class << self
    attr_accessor :events

    def before_compaction(ctx)
      events << [:before, ctx.robot.name, ctx.strategy, ctx.messages_before.size]
    end
  end
end

class AfterCompactionHook < RobotLab::Hook
  self.namespace = :after_compaction_hook
  @events = nil
  class << self
    attr_accessor :events

    def after_compaction(ctx)
      events << [:after, ctx.compacted_messages&.size]
    end
  end
end

class AroundCompactionHook < RobotLab::Hook
  self.namespace = :around_compaction_hook
  @events = nil
  class << self
    attr_accessor :events

    def around_compaction(ctx, &block)
      events << :open
      block.call
      events << :close
    end
  end
end

class OnCompactionHook < RobotLab::Hook
  self.namespace = :on_compaction_hook
  @events = nil
  class << self
    attr_accessor :events, :replacement

    def on_compaction(ctx)
      events << :on_compaction_called
      ctx.compacted_messages = replacement if replacement
    end
  end
end

# ---------------------------------------------------------------------------
# Learn hook handler classes
# ---------------------------------------------------------------------------

class BeforeLearnHook < RobotLab::Hook
  self.namespace = :before_learn_hook
  @events = nil
  class << self
    attr_accessor :events

    def before_learn(ctx)
      events << [:before, ctx.robot.name, ctx.text, ctx.learnings_before.dup]
    end
  end
end

class AfterLearnHook < RobotLab::Hook
  self.namespace = :after_learn_hook
  @events = nil
  class << self
    attr_accessor :events

    def after_learn(ctx)
      events << [:after, ctx.text, ctx.stored]
    end
  end
end

class AroundLearnHook < RobotLab::Hook
  self.namespace = :around_learn_hook
  @events = nil
  class << self
    attr_accessor :events

    def around_learn(ctx, &block)
      events << :open
      block.call
      events << :close
    end
  end
end

class OnLearnHook < RobotLab::Hook
  self.namespace = :on_learn_hook
  @events = nil
  class << self
    attr_accessor :events

    def on_learn(ctx)
      events << [:on_learn, ctx.text, ctx.stored]
    end
  end
end

class RobotLabLearnHooksTest < Minitest::Test
  def setup
    RobotLab.hooks.clear
    BeforeLearnHook.events = []
    AfterLearnHook.events  = []
    AroundLearnHook.events = []
    OnLearnHook.events     = []
  end

  def teardown
    RobotLab.hooks.clear
  end

  def test_before_learn_fires_with_text_and_snapshot
    robot = build_robot(name: "learner", system_prompt: "hi")
    robot.learn("first fact")
    RobotLab.on(BeforeLearnHook)
    robot.learn("second fact")
    assert_equal [[:before, "learner", "second fact", ["first fact"]]], BeforeLearnHook.events
  end

  def test_after_learn_fires_with_stored_true_when_new
    robot = build_robot(name: "learner", system_prompt: "hi")
    RobotLab.on(AfterLearnHook)
    robot.learn("brand new insight")
    assert_equal [[:after, "brand new insight", true]], AfterLearnHook.events
  end

  def test_after_learn_fires_with_stored_false_when_deduplicated
    robot = build_robot(name: "learner", system_prompt: "hi")
    robot.learn("always check the cache before fetching")
    RobotLab.on(AfterLearnHook)
    robot.learn("check the cache")  # subset — already covered
    assert_equal [[:after, "check the cache", false]], AfterLearnHook.events
  end

  def test_around_learn_wraps_core_block
    robot = build_robot(name: "learner", system_prompt: "hi")
    RobotLab.on(AroundLearnHook)
    robot.learn("something")
    assert_equal %i[open close], AroundLearnHook.events
  end

  def test_on_learn_fires_after_session_storage
    robot = build_robot(name: "learner", system_prompt: "hi")
    RobotLab.on(OnLearnHook)
    robot.learn("persist this")
    assert_equal [[:on_learn, "persist this", true]], OnLearnHook.events
    assert_includes robot.learnings, "persist this"
  end

  def test_on_learn_fires_even_when_deduplicated
    robot = build_robot(name: "learner", system_prompt: "hi")
    robot.learn("always check the cache before fetching")
    RobotLab.on(OnLearnHook)
    robot.learn("check the cache")
    assert_equal [[:on_learn, "check the cache", false]], OnLearnHook.events
  end

  def test_learn_hooks_not_fired_when_text_empty
    robot = build_robot(name: "learner", system_prompt: "hi")
    RobotLab.on(BeforeLearnHook)
    robot.learn("")
    robot.learn("   ")
    assert_empty BeforeLearnHook.events
  end

  def test_learn_hooks_fire_on_robot_level_registration
    robot = build_robot(name: "learner", system_prompt: "hi")
    robot.on(AfterLearnHook)
    robot.learn("robot-scoped learning")
    assert_equal [[:after, "robot-scoped learning", true]], AfterLearnHook.events
  end

  def test_on_learn_can_implement_extension_persistence
    persisted = []
    robot     = build_robot(name: "learner", system_prompt: "hi")

    stub_hook = Class.new(RobotLab::Hook) do
      self.namespace = :stub_persist
      define_singleton_method(:on_learn) { |ctx| persisted << ctx.text if ctx.stored }
    end

    robot.on(stub_hook)
    robot.learn("always check the cache before fetching")
    robot.learn("check the cache")  # subset — covered by existing, stored=false

    assert_equal ["always check the cache before fetching"], persisted
  end
end

class RobotLabCompactionHooksTest < Minitest::Test
  FakeMsg = Struct.new(:content, :role) do
    def tool_calls = nil
    def stop_reason = :stop
    def text? = true
    def tool_use? = false
    def system? = role == :system
    def user? = role == :user
    def assistant? = role == :assistant
  end

  def setup
    RobotLab.hooks.clear
    BeforeCompactionHook.events  = []
    AfterCompactionHook.events   = []
    AroundCompactionHook.events  = []
    OnCompactionHook.events      = []
    OnCompactionHook.replacement = nil
  end

  def teardown
    RobotLab.hooks.clear
  end

  def test_before_compaction_fires_with_context
    robot = compactable_robot(threshold: 0.0)
    RobotLab.on(BeforeCompactionHook)
    robot.send(:maybe_compact)
    assert_equal [[:before, robot.name, :context_window, 1]], BeforeCompactionHook.events
  end

  def test_after_compaction_fires_with_compacted_messages
    robot = compactable_robot(threshold: 0.0)
    robot.define_singleton_method(:compress_history) { nil }
    RobotLab.on(AfterCompactionHook)
    robot.send(:maybe_compact)
    assert_equal 1, AfterCompactionHook.events.size
    event = AfterCompactionHook.events.first
    assert_equal :after, event[0]
    refute_nil event[1]
  end

  def test_around_compaction_wraps_core_block
    robot = compactable_robot(threshold: 0.0)
    robot.define_singleton_method(:compress_history) { nil }
    RobotLab.on(AroundCompactionHook)
    robot.send(:maybe_compact)
    assert_equal %i[open close], AroundCompactionHook.events
  end

  def test_on_compaction_replaces_core_compaction
    compress_called  = false
    replaced_with    = nil
    replacement_msgs = [FakeMsg.new("replacement", :user)]
    robot = compactable_robot(threshold: 0.0)
    robot.define_singleton_method(:compress_history) { compress_called = true }
    robot.define_singleton_method(:replace_messages) { |msgs| replaced_with = msgs }
    OnCompactionHook.replacement = replacement_msgs
    RobotLab.on(OnCompactionHook)
    robot.send(:maybe_compact)
    refute compress_called, "compress_history should not be called when on_compaction handles it"
    assert_includes OnCompactionHook.events, :on_compaction_called
    assert_same replacement_msgs, replaced_with
  end

  def test_on_compaction_without_handler_runs_default
    compress_called = false
    robot = compactable_robot(threshold: 0.0)
    robot.define_singleton_method(:compress_history) { compress_called = true }
    RobotLab.on(OnCompactionHook)
    robot.send(:maybe_compact)
    assert compress_called, "compress_history should run when on_compaction does not handle it"
  end

  def test_compaction_hooks_not_fired_when_auto_compact_none
    robot = build_robot(name: "bot", system_prompt: "hi",
                        config: RobotLab::RunConfig.new(auto_compact: :none))
    inject_fake_message(robot)
    RobotLab.on(BeforeCompactionHook)
    robot.send(:maybe_compact)
    assert_empty BeforeCompactionHook.events
  end

  def test_compaction_hooks_not_fired_when_messages_empty
    robot = build_robot(name: "bot", system_prompt: "hi",
                        config: RobotLab::RunConfig.new(auto_compact: :context_window))
    RobotLab.on(BeforeCompactionHook)
    robot.send(:maybe_compact)
    assert_empty BeforeCompactionHook.events
  end

  def test_compaction_hooks_not_fired_when_under_threshold
    robot = build_robot(name: "bot", system_prompt: "hi",
                        config: RobotLab::RunConfig.new(auto_compact: :context_window,
                                                        compact_threshold: 0.99))
    inject_fake_message(robot)
    RobotLab.on(BeforeCompactionHook)
    robot.send(:maybe_compact)
    assert_empty BeforeCompactionHook.events
  end

  def test_proc_strategy_fires_hooks_with_custom_strategy
    my_proc = ->(_r) {}
    robot   = build_robot(name: "bot", system_prompt: "hi",
                          config: RobotLab::RunConfig.new(auto_compact: my_proc))
    inject_fake_message(robot)
    RobotLab.on(BeforeCompactionHook)
    robot.send(:maybe_compact)
    assert_equal :custom, BeforeCompactionHook.events.first&.dig(2)
  end

  private

  def compactable_robot(threshold:)
    build_robot(name: "compact-bot", system_prompt: "hi",
                config: RobotLab::RunConfig.new(auto_compact: :context_window,
                                                compact_threshold: threshold)).tap do |robot|
      inject_fake_message(robot)
    end
  end

  def inject_fake_message(robot)
    robot.instance_variable_get(:@chat)
         .instance_variable_set(:@messages, [FakeMsg.new("hello", :user)])
  end
end
