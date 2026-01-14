# frozen_string_literal: true

require "test_helper"

class RobotLab::MessageTest < Minitest::Test
  def test_text_message_initialization
    message = RobotLab::TextMessage.new(role: :user, content: "Hello")

    assert_equal "text", message.type
    assert_equal "user", message.role
    assert_equal "Hello", message.content
  end

  def test_text_message_with_system_role
    message = RobotLab::TextMessage.new(role: :system, content: "You are helpful")

    assert_equal "system", message.role
    assert_equal "You are helpful", message.content
  end

  def test_text_message_to_hash
    message = RobotLab::TextMessage.new(role: :assistant, content: "Hi there")
    hash = message.to_h

    assert_equal "text", hash[:type]
    assert_equal "assistant", hash[:role]
    assert_equal "Hi there", hash[:content]
  end

  def test_tool_call_message_initialization
    tools = [{ id: "tool_1", name: "calculator", input: { a: 1, b: 2 } }]
    message = RobotLab::ToolCallMessage.new(role: :assistant, tools: tools)

    assert_equal "tool_call", message.type
    assert_equal "assistant", message.role
    assert_equal 1, message.tools.length
  end

  def test_tool_call_message_with_stop_reason
    message = RobotLab::ToolCallMessage.new(
      role: :assistant,
      tools: [{ id: "t1", name: "test", input: {} }],
      stop_reason: "tool"
    )

    assert_equal "tool", message.stop_reason
  end

  def test_tool_result_message_initialization
    tool = RobotLab::ToolMessage.new(id: "tool_1", name: "calculator", input: {})
    message = RobotLab::ToolResultMessage.new(
      tool: tool,
      content: { data: "3" }
    )

    assert_equal "tool_result", message.type
    assert_equal "tool_1", message.tool.id
    assert_equal "calculator", message.tool.name
  end

  def test_tool_result_message_with_error
    tool = RobotLab::ToolMessage.new(id: "tool_1", name: "calculator", input: {})
    message = RobotLab::ToolResultMessage.new(
      tool: tool,
      content: { error: "Division by zero" }
    )

    assert message.error?
    assert_equal "Division by zero", message.error
  end

  def test_message_from_hash_text
    hash = { type: "text", role: :user, content: "Hello" }
    message = RobotLab::Message.from_hash(hash)

    assert_instance_of RobotLab::TextMessage, message
    assert_equal "Hello", message.content
  end

  def test_message_from_hash_tool_call
    hash = { type: "tool_call", role: :assistant, tools: [{ id: "t1", name: "test", input: {} }] }
    message = RobotLab::Message.from_hash(hash)

    assert_instance_of RobotLab::ToolCallMessage, message
  end

  def test_message_from_hash_tool_result
    hash = {
      type: "tool_result",
      tool: { id: "t1", name: "test", input: {} },
      content: { data: "result" }
    }
    message = RobotLab::Message.from_hash(hash)

    assert_instance_of RobotLab::ToolResultMessage, message
    assert_equal "result", message.content[:data]
  end
end
