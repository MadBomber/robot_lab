# frozen_string_literal: true

require "test_helper"

class RobotLab::ErrorsTest < Minitest::Test
  def test_nil_is_not_retryable
    refute RobotLab::Errors.retryable?(nil)
  end

  def test_inference_error_is_retryable
    assert RobotLab::Errors.retryable?(RobotLab::InferenceError.new("boom"))
  end

  def test_tool_loop_error_is_not_retryable_despite_being_an_inference_error
    assert RobotLab::ToolLoopError < RobotLab::InferenceError
    refute RobotLab::Errors.retryable?(RobotLab::ToolLoopError.new("circuit breaker"))
  end

  def test_mcp_error_defaults_to_not_retryable
    refute RobotLab::Errors.retryable?(RobotLab::MCPError.new("rejected"))
  end

  def test_mcp_error_retryable_when_flagged_at_raise_site
    assert RobotLab::Errors.retryable?(RobotLab::MCPError.new("connection lost", retryable: true))
  end

  def test_tool_error_defaults_to_not_retryable
    refute RobotLab::Errors.retryable?(RobotLab::ToolError.new("bad input"))
  end

  def test_tool_error_retryable_when_flagged_at_raise_site
    assert RobotLab::Errors.retryable?(RobotLab::ToolError.new("timeout", retryable: true))
  end

  def test_configuration_error_is_never_retryable
    refute RobotLab::Errors.retryable?(RobotLab::ConfigurationError.new("bad config"))
  end

  def test_non_robot_lab_error_is_never_retryable
    refute RobotLab::Errors.retryable?(StandardError.new("generic"))
  end

  def test_retryable_classes_is_frozen_and_contains_inference_error
    classes = RobotLab::Errors.retryable_classes
    assert_includes classes, RobotLab::InferenceError
    assert classes.frozen?
  end
end
