# frozen_string_literal: true

require "test_helper"

# Expose dispatch_async for testing
class UtilsTestHarness
  include RobotLab::Utils
  public :dispatch_async
end

class RobotLab::UtilsTest < Minitest::Test
  def setup
    @harness = UtilsTestHarness.new
  end

  def test_dispatch_async_runs_block
    result = nil

    Async do
      @harness.dispatch_async { result = "done" }
    end

    assert_equal "done", result
  end

  def test_dispatch_async_logs_errors_instead_of_swallowing
    log_output = StringIO.new
    original_logger = RobotLab.config.logger

    begin
      RobotLab.config.logger = Logger.new(log_output)

      Async do
        @harness.dispatch_async { raise RuntimeError, "kaboom" }
      end

      log_output.rewind
      logged = log_output.read

      assert_match(/dispatch_async error/, logged)
      assert_match(/RuntimeError/, logged)
      assert_match(/kaboom/, logged)
    ensure
      RobotLab.config.logger = original_logger
    end
  end

  def test_dispatch_async_does_not_reraise
    # The Async task should complete without propagating the error.
    # If rescue is missing, this test will fail with the raised exception.
    original_logger = RobotLab.config.logger
    RobotLab.config.logger = Logger.new(nil)

    begin
      Async do
        @harness.dispatch_async { raise "should not propagate" }
      end
      pass # reached here means no exception escaped
    ensure
      RobotLab.config.logger = original_logger
    end
  end

  def test_deep_dup_hash
    original = { a: 1, b: { c: 2 } }
    duped = @harness.send(:deep_dup, original)
    duped[:b][:c] = 99
    assert_equal 2, original[:b][:c]
  end

  def test_deep_dup_array
    original = [1, [2, 3], { a: 4 }]
    duped = @harness.send(:deep_dup, original)
    duped[1] << 99
    assert_equal [2, 3], original[1]
  end

  def test_deep_dup_scalar_returns_dup
    result = @harness.send(:deep_dup, "hello")
    assert_equal "hello", result
  end

  def test_deep_dup_integer_returns_same
    result = @harness.send(:deep_dup, 42)
    assert_equal 42, result
  end

  def test_deep_dup_nil_returns_nil
    result = @harness.send(:deep_dup, nil)
    assert_nil result
  end
end
