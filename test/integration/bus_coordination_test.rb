# frozen_string_literal: true

require "test_helper"

class BusCoordinationIntegrationTest < Minitest::Test
  def test_broadcast_reaches_subscriber
    bus = TypedBus::MessageBus.new
    alice = RobotLab::Robot.new(name: "alice", template: :assistant, bus: bus)
    bob   = RobotLab::Robot.new(name: "bob",   template: :assistant, bus: bus)

    received = []
    bob.on_message { |msg| received << msg.content }

    Async { alice.send_message(to: :bob, content: "ping") }
    wait_until(timeout: 2) { received.size >= 1 }

    assert_equal ["ping"], received
  end

  def test_reply_correlates_with_sent_message
    bus = TypedBus::MessageBus.new
    alice = RobotLab::Robot.new(name: "alice", template: :assistant, bus: bus)
    bob   = RobotLab::Robot.new(name: "bob",   template: :assistant, bus: bus)

    alice_received = []
    alice.on_message { |msg| alice_received << msg }
    bob.on_message do |msg|
      bob.send_reply(to: :alice, content: "pong", in_reply_to: msg.key)
    end

    sent = nil
    Async { sent = alice.send_message(to: :bob, content: "ping") }
    wait_until(timeout: 2) { alice_received.size >= 1 }

    assert_equal "pong", alice_received.first.content
    assert_equal sent.key, alice_received.first.in_reply_to
  end

  def test_default_handler_is_no_op_no_llm_call
    bus = TypedBus::MessageBus.new
    alice = RobotLab::Robot.new(name: "alice", template: :assistant, bus: bus)
    bob   = RobotLab::Robot.new(name: "bob",   template: :assistant, bus: bus)

    llm_called = false
    bob_chat = bob.instance_variable_get(:@chat)
    bob_chat.define_singleton_method(:ask) { |*| llm_called = true }

    Async { alice.send_message(to: :bob, content: "hello") }
    sleep 0.2

    refute llm_called, "default handler must not trigger LLM"
  end
end
