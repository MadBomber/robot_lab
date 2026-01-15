# frozen_string_literal: true

require "test_helper"

class RobotLab::ErrorTest < Minitest::Test
  # Error class hierarchy tests
  def test_error_inherits_from_standard_error
    assert RobotLab::Error < StandardError
  end

  def test_configuration_error_inherits_from_error
    assert RobotLab::ConfigurationError < RobotLab::Error
  end

  def test_tool_not_found_error_inherits_from_error
    assert RobotLab::ToolNotFoundError < RobotLab::Error
  end

  def test_inference_error_inherits_from_error
    assert RobotLab::InferenceError < RobotLab::Error
  end

  def test_mcp_error_inherits_from_error
    assert RobotLab::MCPError < RobotLab::Error
  end

  # Error instantiation tests
  def test_error_can_be_raised_and_caught
    assert_raises(RobotLab::Error) do
      raise RobotLab::Error, "Something went wrong"
    end
  end

  def test_configuration_error_can_be_raised
    error = assert_raises(RobotLab::ConfigurationError) do
      raise RobotLab::ConfigurationError, "Invalid config"
    end

    assert_equal "Invalid config", error.message
  end

  def test_tool_not_found_error_can_be_raised
    error = assert_raises(RobotLab::ToolNotFoundError) do
      raise RobotLab::ToolNotFoundError, "Tool 'missing' not found"
    end

    assert_equal "Tool 'missing' not found", error.message
  end

  def test_inference_error_can_be_raised
    error = assert_raises(RobotLab::InferenceError) do
      raise RobotLab::InferenceError, "LLM request failed"
    end

    assert_equal "LLM request failed", error.message
  end

  def test_mcp_error_can_be_raised
    error = assert_raises(RobotLab::MCPError) do
      raise RobotLab::MCPError, "MCP connection failed"
    end

    assert_equal "MCP connection failed", error.message
  end

  # Catching by parent class
  def test_specific_errors_caught_by_parent_error
    caught = false

    begin
      raise RobotLab::ConfigurationError, "test"
    rescue RobotLab::Error
      caught = true
    end

    assert caught
  end

  def test_specific_errors_caught_by_standard_error
    caught = false

    begin
      raise RobotLab::ToolNotFoundError, "test"
    rescue StandardError
      caught = true
    end

    assert caught
  end
end
