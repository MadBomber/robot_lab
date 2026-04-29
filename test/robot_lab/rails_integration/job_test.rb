# frozen_string_literal: true

require 'test_helper'
require 'erb'

# ActiveSupport extensions needed for job.rb class load and setup_thread
require 'active_support/core_ext/numeric/time'       # 5.seconds in retry_on
require 'active_support/core_ext/string/inflections' # "ClassName".constantize

# Time.current needs the full AS stack (IsolatedExecutionState) which we don't have here.
# Override it unconditionally so job.rb's setup_thread works without a full Rails boot.
# In production, Rails sets this up properly; this shim is test-only.
class << Time
  def current = now
end

# Stub ActiveJob::Base so Job can be loaded without a full Rails stack.
unless defined?(ActiveJob::Base)
  module ActiveJob
    class DeserializationError < StandardError; end
    class Base
      def self.retry_on(*) = nil
      def self.discard_on(*) = nil
      def self.queue_as(*) = nil
    end
  end
end

require 'robot_lab/rails_integration/turbo_stream_callbacks'
require 'robot_lab/rails_integration/job'

class RobotLab::RailsIntegration::JobTest < Minitest::Test
  # ── Fakes ────────────────────────────────────────────────────────────────────

  FakeResult = Struct.new(:robot_name, :stop_reason, :checksum) do
    def export = { output: [], tool_calls: [] }
  end

  FakeRobot = Struct.new(:result) do
    def run(message, **) = result
  end

  # Spy that records keyword args passed to .build
  class SpyRobotClass
    class << self
      attr_reader :last_build_opts

      def build(**opts)
        @last_build_opts = opts
        FakeRobot.new(FakeResult.new("spy", "end_turn", "abc"))
      end

      def reset! = @last_build_opts = nil
    end
  end

  # Minimal thread record double
  FakeThread = Struct.new(:id) do
    def results = FakeResults.new
    def update!(**) = nil
  end

  FakeResults = Class.new do
    def maximum(*) = 0
    def create!(**) = nil
  end

  # Concrete subclass used across most tests
  class TestJob < RobotLab::RailsIntegration::Job
    robot_class SpyRobotClass
  end

  def setup
    SpyRobotClass.reset!
    remove_turbo_stub if turbo_defined?
  end

  def teardown
    remove_turbo_stub if turbo_defined?
  end

  # ── robot_class DSL ──────────────────────────────────────────────────────────

  def test_robot_class_defaults_to_nil
    klass = Class.new(RobotLab::RailsIntegration::Job)
    assert_nil klass.robot_class
  end

  def test_robot_class_setter_and_getter
    klass = Class.new(RobotLab::RailsIntegration::Job)
    klass.robot_class SpyRobotClass
    assert_equal SpyRobotClass, klass.robot_class
  end

  def test_robot_class_is_per_subclass
    a = Class.new(RobotLab::RailsIntegration::Job)
    b = Class.new(RobotLab::RailsIntegration::Job)
    a.robot_class SpyRobotClass
    assert_equal SpyRobotClass, a.robot_class
    assert_nil b.robot_class
  end

  # ── resolve_robot_class ──────────────────────────────────────────────────────

  def test_resolve_robot_class_uses_dsl_when_no_runtime_arg
    klass = TestJob.new.send(:resolve_robot_class, nil)
    assert_equal SpyRobotClass, klass
  end

  def test_resolve_robot_class_accepts_class_constant
    klass = TestJob.new.send(:resolve_robot_class, SpyRobotClass)
    assert_equal SpyRobotClass, klass
  end

  def test_resolve_robot_class_accepts_string
    name  = "RobotLab::RailsIntegration::JobTest::SpyRobotClass"
    klass = TestJob.new.send(:resolve_robot_class, name)
    assert_equal SpyRobotClass, klass
  end

  def test_resolve_robot_class_runtime_overrides_dsl
    other = Class.new { def self.build(**) = nil }
    klass = TestJob.new.send(:resolve_robot_class, other)
    assert_equal other, klass
  end

  def test_resolve_robot_class_raises_when_nothing_set
    job = Class.new(RobotLab::RailsIntegration::Job).new
    assert_raises(ArgumentError) { job.send(:resolve_robot_class, nil) }
  end

  # ── setup_thread ─────────────────────────────────────────────────────────────

  def test_setup_thread_returns_nil_when_no_thread_id
    result = TestJob.new.send(:setup_thread, nil, "hello")
    assert_nil result
  end

  def test_setup_thread_constantizes_and_returns_thread
    fake_thread = FakeThread.new(1)
    fake_model  = Class.new do
      define_singleton_method(:find_or_create_by_session_id) { |_| fake_thread }
    end

    Object.const_set(:RobotLabThread, fake_model)
    result = TestJob.new.send(:setup_thread, "tid-123", "hello")
    assert_equal fake_thread, result
  ensure
    Object.send(:remove_const, :RobotLabThread) if defined?(RobotLabThread)
  end

  # ── build_robot ──────────────────────────────────────────────────────────────

  def test_build_robot_plain_when_no_thread_id
    TestJob.new.send(:build_robot, SpyRobotClass, nil)
    refute SpyRobotClass.last_build_opts.key?(:on_content)
    refute SpyRobotClass.last_build_opts.key?(:on_tool_call)
  end

  def test_build_robot_plain_when_thread_id_but_no_turbo
    TestJob.new.send(:build_robot, SpyRobotClass, "tid-123")
    refute SpyRobotClass.last_build_opts.key?(:on_content)
    refute SpyRobotClass.last_build_opts.key?(:on_tool_call)
  end

  def test_build_robot_wires_callbacks_when_thread_id_and_turbo
    stub_turbo_streams_channel
    TestJob.new.send(:build_robot, SpyRobotClass, "tid-123")
    assert SpyRobotClass.last_build_opts.key?(:on_content)
    assert SpyRobotClass.last_build_opts.key?(:on_tool_call)
    assert_kind_of Proc, SpyRobotClass.last_build_opts[:on_content]
    assert_kind_of Proc, SpyRobotClass.last_build_opts[:on_tool_call]
  end

  def test_build_robot_uses_correct_stream_name
    stub_turbo_streams_channel
    broadcasts = capture_broadcasts

    TestJob.new.send(:build_robot, SpyRobotClass, "tid-abc")

    # Fire the on_content callback with a fake chunk to check the stream name
    chunk = Struct.new(:content).new("hello")
    SpyRobotClass.last_build_opts[:on_content].call(chunk)

    assert_equal "robot_lab_thread_tid-abc", broadcasts.first[:stream_name]
  end

  # ── broadcast_completion ─────────────────────────────────────────────────────

  def test_broadcast_completion_noop_when_turbo_unavailable
    TestJob.new.send(:broadcast_completion, "tid-123")
  end

  def test_broadcast_completion_sends_replace_to_correct_stream
    stub_turbo_streams_channel
    broadcasts = capture_broadcasts

    TestJob.new.send(:broadcast_completion, "tid-123")

    assert_equal 1, broadcasts.size
    assert_equal "robot_lab_thread_tid-123", broadcasts.first[:stream_name]
    assert_equal "robot_status", broadcasts.first[:target]
    assert_includes broadcasts.first[:html], "complete"
  end

  # ── broadcast_error ──────────────────────────────────────────────────────────

  def test_broadcast_error_noop_when_turbo_unavailable
    TestJob.new.send(:broadcast_error, "tid-123", RuntimeError.new("boom"))
  end

  def test_broadcast_error_sends_append_with_escaped_message
    stub_turbo_streams_channel
    broadcasts = capture_broadcasts

    TestJob.new.send(:broadcast_error, "tid-123", RuntimeError.new("<b>oops</b>"))

    assert_equal 1, broadcasts.size
    assert_equal "robot_lab_thread_tid-123", broadcasts.first[:stream_name]
    assert_includes broadcasts.first[:html], "&lt;b&gt;"
    refute_includes broadcasts.first[:html], "<b>"
  end

  # ── turbo_available? ─────────────────────────────────────────────────────────

  def test_turbo_available_false_without_turbo
    refute TestJob.new.send(:turbo_available?)
  end

  def test_turbo_available_true_with_turbo
    stub_turbo_streams_channel
    assert TestJob.new.send(:turbo_available?)
  end

  private

  def turbo_defined? = defined?(Turbo::StreamsChannel)

  def stub_turbo_streams_channel
    return if turbo_defined?

    turbo_mod = Module.new
    Object.const_set(:Turbo, turbo_mod)
    channel = Class.new do
      def self.broadcasts    = @broadcasts ||= []
      def self.broadcast_append_to(stream_name, target:, html:)
        broadcasts << { stream_name:, target:, html: }
      end
      def self.broadcast_replace_to(stream_name, target:, html:)
        broadcasts << { stream_name:, target:, html:, action: :replace }
      end
    end
    turbo_mod.const_set(:StreamsChannel, channel)
  end

  def capture_broadcasts
    Turbo::StreamsChannel.broadcasts.clear
    Turbo::StreamsChannel.broadcasts
  end

  def remove_turbo_stub
    Object.send(:remove_const, :Turbo) if defined?(Turbo)
  end
end
