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
