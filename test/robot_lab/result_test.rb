# frozen_string_literal: true

require "test_helper"

class RobotLab::RobotResultTest < Minitest::Test
  def test_result_initialization
    output = [RobotLab::TextMessage.new(role: :assistant, content: "Hello")]
    result = RobotLab::RobotResult.new(
      robot_name: "test_robot",
      output: output
    )

    assert_equal "test_robot", result.robot_name
    assert_equal output, result.output
    assert_empty result.tool_calls
    assert_nil result.stop_reason
  end

  def test_result_with_tool_calls
    tools = [{ id: "t1", name: "calc", input: {} }]
    tool_message = RobotLab::ToolMessage.new(id: "t1", name: "calc", input: {})
    tool_call = RobotLab::ToolCallMessage.new(role: :assistant, tools: tools)
    tool_result = RobotLab::ToolResultMessage.new(
      tool: tool_message,
      content: { data: "42" }
    )

    result = RobotLab::RobotResult.new(
      robot_name: "tool_robot",
      output: [tool_call],
      tool_calls: [tool_result]
    )

    assert_equal 1, result.tool_calls.length
    assert_equal({ data: "42" }, result.tool_calls.first.content)
  end

  def test_result_with_stop_reason
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: [],
      stop_reason: "max_tokens"
    )

    assert_equal "max_tokens", result.stop_reason
  end

  def test_result_checksum_generation
    output = [RobotLab::TextMessage.new(role: :assistant, content: "Test")]
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: output
    )

    checksum = result.checksum

    refute_nil checksum
    assert_kind_of String, checksum
    assert checksum.length > 0
  end

  def test_result_checksum_consistency
    output = [RobotLab::TextMessage.new(role: :assistant, content: "Same content")]
    result1 = RobotLab::RobotResult.new(robot_name: "robot", output: output)
    result2 = RobotLab::RobotResult.new(robot_name: "robot", output: output)

    assert_equal result1.checksum, result2.checksum
  end

  def test_result_checksum_varies_with_content
    output1 = [RobotLab::TextMessage.new(role: :assistant, content: "Content A")]
    output2 = [RobotLab::TextMessage.new(role: :assistant, content: "Content B")]

    result1 = RobotLab::RobotResult.new(robot_name: "robot", output: output1)
    result2 = RobotLab::RobotResult.new(robot_name: "robot", output: output2)

    refute_equal result1.checksum, result2.checksum
  end

  def test_result_to_h
    output = [RobotLab::TextMessage.new(role: :assistant, content: "Test")]
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: output,
      stop_reason: "stop"
    )

    hash = result.to_h

    assert_equal "robot", hash[:robot_name]
    assert_equal "stop", hash[:stop_reason]
    assert hash[:output].is_a?(Array)
  end

  def test_result_from_hash
    hash = {
      robot_name: "loaded_robot",
      output: [{ type: "text", role: :assistant, content: "Loaded" }],
      tool_calls: [],
      stop_reason: "stop"
    }

    result = RobotLab::RobotResult.from_hash(hash)

    assert_equal "loaded_robot", result.robot_name
    assert_equal 1, result.output.length
    assert_equal "Loaded", result.output.first.content
  end
end
