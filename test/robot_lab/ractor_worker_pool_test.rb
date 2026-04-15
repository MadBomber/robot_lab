# frozen_string_literal: true

require "test_helper"
require "ractor_queue"

# A minimal ractor-safe tool for pool testing.
# Must be defined at the top level so Ractors can const_get it.
class RactorSafeDoubler < RobotLab::Tool
  description "Doubles a number"
  param :value, type: "number", desc: "The number"
  ractor_safe true

  def execute(value:)
    value * 2
  end
end

class AlwaysFailTool < RobotLab::Tool
  description "Always fails"
  ractor_safe true

  def execute(**); raise "tool exploded"; end
end

class RobotLab::RactorWorkerPoolTest < Minitest::Test
  def setup
    @pool = RobotLab::RactorWorkerPool.new(size: 2)
  end

  def teardown
    @pool.shutdown
  end

  def test_submit_returns_result
    result = @pool.submit("RactorSafeDoubler", { "value" => 5 })
    assert_equal 10, result
  end

  def test_submit_multiple_concurrent_jobs
    futures = 4.times.map do |i|
      Thread.new { @pool.submit("RactorSafeDoubler", { "value" => i }) }
    end
    results = futures.map(&:value)
    assert_equal [0, 2, 4, 6], results.sort
  end

  def test_submit_raises_tool_error_on_tool_exception
    assert_raises(RobotLab::ToolError) do
      @pool.submit("AlwaysFailTool", {})
    end
  end

  def test_pool_size
    assert_equal 2, @pool.size
  end

  def test_shutdown_is_idempotent
    @pool.shutdown
    @pool.shutdown  # should not raise
  end
end
