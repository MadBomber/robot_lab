# frozen_string_literal: true

require "test_helper"

class RobotLab::ErrorsTest < Minitest::Test
  # .serialize tests
  def test_serialize_returns_hash_with_type_and_message
    error = StandardError.new("Something went wrong")
    result = RobotLab::Errors.serialize(error)

    assert result.is_a?(Hash)
    assert_equal "StandardError", result[:type]
    assert_equal "Something went wrong", result[:message]
  end

  def test_serialize_with_custom_error_class
    error = RobotLab::ConfigurationError.new("Bad config")
    result = RobotLab::Errors.serialize(error)

    assert_equal "RobotLab::ConfigurationError", result[:type]
    assert_equal "Bad config", result[:message]
  end

  def test_serialize_without_backtrace_by_default
    error = StandardError.new("test")
    error.set_backtrace(["line1", "line2"])
    result = RobotLab::Errors.serialize(error)

    refute result.key?(:backtrace)
  end

  def test_serialize_with_backtrace_when_requested
    error = StandardError.new("test")
    error.set_backtrace(["line1", "line2", "line3"])
    result = RobotLab::Errors.serialize(error, include_backtrace: true)

    assert result.key?(:backtrace)
    assert_equal ["line1", "line2", "line3"], result[:backtrace]
  end

  def test_serialize_limits_backtrace_to_10_lines
    backtrace = (1..20).map { |i| "line#{i}" }
    error = StandardError.new("test")
    error.set_backtrace(backtrace)
    result = RobotLab::Errors.serialize(error, include_backtrace: true)

    assert_equal 10, result[:backtrace].size
    assert_equal "line1", result[:backtrace].first
    assert_equal "line10", result[:backtrace].last
  end

  def test_serialize_handles_nil_backtrace
    error = StandardError.new("test")
    result = RobotLab::Errors.serialize(error, include_backtrace: true)

    refute result.key?(:backtrace)
  end

  def test_serialize_includes_cause_when_present
    cause = StandardError.new("Root cause")
    error = begin
      begin
        raise cause
      rescue StandardError
        raise RobotLab::Error, "Wrapper error"
      end
    rescue RobotLab::Error => e
      e
    end

    result = RobotLab::Errors.serialize(error)

    assert result.key?(:cause)
    assert_equal "StandardError", result[:cause][:type]
    assert_equal "Root cause", result[:cause][:message]
  end

  def test_serialize_without_cause
    error = StandardError.new("No cause")
    result = RobotLab::Errors.serialize(error)

    refute result.key?(:cause)
  end

  # .deserialize tests
  def test_deserialize_creates_error_from_hash
    hash = { type: "StandardError", message: "Deserialized error" }
    error = RobotLab::Errors.deserialize(hash)

    assert error.is_a?(StandardError)
    assert_equal "Deserialized error", error.message
  end

  def test_deserialize_with_string_keys
    hash = { "type" => "StandardError", "message" => "String keys" }
    error = RobotLab::Errors.deserialize(hash)

    assert error.is_a?(StandardError)
    assert_equal "String keys", error.message
  end

  def test_deserialize_custom_error_class
    hash = { type: "RobotLab::ConfigurationError", message: "Config problem" }
    error = RobotLab::Errors.deserialize(hash)

    assert error.is_a?(RobotLab::ConfigurationError)
    assert_equal "Config problem", error.message
  end

  def test_deserialize_falls_back_to_standard_error_for_unknown_class
    hash = { type: "UnknownError::Class", message: "Unknown" }
    error = RobotLab::Errors.deserialize(hash)

    assert error.is_a?(StandardError)
    assert_equal "Unknown", error.message
  end

  # .format tests
  def test_format_returns_formatted_string
    error = StandardError.new("Something failed")
    result = RobotLab::Errors.format(error)

    assert_equal "[StandardError] Something failed", result
  end

  def test_format_with_custom_error_class
    error = RobotLab::MCPError.new("Connection refused")
    result = RobotLab::Errors.format(error)

    assert_equal "[RobotLab::MCPError] Connection refused", result
  end

  # .capture tests
  def test_capture_returns_data_on_success
    result = RobotLab::Errors.capture { 42 }

    assert_equal({ data: 42 }, result)
  end

  def test_capture_returns_complex_data
    result = RobotLab::Errors.capture { { answer: 42, items: [1, 2, 3] } }

    assert_equal({ data: { answer: 42, items: [1, 2, 3] } }, result)
  end

  def test_capture_returns_error_on_failure
    result = RobotLab::Errors.capture { raise StandardError, "Boom!" }

    assert result.key?(:error)
    assert_equal "StandardError", result[:error][:type]
    assert_equal "Boom!", result[:error][:message]
  end

  def test_capture_catches_custom_errors
    result = RobotLab::Errors.capture { raise RobotLab::InferenceError, "LLM failed" }

    assert result.key?(:error)
    assert_equal "RobotLab::InferenceError", result[:error][:type]
    assert_equal "LLM failed", result[:error][:message]
  end

  def test_capture_does_not_catch_non_standard_errors
    # SystemExit, SignalException, etc. are not StandardError subclasses
    # They should propagate through
    assert_raises(SystemExit) do
      RobotLab::Errors.capture { exit(1) }
    end
  end
end
