# frozen_string_literal: true

require "test_helper"

class RobotLab::StateTest < Minitest::Test
  def test_state_initialization_with_defaults
    state = RobotLab::State.new

    assert_empty state.data.to_h
    assert_empty state.results
    assert_empty state.messages
    assert_nil state.thread_id
  end

  def test_state_initialization_with_data
    state = RobotLab::State.new(
      data: { user_id: 123, category: "support" },
      thread_id: "thread_abc"
    )

    assert_equal 123, state.data[:user_id]
    assert_equal "support", state.data[:category]
    assert_equal "thread_abc", state.thread_id
  end

  def test_state_data_proxy
    state = RobotLab::State.new(data: { counter: 0 })

    state.data[:counter] = 5
    state.data[:new_key] = "value"

    assert_equal 5, state.data[:counter]
    assert_equal "value", state.data[:new_key]
  end

  def test_state_append_result
    state = RobotLab::State.new
    result = RobotLab::RobotResult.new(
      robot_name: "test_robot",
      output: [RobotLab::TextMessage.new(role: :assistant, content: "Hello")]
    )

    state.append_result(result)

    assert_equal 1, state.results.length
    assert_equal "test_robot", state.results.first.robot_name
  end

  def test_state_results_immutable
    state = RobotLab::State.new
    result = RobotLab::RobotResult.new(robot_name: "robot", output: [])
    state.append_result(result)

    external_results = state.results
    external_results.clear

    assert_equal 1, state.results.length
  end

  def test_state_format_history
    state = RobotLab::State.new(
      messages: [RobotLab::TextMessage.new(role: :user, content: "User input")]
    )

    output = [RobotLab::TextMessage.new(role: :assistant, content: "Robot response")]
    result = RobotLab::RobotResult.new(robot_name: "robot", output: output)
    state.append_result(result)

    history = state.format_history

    assert_equal 2, history.length
    assert_equal "user", history.first.role
  end

  def test_state_format_history_with_custom_formatter
    state = RobotLab::State.new
    output = [RobotLab::TextMessage.new(role: :assistant, content: "Response")]
    result = RobotLab::RobotResult.new(robot_name: "robot", output: output)
    state.append_result(result)

    formatter = ->(r) { r.output }
    history = state.format_history(formatter: formatter)

    assert_equal 1, history.length
  end

  def test_state_clone
    original = RobotLab::State.new(
      data: { key: "value" },
      thread_id: "thread_1"
    )
    result = RobotLab::RobotResult.new(robot_name: "robot", output: [])
    original.append_result(result)

    cloned = original.clone

    assert_equal "value", cloned.data[:key]
    assert_equal 1, cloned.results.length
    assert_equal "thread_1", cloned.thread_id

    # Verify independence
    cloned.data[:key] = "modified"
    assert_equal "value", original.data[:key]
  end

  def test_state_to_h
    state = RobotLab::State.new(
      data: { a: 1 },
      thread_id: "thread_x"
    )

    hash = state.to_h

    assert_equal({ a: 1 }, hash[:data])
    assert_equal "thread_x", hash[:thread_id]
  end
end
