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
end
