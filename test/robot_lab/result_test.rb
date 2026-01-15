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

  def test_result_export
    output = [RobotLab::TextMessage.new(role: :assistant, content: "Test")]
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: output,
      stop_reason: "stop"
    )

    exported = result.export

    assert_equal "robot", exported[:robot_name]
    assert_equal "stop", exported[:stop_reason]
    assert exported[:checksum].is_a?(String)
    assert exported[:created_at].is_a?(String)
    assert exported[:id].is_a?(String)
  end

  def test_result_to_json
    output = [RobotLab::TextMessage.new(role: :assistant, content: "Test")]
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: output
    )

    json = result.to_json

    assert json.is_a?(String)
    parsed = JSON.parse(json)
    assert_equal "robot", parsed["robot_name"]
  end

  def test_last_text_content
    output = [
      RobotLab::TextMessage.new(role: :assistant, content: "First"),
      RobotLab::TextMessage.new(role: :assistant, content: "Last")
    ]
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: output
    )

    assert_equal "Last", result.last_text_content
  end

  def test_last_text_content_nil_when_no_text_messages
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: []
    )

    assert_nil result.last_text_content
  end

  def test_has_tool_calls_true_with_tool_call_message
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: {})
    tool_call = RobotLab::ToolCallMessage.new(role: :assistant, tools: [tool])

    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: [tool_call]
    )

    assert result.has_tool_calls?
  end

  def test_has_tool_calls_true_with_tool_results
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: {})
    tool_result = RobotLab::ToolResultMessage.new(tool: tool, content: "result")

    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: [],
      tool_calls: [tool_result]
    )

    assert result.has_tool_calls?
  end

  def test_has_tool_calls_false_without_tools
    output = [RobotLab::TextMessage.new(role: :assistant, content: "Test")]
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: output
    )

    refute result.has_tool_calls?
  end

  def test_stopped_true_when_output_stopped
    output = [RobotLab::TextMessage.new(role: :assistant, content: "Done", stop_reason: "stop")]
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: output
    )

    assert result.stopped?
  end

  def test_stopped_false_when_has_tool_calls
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: {})
    tool_call = RobotLab::ToolCallMessage.new(role: :assistant, tools: [tool])

    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: [tool_call]
    )

    refute result.stopped?
  end

  def test_result_auto_generates_uuid
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: []
    )

    assert_match(/\A[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\z/, result.id)
  end

  def test_result_auto_sets_created_at
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: []
    )

    assert result.created_at.is_a?(Time)
  end

  def test_normalize_messages_from_hash
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: [{ type: "text", role: :assistant, content: "From hash" }]
    )

    assert result.output.first.is_a?(RobotLab::TextMessage)
    assert_equal "From hash", result.output.first.content
  end

  def test_to_h_includes_debug_fields
    output = [RobotLab::TextMessage.new(role: :assistant, content: "Test")]
    prompt = [RobotLab::TextMessage.new(role: :user, content: "Prompt")]
    result = RobotLab::RobotResult.new(
      robot_name: "robot",
      output: output,
      prompt: prompt
    )

    hash = result.to_h

    assert hash[:prompt].is_a?(Array)
  end

  def test_from_hash_with_string_keys
    hash = {
      "robot_name" => "robot",
      "output" => [{ "type" => "text", "role" => "assistant", "content" => "Test" }],
      "tool_calls" => []
    }

    result = RobotLab::RobotResult.from_hash(hash)

    assert_equal "robot", result.robot_name
  end

  def test_from_hash_with_created_at
    hash = {
      robot_name: "robot",
      output: [],
      created_at: "2024-01-15T10:30:00Z"
    }

    result = RobotLab::RobotResult.from_hash(hash)

    assert result.created_at.is_a?(Time)
  end
end
