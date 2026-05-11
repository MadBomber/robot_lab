# frozen_string_literal: true

require "test_helper"

class NetworkRoutingIntegrationTest < Minitest::Test
  FakeResponse = Data.define(:content, :tool_calls, :stop_reason, :tokens)

  def stub_llm(robot, reply:)
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) do |_msg = nil, **_kw, &_b|
      FakeResponse.new(content: reply, tool_calls: nil, stop_reason: "end_turn", tokens: nil)
    end
  end

  def test_sequential_pipeline_executes_both_robots
    robot1 = build_robot(name: "step1")
    robot2 = build_robot(name: "step2")
    stub_llm(robot1, reply: "result from step1")
    stub_llm(robot2, reply: "result from step2")

    network = RobotLab::Network.new(name: "seq") do
      task :step1, robot1, depends_on: :none
      task :step2, robot2, depends_on: [:step1]
    end

    result = network.run(message: "start")
    context = result.context

    assert context.key?(:step1), "step1 must be in result context"
    assert context.key?(:step2), "step2 must be in result context"
    assert_equal "result from step1", context[:step1].last_text_content
    assert_equal "result from step2", context[:step2].last_text_content
  end

  def test_optional_step_skipped_when_not_needed
    mandatory = build_robot(name: "mandatory")
    optional  = build_robot(name: "opt")
    stub_llm(mandatory, reply: "mandatory done")

    optional_called = false
    opt_chat = optional.instance_variable_get(:@chat)
    opt_chat.define_singleton_method(:ask) do |*|
      optional_called = true
      FakeResponse.new(content: "opt result", tool_calls: nil, stop_reason: "end_turn", tokens: nil)
    end

    network = RobotLab::Network.new(name: "optional_test") do
      task :mandatory, mandatory, depends_on: :none
      task :opt,       optional,  depends_on: :optional
    end

    result = network.run(message: "go")
    assert result.context.key?(:mandatory), "mandatory step must execute"
    refute optional_called, "optional step must not execute when not selected"
  end

  def test_network_memory_is_shared_across_robots
    writer  = build_robot(name: "writer")
    checker = build_robot(name: "checker")

    shared_memory = nil
    writer_chat = writer.instance_variable_get(:@chat)
    writer_chat.define_singleton_method(:ask) do |*|
      FakeResponse.new(content: "written", tool_calls: nil, stop_reason: "end_turn", tokens: nil)
    end

    network = RobotLab::Network.new(name: "shared_mem_test") do
      task :writer,  writer,  depends_on: :none
      task :checker, checker, depends_on: [:writer]
    end

    captured_memory = nil
    checker.define_singleton_method(:run) do |message = nil, **kwargs, &block|
      captured_memory = kwargs[:network_memory]
      FakeResponse.new(content: "checked", tool_calls: nil, stop_reason: "end_turn", tokens: nil)
      super(message, **kwargs, &block)
    end

    checker_chat = checker.instance_variable_get(:@chat)
    checker_chat.define_singleton_method(:ask) do |*|
      FakeResponse.new(content: "checked", tool_calls: nil, stop_reason: "end_turn", tokens: nil)
    end

    network.run(message: "go")
    assert_instance_of RobotLab::Memory, captured_memory
  end
end
