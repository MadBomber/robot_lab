# frozen_string_literal: true

require "test_helper"

class NetworkPipelineIntegrationTest < Minitest::Test
  FakeResponse = Data.define(:content, :tool_calls, :stop_reason, :tokens)

  def stub_llm(robot, reply:)
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) do |_msg = nil, **_kw, &_b|
      FakeResponse.new(content: reply, tool_calls: nil, stop_reason: "end_turn", tokens: nil)
    end
  end

  def test_result_of_robot1_is_visible_in_final_context
    classifier = build_robot(name: "classifier")
    responder  = build_robot(name: "responder")
    stub_llm(classifier, reply: "billing")
    stub_llm(responder,  reply: "Here is the billing help.")

    network = RobotLab::Network.new(name: "pipeline_test") do
      task :classifier, classifier, depends_on: :none
      task :responder,  responder,  depends_on: [:classifier]
    end

    result = network.run(message: "I have a billing question")
    assert_equal "billing",               result.context[:classifier].last_text_content
    assert_equal "Here is the billing help.", result.context[:responder].last_text_content
  end

  def test_network_returns_last_robot_result_as_value
    first  = build_robot(name: "first")
    second = build_robot(name: "second")
    stub_llm(first,  reply: "first output")
    stub_llm(second, reply: "final answer")

    network = RobotLab::Network.new(name: "value_test") do
      task :first,  first,  depends_on: :none
      task :second, second, depends_on: [:first]
    end

    result = network.run(message: "begin")
    last_result = result.value
    assert_kind_of RobotLab::RobotResult, last_result
    assert_equal "final answer", last_result.last_text_content
  end

  def test_three_robot_pipeline_executes_all
    r1 = build_robot(name: "r1")
    r2 = build_robot(name: "r2")
    r3 = build_robot(name: "r3")
    stub_llm(r1, reply: "one")
    stub_llm(r2, reply: "two")
    stub_llm(r3, reply: "three")

    network = RobotLab::Network.new(name: "three_step") do
      task :r1, r1, depends_on: :none
      task :r2, r2, depends_on: [:r1]
      task :r3, r3, depends_on: [:r2]
    end

    result = network.run(message: "go")
    assert_equal "one",   result.context[:r1].last_text_content
    assert_equal "two",   result.context[:r2].last_text_content
    assert_equal "three", result.context[:r3].last_text_content
  end
end
