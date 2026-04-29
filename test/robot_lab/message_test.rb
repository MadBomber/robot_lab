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

  # Message predicate methods
  def test_text_predicate
    message = RobotLab::TextMessage.new(role: :user, content: "Hello")
    assert message.text?
    refute message.tool_call?
    refute message.tool_result?
  end

  def test_tool_call_predicate
    message = RobotLab::ToolCallMessage.new(
      role: :assistant,
      tools: [{ id: "t1", name: "test", input: {} }]
    )
    refute message.text?
    assert message.tool_call?
    refute message.tool_result?
  end

  def test_tool_result_predicate
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: {})
    message = RobotLab::ToolResultMessage.new(tool: tool, content: "result")
    refute message.text?
    refute message.tool_call?
    assert message.tool_result?
  end

  def test_role_predicates
    system_msg = RobotLab::TextMessage.new(role: :system, content: "System")
    user_msg = RobotLab::TextMessage.new(role: :user, content: "User")
    assistant_msg = RobotLab::TextMessage.new(role: :assistant, content: "Assistant")

    assert system_msg.system?
    refute system_msg.user?
    refute system_msg.assistant?

    refute user_msg.system?
    assert user_msg.user?
    refute user_msg.assistant?

    refute assistant_msg.system?
    refute assistant_msg.user?
    assert assistant_msg.assistant?
  end

  def test_stop_reason_predicates
    stopped_msg = RobotLab::TextMessage.new(role: :assistant, content: "Done", stop_reason: "stop")
    tool_msg = RobotLab::TextMessage.new(role: :assistant, content: "Calling tool", stop_reason: "tool")

    assert stopped_msg.stopped?
    refute stopped_msg.tool_stop?

    refute tool_msg.stopped?
    assert tool_msg.tool_stop?
  end

  def test_message_to_json
    message = RobotLab::TextMessage.new(role: :user, content: "Hello")
    json = message.to_json

    assert json.is_a?(String)
    parsed = JSON.parse(json)
    assert_equal "text", parsed["type"]
    assert_equal "user", parsed["role"]
    assert_equal "Hello", parsed["content"]
  end

  def test_tool_message_initialization
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: { key: "value" })

    assert_equal "t1", tool.id
    assert_equal "test", tool.name
    assert_equal({ key: "value" }, tool.input)
  end

  def test_tool_message_with_nil_input
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: nil)

    assert_equal({}, tool.input)
  end

  def test_tool_message_to_h
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: { key: "value" })
    hash = tool.to_h

    assert_equal "tool", hash[:type]
    assert_equal "t1", hash[:id]
    assert_equal "test", hash[:name]
    assert_equal({ key: "value" }, hash[:input])
  end

  def test_tool_message_to_json
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: {})
    json = tool.to_json

    assert json.is_a?(String)
    parsed = JSON.parse(json)
    assert_equal "t1", parsed["id"]
  end

  def test_tool_message_from_hash
    hash = { id: "t1", name: "test", input: { key: "value" } }
    tool = RobotLab::ToolMessage.from_hash(hash)

    assert_equal "t1", tool.id
    assert_equal "test", tool.name
    assert_equal({ key: "value" }, tool.input)
  end

  def test_tool_message_from_hash_with_arguments
    # Some APIs use 'arguments' instead of 'input'
    hash = { id: "t1", name: "test", arguments: { query: "search" } }
    tool = RobotLab::ToolMessage.from_hash(hash)

    assert_equal({ query: "search" }, tool.input)
  end

  def test_tool_call_message_to_h
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: {})
    message = RobotLab::ToolCallMessage.new(role: :assistant, tools: [tool])
    hash = message.to_h

    assert_equal "tool_call", hash[:type]
    assert_equal "assistant", hash[:role]
    assert hash[:tools].is_a?(Array)
    assert_equal 1, hash[:tools].size
  end

  def test_tool_result_success_predicate
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: {})
    message = RobotLab::ToolResultMessage.new(tool: tool, content: { data: "result" })

    assert message.success?
    refute message.error?
    assert_equal "result", message.data
    assert_nil message.error
  end

  def test_tool_result_data_accessor
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: {})
    message = RobotLab::ToolResultMessage.new(
      tool: tool,
      content: { data: { nested: "value" } }
    )

    assert_equal({ nested: "value" }, message.data)
  end

  def test_tool_result_to_h
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: {})
    message = RobotLab::ToolResultMessage.new(tool: tool, content: { data: "result" })
    hash = message.to_h

    assert_equal "tool_result", hash[:type]
    assert_equal "tool_result", hash[:role]
    assert hash[:tool].is_a?(Hash)
    assert_equal({ data: "result" }, hash[:content])
  end

  def test_tool_result_with_tool_hash
    message = RobotLab::ToolResultMessage.new(
      tool: { id: "t1", name: "test", input: {} },
      content: { data: "result" }
    )

    assert_instance_of RobotLab::ToolMessage, message.tool
    assert_equal "t1", message.tool.id
  end

  def test_invalid_message_type_raises
    assert_raises(ArgumentError) do
      RobotLab::Message.new(type: "invalid_xyz", role: :assistant, content: "test")
    end
  end

  def test_invalid_role_raises
    assert_raises(ArgumentError) do
      RobotLab::Message.new(type: "text", role: :unknown_role, content: "test")
    end
  end

  def test_invalid_stop_reason_raises
    assert_raises(ArgumentError) do
      RobotLab::TextMessage.new(role: :assistant, content: "test", stop_reason: "invalid_reason")
    end
  end

  def test_message_from_hash_with_unknown_type_falls_through
    assert_raises(ArgumentError) do
      RobotLab::Message.from_hash({ type: "unknown_xyz", role: :assistant, content: "test" })
    end
  end

  def test_message_from_hash_with_missing_type_defaults_to_text
    # Records persisted before the type field was introduced have no :type key.
    # from_hash defaults nil type to "text" so old rows can still be deserialized.
    message = RobotLab::Message.from_hash({ role: "user", content: "Hello" })
    assert_instance_of RobotLab::TextMessage, message
    assert_equal "user",  message.role
    assert_equal "Hello", message.content
  end

  def test_message_from_hash_with_nil_type_defaults_to_text
    message = RobotLab::Message.from_hash({ type: nil, role: "assistant", content: "Hi" })
    assert_instance_of RobotLab::TextMessage, message
    assert_equal "assistant", message.role
  end

  def test_tool_call_message_requires_tool_message_or_hash
    assert_raises(ArgumentError) do
      RobotLab::ToolCallMessage.new(role: :assistant, tools: ["not_a_tool"])
    end
  end

  def test_tool_result_message_requires_tool_message_or_hash
    assert_raises(ArgumentError) do
      RobotLab::ToolResultMessage.new(tool: "not_a_tool", content: "result")
    end
  end

  def test_tool_result_message_to_json
    tool = RobotLab::ToolMessage.new(id: "t1", name: "test", input: {})
    message = RobotLab::ToolResultMessage.new(tool: tool, content: { data: "ok" })
    json = message.to_json

    assert json.is_a?(String)
    parsed = JSON.parse(json)
    assert_equal "tool_result", parsed["type"]
    assert_equal "tool_result", parsed["role"]
  end

  def test_text_message_compact_hash_excludes_nil_stop_reason
    message = RobotLab::TextMessage.new(role: :user, content: "Hello")
    hash = message.to_h
    refute hash.key?(:stop_reason)
  end

  def test_message_from_hash_with_string_keys
    hash = { "type" => "text", "role" => "user", "content" => "Hello" }
    message = RobotLab::Message.from_hash(hash)
    assert_instance_of RobotLab::TextMessage, message
    assert_equal "Hello", message.content
  end
end
