# frozen_string_literal: true

require "test_helper"

class RobotLab::WaiterTest < Minitest::Test
  def test_wait_blocks_until_signal
    waiter = RobotLab::Waiter.new
    result = nil

    thread = Thread.new do
      result = waiter.wait
    end

    sleep 0.05
    waiter.signal("hello")

    thread.join(1)

    assert_equal "hello", result
  end

  def test_wait_returns_immediately_if_already_signaled
    waiter = RobotLab::Waiter.new
    waiter.signal("already")

    result = waiter.wait
    assert_equal "already", result
  end

  def test_wait_with_timeout_returns_timeout_symbol
    waiter = RobotLab::Waiter.new

    result = waiter.wait(timeout: 0.1)

    assert_equal :timeout, result
  end

  def test_wait_with_timeout_returns_value_if_signaled_in_time
    waiter = RobotLab::Waiter.new
    result = nil

    thread = Thread.new do
      result = waiter.wait(timeout: 2)
    end

    sleep 0.05
    waiter.signal("in time")

    thread.join(1)

    assert_equal "in time", result
  end

  def test_signaled_returns_false_initially
    waiter = RobotLab::Waiter.new
    refute waiter.signaled?
  end

  def test_signaled_returns_true_after_signal
    waiter = RobotLab::Waiter.new
    waiter.signal("value")
    assert waiter.signaled?
  end

  def test_multiple_waiters_all_receive_signal
    waiter = RobotLab::Waiter.new
    results = []
    mutex = Mutex.new

    threads = 3.times.map do
      Thread.new do
        value = waiter.wait
        mutex.synchronize { results << value }
      end
    end

    sleep 0.05
    waiter.signal("broadcast")

    threads.each { |t| t.join(1) }

    assert_equal 3, results.size
    assert results.all? { |r| r == "broadcast" }
  end

  def test_signal_with_nil_value
    waiter = RobotLab::Waiter.new
    waiter.signal(nil)

    # Should return nil, not :timeout
    assert waiter.signaled?
  end
end
