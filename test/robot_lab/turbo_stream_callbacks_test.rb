# frozen_string_literal: true

require 'test_helper'
require 'robot_lab/rails_integration/turbo_stream_callbacks'
require 'erb'

class TurboStreamCallbacksTest < Minitest::Test
  def setup
    # Ensure Turbo is not defined at the start of each test
    remove_turbo_stub if turbo_defined?
  end

  def teardown
    remove_turbo_stub if turbo_defined?
  end

  # --- available? ---

  def test_available_returns_false_when_turbo_not_defined
    assert_equal false, RobotLab::RailsIntegration::TurboStreamCallbacks.available?
  end

  def test_available_returns_true_when_turbo_defined
    stub_turbo_streams_channel
    assert_equal true, RobotLab::RailsIntegration::TurboStreamCallbacks.available?
  end

  # --- build_content_callback ---

  def test_build_content_callback_returns_a_proc
    callback = RobotLab::RailsIntegration::TurboStreamCallbacks.build_content_callback(
      stream_name: "test_stream"
    )
    assert_kind_of Proc, callback
  end

  def test_content_callback_escapes_html
    stub_turbo_streams_channel
    broadcasts = capture_broadcasts

    callback = RobotLab::RailsIntegration::TurboStreamCallbacks.build_content_callback(
      stream_name: "test_stream"
    )

    chunk = FakeChunk.new("<script>alert('xss')</script>")
    callback.call(chunk)

    assert_equal 1, broadcasts.size
    assert_includes broadcasts.first[:html], "&lt;script&gt;"
    refute_includes broadcasts.first[:html], "<script>"
  end

  def test_content_callback_skips_nil_content
    stub_turbo_streams_channel
    broadcasts = capture_broadcasts

    callback = RobotLab::RailsIntegration::TurboStreamCallbacks.build_content_callback(
      stream_name: "test_stream"
    )

    chunk = FakeChunk.new(nil)
    callback.call(chunk)

    assert_empty broadcasts
  end

  def test_content_callback_noop_when_turbo_unavailable
    # Turbo is not defined — callback should silently do nothing
    callback = RobotLab::RailsIntegration::TurboStreamCallbacks.build_content_callback(
      stream_name: "test_stream"
    )

    chunk = FakeChunk.new("Hello")
    # Should not raise
    callback.call(chunk)
  end

  def test_content_callback_uses_custom_target
    stub_turbo_streams_channel
    broadcasts = capture_broadcasts

    callback = RobotLab::RailsIntegration::TurboStreamCallbacks.build_content_callback(
      stream_name: "test_stream",
      target: "custom_target"
    )

    chunk = FakeChunk.new("Hello")
    callback.call(chunk)

    assert_equal "custom_target", broadcasts.first[:target]
  end

  def test_content_callback_broadcasts_to_correct_stream
    stub_turbo_streams_channel
    broadcasts = capture_broadcasts

    callback = RobotLab::RailsIntegration::TurboStreamCallbacks.build_content_callback(
      stream_name: "my_stream_123"
    )

    chunk = FakeChunk.new("Hello")
    callback.call(chunk)

    assert_equal "my_stream_123", broadcasts.first[:stream_name]
  end

  def test_content_callback_handles_string_chunks
    stub_turbo_streams_channel
    broadcasts = capture_broadcasts

    callback = RobotLab::RailsIntegration::TurboStreamCallbacks.build_content_callback(
      stream_name: "test_stream"
    )

    # Pass a plain string (no .content method)
    callback.call("plain text")

    assert_equal 1, broadcasts.size
    assert_equal "plain text", broadcasts.first[:html]
  end

  # --- build_tool_call_callback ---

  def test_build_tool_call_callback_returns_a_proc
    callback = RobotLab::RailsIntegration::TurboStreamCallbacks.build_tool_call_callback(
      stream_name: "test_stream"
    )
    assert_kind_of Proc, callback
  end

  def test_tool_call_callback_escapes_tool_name
    stub_turbo_streams_channel
    broadcasts = capture_broadcasts

    callback = RobotLab::RailsIntegration::TurboStreamCallbacks.build_tool_call_callback(
      stream_name: "test_stream"
    )

    tool_call = FakeToolCall.new("<img onerror=alert(1)>")
    callback.call(tool_call)

    assert_equal 1, broadcasts.size
    assert_includes broadcasts.first[:html], "&lt;img onerror=alert(1)&gt;"
    refute_includes broadcasts.first[:html], "<img"
  end

  def test_tool_call_callback_noop_when_turbo_unavailable
    callback = RobotLab::RailsIntegration::TurboStreamCallbacks.build_tool_call_callback(
      stream_name: "test_stream"
    )

    tool_call = FakeToolCall.new("search")
    # Should not raise
    callback.call(tool_call)
  end

  def test_tool_call_callback_uses_custom_target
    stub_turbo_streams_channel
    broadcasts = capture_broadcasts

    callback = RobotLab::RailsIntegration::TurboStreamCallbacks.build_tool_call_callback(
      stream_name: "test_stream",
      target: "my_tools"
    )

    tool_call = FakeToolCall.new("search")
    callback.call(tool_call)

    assert_equal "my_tools", broadcasts.first[:target]
  end

  private

  # Minimal stub that captures broadcast_append_to calls
  FakeChunk    = Struct.new(:content)
  FakeToolCall = Struct.new(:name)

  def turbo_defined?
    defined?(Turbo::StreamsChannel)
  end

  def stub_turbo_streams_channel
    return if turbo_defined?

    turbo_mod = Module.new
    Object.const_set(:Turbo, turbo_mod)
    streams_channel = Class.new do
      def self.broadcasts
        @broadcasts ||= []
      end

      def self.broadcast_append_to(stream_name, target:, html:)
        broadcasts << { stream_name: stream_name, target: target, html: html }
      end

      def self.broadcast_replace_to(stream_name, target:, html:)
        broadcasts << { stream_name: stream_name, target: target, html: html, action: :replace }
      end
    end
    turbo_mod.const_set(:StreamsChannel, streams_channel)
  end

  def capture_broadcasts
    Turbo::StreamsChannel.broadcasts.clear
    Turbo::StreamsChannel.broadcasts
  end

  def remove_turbo_stub
    Object.send(:remove_const, :Turbo) if defined?(Turbo)
  end
end
