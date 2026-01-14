# frozen_string_literal: true

require "test_helper"

class RobotLab::History::ConfigTest < Minitest::Test
  def test_config_initialization_with_callbacks
    config = RobotLab::History::Config.new(
      create_thread: ->(state:, input:, **) { { thread_id: "t1" } },
      get: ->(thread_id:, **) { [] }
    )

    assert config.configured?
  end

  def test_config_not_configured_without_callbacks
    config = RobotLab::History::Config.new

    refute config.configured?
  end

  def test_create_thread_calls_callback
    called_with = nil
    config = RobotLab::History::Config.new(
      create_thread: ->(state:, input:, **) {
        called_with = { state: state, input: input }
        { thread_id: "new_thread" }
      }
    )

    state = RobotLab::State.new
    result = config.create_thread!(state: state, input: "Hello")

    assert_equal state, called_with[:state]
    assert_equal "Hello", called_with[:input]
    assert_equal "new_thread", result[:thread_id]
  end

  def test_create_thread_raises_without_callback
    config = RobotLab::History::Config.new

    assert_raises(RobotLab::History::HistoryError) do
      config.create_thread!(state: RobotLab::State.new, input: "test")
    end
  end

  def test_create_thread_raises_without_thread_id
    config = RobotLab::History::Config.new(
      create_thread: ->(state:, input:, **) { { other: "value" } }
    )

    assert_raises(RobotLab::History::HistoryError) do
      config.create_thread!(state: RobotLab::State.new, input: "test")
    end
  end

  def test_get_calls_callback
    results = [
      RobotLab::RobotResult.new(robot_name: "robot", output: [])
    ]

    config = RobotLab::History::Config.new(
      get: ->(thread_id:, **) { results }
    )

    fetched = config.get!(thread_id: "t1")

    assert_equal results, fetched
  end

  def test_get_raises_without_callback
    config = RobotLab::History::Config.new

    assert_raises(RobotLab::History::HistoryError) do
      config.get!(thread_id: "t1")
    end
  end

  def test_append_user_message_calls_callback
    called_with = nil
    config = RobotLab::History::Config.new(
      append_user_message: ->(thread_id:, message:, **) {
        called_with = { thread_id: thread_id, message: message }
      }
    )

    message = RobotLab::UserMessage.new("Test")
    config.append_user_message!(thread_id: "t1", message: message)

    assert_equal "t1", called_with[:thread_id]
    assert_equal message, called_with[:message]
  end

  def test_append_user_message_noop_without_callback
    config = RobotLab::History::Config.new

    # Should not raise
    config.append_user_message!(thread_id: "t1", message: RobotLab::UserMessage.new("test"))
  end

  def test_append_results_calls_callback
    called_with = nil
    config = RobotLab::History::Config.new(
      append_results: ->(thread_id:, new_results:, **) {
        called_with = { thread_id: thread_id, new_results: new_results }
      }
    )

    results = [RobotLab::RobotResult.new(robot_name: "robot", output: [])]
    config.append_results!(thread_id: "t1", new_results: results)

    assert_equal "t1", called_with[:thread_id]
    assert_equal results, called_with[:new_results]
  end
end

class RobotLab::History::ThreadManagerTest < Minitest::Test
  def setup
    @threads = {}
    @results = Hash.new { |h, k| h[k] = [] }

    @config = RobotLab::History::Config.new(
      create_thread: ->(state:, input:, **) {
        id = "thread_#{@threads.size + 1}"
        @threads[id] = { state: state, input: input }
        { thread_id: id }
      },
      get: ->(thread_id:, **) { @results[thread_id] },
      append_results: ->(thread_id:, new_results:, **) {
        @results[thread_id].concat(new_results)
      }
    )

    @manager = RobotLab::History::ThreadManager.new(@config)
  end

  def test_create_thread
    state = RobotLab::State.new
    thread_id = @manager.create_thread(state: state, input: "Hello")

    assert_equal "thread_1", thread_id
    assert @threads.key?("thread_1")
  end

  def test_get_history
    result = RobotLab::RobotResult.new(robot_name: "robot", output: [])
    @results["t1"] << result

    history = @manager.get_history("t1")

    assert_equal 1, history.length
    assert_equal result, history.first
  end

  def test_append_results
    results = [
      RobotLab::RobotResult.new(robot_name: "robot1", output: []),
      RobotLab::RobotResult.new(robot_name: "robot2", output: [])
    ]

    @manager.append_results(thread_id: "t1", results: results)

    assert_equal 2, @results["t1"].length
  end

  def test_load_state
    result = RobotLab::RobotResult.new(robot_name: "robot", output: [])
    @results["t1"] << result

    state = RobotLab::State.new
    loaded = @manager.load_state(thread_id: "t1", state: state)

    assert_equal "t1", loaded.thread_id
    assert_equal 1, loaded.results.length
  end

  def test_save_state
    state = RobotLab::State.new
    state.append_result(RobotLab::RobotResult.new(robot_name: "robot", output: []))

    @manager.save_state(thread_id: "t1", state: state)

    assert_equal 1, @results["t1"].length
  end

  def test_save_state_with_offset
    state = RobotLab::State.new
    state.append_result(RobotLab::RobotResult.new(robot_name: "old", output: []))
    state.append_result(RobotLab::RobotResult.new(robot_name: "new1", output: []))
    state.append_result(RobotLab::RobotResult.new(robot_name: "new2", output: []))

    @manager.save_state(thread_id: "t1", state: state, since_index: 1)

    assert_equal 2, @results["t1"].length
    assert_equal "new1", @results["t1"][0].robot_name
    assert_equal "new2", @results["t1"][1].robot_name
  end
end
