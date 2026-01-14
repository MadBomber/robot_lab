# frozen_string_literal: true

require "test_helper"

class RobotLab::Streaming::SequenceCounterTest < Minitest::Test
  def test_counter_starts_at_zero
    counter = RobotLab::Streaming::SequenceCounter.new

    assert_equal 0, counter.current
  end

  def test_counter_starts_at_custom_value
    counter = RobotLab::Streaming::SequenceCounter.new(start: 100)

    assert_equal 100, counter.current
  end

  def test_counter_increments
    counter = RobotLab::Streaming::SequenceCounter.new

    assert_equal 1, counter.next
    assert_equal 2, counter.next
    assert_equal 3, counter.next
  end

  def test_counter_current_does_not_increment
    counter = RobotLab::Streaming::SequenceCounter.new

    counter.next
    counter.next

    assert_equal 2, counter.current
    assert_equal 2, counter.current
  end

  def test_counter_reset
    counter = RobotLab::Streaming::SequenceCounter.new
    counter.next
    counter.next

    counter.reset(10)

    assert_equal 10, counter.current
  end

  def test_counter_reset_to_zero
    counter = RobotLab::Streaming::SequenceCounter.new
    counter.next

    counter.reset

    assert_equal 0, counter.current
  end
end

class RobotLab::Streaming::ContextTest < Minitest::Test
  def setup
    @events = []
    @publish = ->(event) { @events << event }
  end

  def test_context_initialization
    context = RobotLab::Streaming::Context.new(
      run_id: "run_123",
      message_id: "msg_456",
      scope: "network",
      publish: @publish
    )

    assert_equal "run_123", context.run_id
    assert_equal "msg_456", context.message_id
    assert_equal "network", context.scope
  end

  def test_publish_event
    context = RobotLab::Streaming::Context.new(
      run_id: "run_1",
      message_id: "msg_1",
      scope: "robot",
      publish: @publish
    )

    context.publish_event(event: "text.delta", data: { delta: "Hello" })

    assert_equal 1, @events.length

    event = @events.first
    assert_equal "text.delta", event[:event]
    assert_equal "Hello", event[:data][:delta]
    assert_equal "run_1", event[:data][:run_id]
    assert_equal 1, event[:sequence_number]
  end

  def test_publish_event_increments_sequence
    context = RobotLab::Streaming::Context.new(
      run_id: "run_1",
      message_id: "msg_1",
      scope: "robot",
      publish: @publish
    )

    context.publish_event(event: "event.a", data: {})
    context.publish_event(event: "event.b", data: {})
    context.publish_event(event: "event.c", data: {})

    assert_equal 1, @events[0][:sequence_number]
    assert_equal 2, @events[1][:sequence_number]
    assert_equal 3, @events[2][:sequence_number]
  end

  def test_create_child_context
    parent = RobotLab::Streaming::Context.new(
      run_id: "parent_run",
      message_id: "parent_msg",
      scope: "network",
      publish: @publish
    )

    child = parent.create_child_context("child_run")

    assert_equal "child_run", child.run_id
    assert_equal "parent_run", child.parent_run_id
    assert_equal "robot", child.scope
  end

  def test_child_context_shares_sequence_counter
    parent = RobotLab::Streaming::Context.new(
      run_id: "parent",
      message_id: "msg",
      scope: "network",
      publish: @publish
    )

    parent.publish_event(event: "parent.event", data: {})

    child = parent.create_child_context("child")
    child.publish_event(event: "child.event", data: {})

    assert_equal 1, @events[0][:sequence_number]
    assert_equal 2, @events[1][:sequence_number]
  end

  def test_generate_part_id
    context = RobotLab::Streaming::Context.new(
      run_id: "run_1",
      message_id: "message_id_123",
      scope: "robot",
      publish: @publish
    )

    part_id = context.generate_part_id

    assert part_id.start_with?("part_")
    assert part_id.length <= 40
  end

  def test_generate_step_id
    context = RobotLab::Streaming::Context.new(
      run_id: "run_1",
      message_id: "msg_1",
      scope: "robot",
      publish: @publish
    )

    step_id = context.generate_step_id("tool_call")

    assert step_id.include?("tool_call")
    assert step_id.start_with?("publish-")
  end

  def test_publish_event_handles_errors_gracefully
    error_publish = ->(_event) { raise "Publish failed!" }
    context = RobotLab::Streaming::Context.new(
      run_id: "run_1",
      message_id: "msg_1",
      scope: "robot",
      publish: error_publish
    )

    # Should not raise
    chunk = context.publish_event(event: "test", data: {})

    refute_nil chunk
  end
end

class RobotLab::Streaming::EventsTest < Minitest::Test
  def test_lifecycle_events
    assert RobotLab::Streaming::Events.lifecycle?("run.started")
    assert RobotLab::Streaming::Events.lifecycle?("run.completed")
    refute RobotLab::Streaming::Events.lifecycle?("text.delta")
  end

  def test_delta_events
    assert RobotLab::Streaming::Events.delta?("text.delta")
    assert RobotLab::Streaming::Events.delta?("tool_call.arguments.delta")
    refute RobotLab::Streaming::Events.delta?("run.started")
  end

  def test_valid_events
    assert RobotLab::Streaming::Events.valid?("run.started")
    assert RobotLab::Streaming::Events.valid?("text.delta")
    refute RobotLab::Streaming::Events.valid?("invalid.event")
  end
end
