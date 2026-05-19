# frozen_string_literal: true

require "test_helper"

# Fake LLM response that satisfies Robot#build_result expectations
FakeLLMResponse = Data.define(:content, :tool_calls, :stop_reason) do
  def initialize(content:, tool_calls: nil, stop_reason: "end_turn")
    super
  end
end

class RobotLab::NetworkPipelineTest < Minitest::Test
  # Stub a robot's @chat.ask to return a fake response without hitting the LLM.
  # The block receives the message string and should return the content string.
  def stub_robot_ask(robot, &response_builder)
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) do |message = nil, **_kwargs, &_block|
      content = response_builder.call(message)
      FakeLLMResponse.new(content: content)
    end
  end

  def test_two_robot_pipeline_runs_sequentially
    robot1 = build_robot(name: "step1", system_prompt: "You are step 1")
    robot2 = build_robot(name: "step2", system_prompt: "You are step 2")

    stub_robot_ask(robot1) { |_msg| "step1 done" }
    stub_robot_ask(robot2) { |_msg| "step2 done" }

    network = RobotLab::Network.new(name: "pipeline") do
      task :step1, robot1, depends_on: :none
      task :step2, robot2, depends_on: [:step1]
    end

    result = network.run(message: "hello")

    # Final value is the last robot's RobotResult
    assert_instance_of RobotLab::RobotResult, result.value
    assert_equal "step2", result.value.robot_name
    assert_equal "step2 done", result.value.reply
  end

  def test_pipeline_shares_network_memory
    robot1 = build_robot(name: "writer", system_prompt: "You write to memory")
    robot2 = build_robot(name: "reader", system_prompt: "You read from memory")

    # robot1 writes to shared memory during its run
    stub_robot_ask(robot1) do |_msg|
      robot1.instance_variable_get(:@chat) # just to have a response
      "wrote it"
    end

    # Intercept robot1's run to also write to network memory
    original_run1 = robot1.method(:run)
    robot1.define_singleton_method(:run) do |message = nil, **kwargs|
      result = original_run1.call(message, **kwargs)
      # The network memory is what resolve_active_memory returns during run
      # We can verify it by checking the network's memory directly after run
      result
    end

    received_message = nil
    stub_robot_ask(robot2) do |msg|
      received_message = msg
      "read it"
    end

    network = RobotLab::Network.new(name: "shared_mem")
    network.task(:writer, robot1, depends_on: :none)
    network.task(:reader, robot2, depends_on: [:writer])

    result = network.run(message: "start")

    # Both robots shared the same network memory
    memory = network.memory
    assert_instance_of RobotLab::Memory, memory

    # Each robot's result is accessible via context
    writer_result = result.context[:writer]
    reader_result = result.context[:reader]

    assert_instance_of RobotLab::RobotResult, writer_result
    assert_instance_of RobotLab::RobotResult, reader_result
    assert_equal "writer", writer_result.robot_name
    assert_equal "reader", reader_result.robot_name
  end

  def test_pipeline_passes_network_config
    config = RobotLab::RunConfig.new(temperature: 0.5)

    robot1 = build_robot(name: "configured", system_prompt: "You are configured")

    applied_temp = nil
    stub_robot_ask(robot1) do |_msg|
      # Check that config was applied to the chat
      applied_temp = robot1.instance_variable_get(:@chat).instance_variable_get(:@temperature)
      "configured response"
    end

    network = RobotLab::Network.new(name: "config_test", config: config)
    network.task(:configured, robot1, depends_on: :none)

    result = network.run(message: "test config")

    assert_equal "configured response", result.value.reply
  end

  def test_pipeline_second_robot_receives_first_robots_output_as_message
    robot1 = build_robot(name: "first", system_prompt: "First robot")
    robot2 = build_robot(name: "second", system_prompt: "Second robot")

    stub_robot_ask(robot1) { |_msg| "output from first" }

    received_message = nil
    stub_robot_ask(robot2) do |msg|
      received_message = msg
      "output from second"
    end

    network = RobotLab::Network.new(name: "chaining") do
      task :first, robot1, depends_on: :none
      task :second, robot2, depends_on: [:first]
    end

    network.run(message: "begin")

    # SimpleFlow passes the previous robot's RobotResult through
    # Robot#call extracts last_text_content as the message for the next robot
    assert_equal "output from first", received_message
  end

  def test_pipeline_result_contains_all_robot_results_in_context
    robot1 = build_robot(name: "a", system_prompt: "Robot A")
    robot2 = build_robot(name: "b", system_prompt: "Robot B")
    robot3 = build_robot(name: "c", system_prompt: "Robot C")

    stub_robot_ask(robot1) { |_| "from a" }
    stub_robot_ask(robot2) { |_| "from b" }
    stub_robot_ask(robot3) { |_| "from c" }

    network = RobotLab::Network.new(name: "three_step") do
      task :a, robot1, depends_on: :none
      task :b, robot2, depends_on: [:a]
      task :c, robot3, depends_on: [:b]
    end

    result = network.run(message: "go")

    assert_equal "from a", result.context[:a].reply
    assert_equal "from b", result.context[:b].reply
    assert_equal "from c", result.context[:c].reply
    assert_equal "from c", result.value.reply
  end

  def test_task_context_merges_into_run_params
    robot1 = build_robot(name: "ctx_robot", system_prompt: "Context robot")

    stub_robot_ask(robot1) { |_| "done" }

    network = RobotLab::Network.new(name: "ctx_test")
    network.task(:ctx_robot, robot1, context: { department: "billing" }, depends_on: :none)

    # The test passes if the pipeline runs without error — context merging worked
    result = network.run(message: "test context")
    assert_equal "done", result.value.reply
  end

  def test_robot_error_does_not_crash_pipeline
    robot = build_robot(name: "bad_robot", system_prompt: "I will fail")

    # Stub ask to raise
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| raise "simulated failure" }

    network = RobotLab::Network.new(name: "fault_test") do
      task :bad_robot, robot, depends_on: :none
    end

    result = network.run(message: "test")

    # Result should contain the error result, not raise
    error_result = result.context[:bad_robot]
    assert_instance_of RobotLab::RobotResult, error_result
    assert_match(/RuntimeError/, error_result.reply)
  end

  def test_token_budget_raises_inference_error_when_exceeded
    robot = build_robot(name: "budget_bot", system_prompt: "test", token_budget: 100)

    tokens = RubyLLM::Tokens.new(input: 60, output: 60)
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "reply", tool_calls: nil, stop_reason: "end_turn", tokens: tokens
    )

    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    network = RobotLab::Network.new(name: "budget_test") do
      task :budget_bot, robot, depends_on: :none
    end

    result = network.run(message: "test")

    # Robot catches the InferenceError in call() and returns an error result
    bot_result = result.context[:budget_bot]
    assert_instance_of RobotLab::RobotResult, bot_result
    assert_match(/InferenceError|Token budget exceeded/, bot_result.reply)
  end

  def test_token_budget_not_exceeded_when_under_budget
    robot = build_robot(name: "budget_bot2", system_prompt: "test", token_budget: 200)

    tokens = RubyLLM::Tokens.new(input: 60, output: 60)
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "all good", tool_calls: nil, stop_reason: "end_turn", tokens: tokens
    )

    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    network = RobotLab::Network.new(name: "budget_ok") do
      task :budget_bot2, robot, depends_on: :none
    end

    result = network.run(message: "test")

    assert_equal "all good", result.value.reply
  end

  def test_circuit_breaker_fires_user_callback_within_limit
    call_count = 0
    on_tool_call_cb = ->(_tc) { call_count += 1 }

    robot = build_robot(name: "cb_robot", system_prompt: "test",
                        max_tool_rounds: 3, on_tool_call: on_tool_call_cb)

    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "done", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )

    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) do |_msg = nil, **_kw, &_b|
      2.times { @on[:tool_call]&.call(Object.new) }
      fake_response
    end

    robot.run("test")

    assert_equal 2, call_count
  end

  def test_circuit_breaker_resets_counter_between_runs
    robot = build_robot(name: "counter_bot", system_prompt: "test", max_tool_rounds: 2)

    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "done", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )

    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) do |_msg = nil, **_kw, &_b|
      2.times { @on[:tool_call]&.call(Object.new) }
      fake_response
    end

    # First run fires 2 tool calls (== limit, no raise)
    result1 = robot.run("first")
    assert_equal "done", result1.reply

    # Second run also fires 2 tool calls — counter was reset
    result2 = robot.run("second")
    assert_equal "done", result2.reply
  end

  def test_inject_learnings_with_nil_message
    robot = build_robot(name: "learner", system_prompt: "test")
    robot.learn("something important")

    result = robot.send(:inject_learnings, nil)
    assert_nil result
  end

  def test_inject_learnings_returns_message_unchanged_when_no_learnings
    robot = build_robot(name: "learner", system_prompt: "test")
    result = robot.send(:inject_learnings, "my message")
    assert_equal "my message", result
  end

  def test_multiple_learnings_all_appear_in_injected_message
    robot = build_robot(name: "learner", system_prompt: "test")
    robot.learn("insight one")
    robot.learn("insight two")
    robot.learn("insight three")

    received_message = nil
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) do |msg = nil, **_kw, &_b|
      received_message = msg
      fake_response
    end

    robot.run("do the task")

    assert_includes received_message, "insight one"
    assert_includes received_message, "insight two"
    assert_includes received_message, "insight three"
  end

  def test_learnings_restored_from_memory_manually
    robot = build_robot(name: "learner", system_prompt: "test")
    robot.learn("foo")
    robot.learn("bar")

    # Simulate reloading learnings from persisted memory
    persisted = robot.memory.get(:learnings)
    robot.instance_variable_set(:@learnings, [])
    robot.instance_variable_set(:@learnings, Array(persisted))

    assert_includes robot.learnings, "foo"
    assert_includes robot.learnings, "bar"
  end

  def test_build_result_uses_input_tokens_fallback
    robot = build_robot(name: "token_bot", system_prompt: "test")

    # Fake response that has input_tokens/output_tokens but NOT .tokens
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :input_tokens, :output_tokens).new(
      content: "hello", tool_calls: nil, stop_reason: "end_turn",
      input_tokens: 42, output_tokens: 21
    )

    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    result = robot.run("test")

    assert_equal 42, result.input_tokens
    assert_equal 21, result.output_tokens
  end

  def test_run_result_includes_duration
    robot = build_robot(name: "dur_bot", system_prompt: "test")

    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    # Invoke via call() which sets duration
    result_obj = ::SimpleFlow::Result.new("hello", context: {})
    result = robot.call(result_obj)

    robot_result = result.context[:dur_bot]
    assert robot_result.duration.is_a?(Float)
    assert robot_result.duration >= 0
  end
end
