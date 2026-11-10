# frozen_string_literal: true

require "test_helper"

class RobotLab::DelegationFutureTest < Minitest::Test
  def build_future(robot_name: "worker", delegated_by: "manager")
    RobotLab::DelegationFuture.new(robot_name: robot_name, delegated_by: delegated_by)
  end

  def test_readers_return_constructor_values
    future = build_future(robot_name: "summarizer", delegated_by: "boss")

    assert_equal "summarizer", future.robot_name
    assert_equal "boss", future.delegated_by
  end

  def test_resolved_is_false_before_resolve_and_true_after
    future = build_future

    refute_predicate future, :resolved?

    future.resolve!("done")

    assert_predicate future, :resolved?
  end

  def test_value_returns_the_resolved_value
    future = build_future
    future.resolve!(42)

    assert_equal 42, future.value
  end

  def test_value_blocks_until_another_thread_resolves
    future = build_future

    thread = Thread.new do
      future.value
    end

    # Let the consumer reach @cv.wait before resolving from here.
    wait_until { thread.status == "sleep" }
    future.resolve!("ready")

    assert_equal "ready", thread.value
  end

  def test_value_with_timeout_raises_when_unresolved
    future = build_future(robot_name: "slowpoke")

    error = assert_raises(RobotLab::DelegationFuture::DelegationTimeout) do
      future.value(timeout: 0.01)
    end

    assert_match(/slowpoke/, error.message)
  end

  def test_timeout_error_is_a_robot_lab_error
    assert_operator RobotLab::DelegationFuture::DelegationTimeout, :<, RobotLab::Error
  end

  def test_reject_causes_value_to_reraise_the_stored_error
    future = build_future
    boom = ArgumentError.new("delegation blew up")
    future.reject!(boom)

    assert_predicate future, :resolved?

    error = assert_raises(ArgumentError) { future.value }
    assert_same boom, error
  end

  def test_wait_alias_returns_the_resolved_value
    future = build_future
    future.resolve!("via wait")

    assert_equal "via wait", future.wait
  end

  def test_wait_alias_blocks_like_value
    future = build_future

    thread = Thread.new { future.wait }

    wait_until { thread.status == "sleep" }
    future.resolve!("woke up")

    assert_equal "woke up", thread.value
  end
end
