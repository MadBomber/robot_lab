# frozen_string_literal: true

require "test_helper"

class RobotLab::Robot::DelegateFatalTest < Minitest::Test
  def test_async_delegate_rejects_future_when_worker_raises_non_standard_error
    delegator = build_robot(name: "boss", system_prompt: "x")
    worker    = build_robot(name: "worker", system_prompt: "x")
    worker.define_singleton_method(:run) { |*, **| raise NotImplementedError, "boom" }

    future = delegator.delegate(to: worker, task: "t", async: true)

    error = assert_raises(NotImplementedError) { future.value(timeout: 2) }
    assert_equal "boom", error.message
    assert_predicate future, :resolved?
  end
end
