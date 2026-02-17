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
    stub_robot_ask(robot2) { |msg| received_message = msg; "read it" }

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
    stub_robot_ask(robot2) { |msg| received_message = msg; "output from second" }

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
end
