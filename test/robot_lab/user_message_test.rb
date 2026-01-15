# frozen_string_literal: true

require "test_helper"

class RobotLab::UserMessageTest < Minitest::Test
  def test_user_message_with_string
    message = RobotLab::UserMessage.new("Hello, world!")

    assert_equal "Hello, world!", message.content
    assert_empty message.metadata
  end

  def test_user_message_with_metadata
    message = RobotLab::UserMessage.new(
      "Help me with billing",
      metadata: { user_id: "user_123", priority: "high" }
    )

    assert_equal "Help me with billing", message.content
    assert_equal "user_123", message.metadata[:user_id]
    assert_equal "high", message.metadata[:priority]
  end

  def test_user_message_to_message
    user_message = RobotLab::UserMessage.new("Test content")
    text_message = user_message.to_message

    assert_instance_of RobotLab::TextMessage, text_message
    assert_equal "user", text_message.role
    assert_equal "Test content", text_message.content
  end

  def test_user_message_to_h
    message = RobotLab::UserMessage.new("Content", metadata: { key: "value" })
    hash = message.to_h

    assert_equal "Content", hash[:content]
    assert_equal({ key: "value" }, hash[:metadata])
  end

  def test_user_message_from_hash
    hash = { content: "Loaded content", metadata: { source: "api" } }
    message = RobotLab::UserMessage.from(hash)

    assert_equal "Loaded content", message.content
    assert_equal "api", message.metadata[:source]
  end

  def test_user_message_from_string
    message = RobotLab::UserMessage.from("Simple string")

    assert_instance_of RobotLab::UserMessage, message
    assert_equal "Simple string", message.content
  end

  def test_user_message_from_user_message
    original = RobotLab::UserMessage.new("Original", metadata: { key: "value" })
    result = RobotLab::UserMessage.from(original)

    assert_same original, result
  end

  def test_user_message_from_text_message
    text = RobotLab::TextMessage.new(role: :user, content: "From text")
    result = RobotLab::UserMessage.from(text)

    assert_instance_of RobotLab::UserMessage, result
    assert_equal "From text", result.content
  end

  def test_user_message_to_s
    message = RobotLab::UserMessage.new("Test content")

    assert_equal "Test content", message.to_s
  end

  def test_user_message_to_json
    message = RobotLab::UserMessage.new("Test", metadata: { key: "value" })
    json = message.to_json

    assert json.is_a?(String)
    parsed = JSON.parse(json)
    assert_equal "Test", parsed["content"]
  end

  def test_user_message_auto_generates_id
    message = RobotLab::UserMessage.new("Test")

    assert_match(/\A[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\z/, message.id)
  end

  def test_user_message_auto_sets_created_at
    message = RobotLab::UserMessage.new("Test")

    assert message.created_at.is_a?(Time)
  end

  def test_user_message_with_session_id
    message = RobotLab::UserMessage.new("Test", session_id: "thread_123")

    assert_equal "thread_123", message.session_id
  end

  def test_user_message_with_system_prompt
    message = RobotLab::UserMessage.new("Test", system_prompt: "Be helpful")

    assert_equal "Be helpful", message.system_prompt
  end

  def test_user_message_with_custom_id
    message = RobotLab::UserMessage.new("Test", id: "custom-id")

    assert_equal "custom-id", message.id
  end

  def test_user_message_from_hash_with_string_keys
    hash = { "content" => "Test", "metadata" => { "key" => "value" } }
    message = RobotLab::UserMessage.from(hash)

    assert_equal "Test", message.content
  end

  def test_user_message_from_other_object
    # Objects that respond to to_s
    result = RobotLab::UserMessage.from(123)

    assert_equal "123", result.content
  end

  def test_user_message_to_h_excludes_nil_values
    message = RobotLab::UserMessage.new("Test")
    hash = message.to_h

    refute hash.key?(:session_id)
    refute hash.key?(:system_prompt)
  end

  def test_user_message_content_converted_to_string
    message = RobotLab::UserMessage.new(123)

    assert_equal "123", message.content
  end

  def test_user_message_from_hash_with_all_fields
    hash = {
      content: "Test",
      session_id: "thread_1",
      system_prompt: "Be helpful",
      metadata: { key: "value" },
      id: "msg_123"
    }
    message = RobotLab::UserMessage.from(hash)

    assert_equal "Test", message.content
    assert_equal "thread_1", message.session_id
    assert_equal "Be helpful", message.system_prompt
    assert_equal({ key: "value" }, message.metadata)
    assert_equal "msg_123", message.id
  end
end
