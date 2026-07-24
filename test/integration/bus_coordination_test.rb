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

  # --- respond_to_tasks / serve: symmetric bus responder (B1) --------------

  def test_respond_to_tasks_auto_replies_to_the_sender
    bus = TypedBus::MessageBus.new
    alice = RobotLab::Robot.new(name: "alice", template: :assistant, bus: bus)
    bob   = RobotLab::Robot.new(name: "bob",   template: :assistant, bus: bus)

    bob.respond_to_tasks { |msg| "handled: #{msg.content}" }

    replies = []
    alice.on_message { |msg| replies << msg.content }
    Async { alice.send_message(to: :bob, content: "ping") }
    wait_until(timeout: 2) { replies.any? }

    assert_equal ["handled: ping"], replies
  end

  def test_respond_to_tasks_ignores_replies_and_does_not_loop
    bus = TypedBus::MessageBus.new
    alice = RobotLab::Robot.new(name: "alice", template: :assistant, bus: bus)
    bob   = RobotLab::Robot.new(name: "bob",   template: :assistant, bus: bus)

    bob_hits = 0
    bob.respond_to_tasks { |msg| bob_hits += 1; "re: #{msg.content}" }
    alice.respond_to_tasks { |msg| "ack: #{msg.content}" } # would loop if replies counted as tasks

    Async { alice.send_message(to: :bob, content: "one") }
    sleep 0.3
    assert_equal 1, bob_hits, "reply was treated as a new task (loop)"
  end

  def test_respond_to_tasks_auto_reply_false_sends_nothing
    bus = TypedBus::MessageBus.new
    alice = RobotLab::Robot.new(name: "alice", template: :assistant, bus: bus)
    bob   = RobotLab::Robot.new(name: "bob",   template: :assistant, bus: bus)

    seen = []
    bob.respond_to_tasks(auto_reply: false) { |msg| seen << msg.content; "silent" }
    sent = nil
    Async { sent = alice.send_message(to: :bob, content: "fyi") }
    wait_until(timeout: 2) { seen.any? }
    sleep 0.1

    assert_equal :sent, alice.outbox[sent.key][:status]
  end

  def test_serve_runs_each_task_through_run_and_replies
    bus = TypedBus::MessageBus.new
    alice = RobotLab::Robot.new(name: "alice", template: :assistant, bus: bus)
    bob   = RobotLab::Robot.new(name: "bob",   template: :assistant, bus: bus)

    # Stub #run so we exercise `serve` without an LLM call.
    bob.define_singleton_method(:run) { |content, **| Struct.new(:reply).new("ran(#{content})") }
    bob.serve

    replies = []
    alice.on_message { |msg| replies << msg.content }
    Async { alice.send_message(to: :bob, content: "do it") }
    wait_until(timeout: 2) { replies.any? }

    assert_equal ["ran(do it)"], replies
  end

  # --- A6: concurrent sends keep counter/outbox consistent -----------------

  def test_concurrent_sends_do_not_lose_outbox_entries
    bus = TypedBus::MessageBus.new
    alice = RobotLab::Robot.new(name: "alice", template: :assistant, bus: bus)
    RobotLab::Robot.new(name: "bob", template: :assistant, bus: bus)

    threads = Array.new(50) do |i|
      Thread.new { Async { alice.send_message(to: :bob, content: "m#{i}") } }
    end
    threads.each(&:join)

    assert_equal 50, alice.outbox.size, "lost or clobbered outbox entries under concurrency"
  end
end
