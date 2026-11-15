# frozen_string_literal: true

require "test_helper"

class MemoryBlockingReadIntegrationTest < Minitest::Test
  def test_blocking_get_unblocks_when_value_written
    memory = RobotLab::Memory.new
    result = nil

    reader = Thread.new { result = memory.get(:answer, wait: 2) }
    sleep 0.05
    memory[:answer] = 42
    reader.join(1)

    assert_equal 42, result
  end

  def test_blocking_get_raises_on_timeout
    memory = RobotLab::Memory.new

    assert_raises(RobotLab::AwaitTimeout) do
      memory.get(:missing, wait: 0.1)
    end
  end

  def test_multi_key_get_wait_is_a_total_deadline
    memory = RobotLab::Memory.new
    writer = Thread.new do
      sleep 0.5
      memory[:a] = 1
      sleep 0.4
      memory[:b] = 2
    end

    # :b arrives at ~0.9s, past the 0.7s budget for the whole call
    assert_raises(RobotLab::AwaitTimeout) do
      memory.get(:a, :b, wait: 0.7)
    end
  ensure
    writer&.join
  end

  def test_multiple_waiters_all_unblock_on_write
    memory = RobotLab::Memory.new
    results = []
    mutex = Mutex.new

    threads = 3.times.map do
      Thread.new do
        v = memory.get(:signal, wait: 2)
        mutex.synchronize { results << v }
      end
    end
    sleep 0.05
    memory[:signal] = "go"
    threads.each { |t| t.join(1) }

    assert_equal 3, results.size
    assert(results.all? { |r| r == "go" })
  end
end
