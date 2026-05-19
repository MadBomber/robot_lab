# frozen_string_literal: true

require "test_helper"

class MemoryPubSubIntegrationTest < Minitest::Test
  def test_subscribe_fires_callback_on_write
    memory = RobotLab::Memory.new
    received = []

    memory.subscribe(:status) { |change| received << change.value }
    memory[:status] = "done"

    wait_until(timeout: 1) { received.size >= 1 }
    assert_equal ["done"], received
  end

  def test_multiple_subscribers_all_fire
    memory = RobotLab::Memory.new
    a_got = []
    b_got = []

    memory.subscribe(:msg) { |change| a_got << change.value }
    memory.subscribe(:msg) { |change| b_got << change.value }
    memory[:msg] = "hello"

    wait_until(timeout: 1) { a_got.size >= 1 && b_got.size >= 1 }
    assert_equal ["hello"], a_got
    assert_equal ["hello"], b_got
  end

  def test_subscribe_pattern_fires_on_matching_keys
    memory = RobotLab::Memory.new
    received_keys = []

    memory.subscribe_pattern("result_*") { |change| received_keys << change.key }
    memory[:result_a] = 1
    memory[:result_b] = 2
    memory[:other]    = 3

    wait_until(timeout: 1) { received_keys.size >= 2 }
    assert_includes received_keys, :result_a
    assert_includes received_keys, :result_b
    refute_includes received_keys, :other
  end

  def test_callback_receives_previous_and_new_value
    memory = RobotLab::Memory.new
    changes = []

    memory.subscribe(:counter) { |change| changes << [change.previous, change.value] }
    memory[:counter] = 1
    wait_until(timeout: 1) { changes.size >= 1 }
    memory[:counter] = 2
    wait_until(timeout: 1) { changes.size >= 2 }

    assert_equal [nil, 1], changes[0]
    assert_equal [1,   2], changes[1]
  end
end
