# frozen_string_literal: true

require 'test_helper'

class RobotLab::RobotMessageTest < Minitest::Test
  def test_build_creates_message
    msg = RobotLab::RobotMessage.build(id: 1, from: "alice", content: "Hello")

    assert_equal 1, msg.id
    assert_equal "alice", msg.from
    assert_equal "Hello", msg.content
    assert_nil msg.in_reply_to
  end

  def test_build_with_in_reply_to
    msg = RobotLab::RobotMessage.build(
      id: 2, from: "bob",
      content: "Got it",
      in_reply_to: "alice:1"
    )

    assert_equal "alice:1", msg.in_reply_to
  end

  def test_key_returns_composite
    msg = RobotLab::RobotMessage.build(id: 3, from: "alice", content: "test")

    assert_equal "alice:3", msg.key
  end

  def test_reply_predicate_false_for_original
    msg = RobotLab::RobotMessage.build(id: 1, from: "alice", content: "hi")

    refute msg.reply?
  end

  def test_reply_predicate_true_for_reply
    msg = RobotLab::RobotMessage.build(
      id: 2, from: "bob",
      content: "hi back",
      in_reply_to: "alice:1"
    )

    assert msg.reply?
  end

  def test_immutable
    msg = RobotLab::RobotMessage.build(id: 1, from: "alice", content: "hi")

    assert msg.frozen?
  end

  def test_equality
    msg1 = RobotLab::RobotMessage.build(id: 1, from: "alice", content: "hi")
    msg2 = RobotLab::RobotMessage.build(id: 1, from: "alice", content: "hi")

    assert_equal msg1, msg2
  end

  def test_inequality
    msg1 = RobotLab::RobotMessage.build(id: 1, from: "alice", content: "hi")
    msg2 = RobotLab::RobotMessage.build(id: 2, from: "alice", content: "hi")

    refute_equal msg1, msg2
  end

  def test_hash_content_supported
    msg = RobotLab::RobotMessage.build(
      id: 1, from: "alice",
      content: { task: "summarize", data: [1, 2, 3] }
    )

    assert_kind_of Hash, msg.content
    assert_equal "summarize", msg.content[:task]
  end

  def test_to_h
    msg = RobotLab::RobotMessage.build(id: 1, from: "alice", content: "hi")
    hash = msg.to_h

    assert_equal({ id: 1, from: "alice", content: "hi", in_reply_to: nil }, hash)
  end

  def test_to_h_with_reply
    msg = RobotLab::RobotMessage.build(
      id: 2, from: "bob",
      content: "ok",
      in_reply_to: "alice:1"
    )
    hash = msg.to_h

    assert_equal "alice:1", hash[:in_reply_to]
  end
end
