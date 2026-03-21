# frozen_string_literal: true

module RobotLab
  # Base error class for all RobotLab errors.
  #
  # All RobotLab-specific exceptions inherit from this class.
  class Error < StandardError; end

  # Raised when configuration is invalid or missing required values.
  #
  # @example
  #   raise ConfigurationError, "API key not set"
  class ConfigurationError < Error; end

  # Raised when a requested tool is not found in the manifest.
  #
  # @example
  #   raise ToolNotFoundError, "Tool 'unknown_tool' not found"
  class ToolNotFoundError < Error; end

  # Raised when LLM inference fails.
  #
  # @example
  #   raise InferenceError, "API request failed: 429 Too Many Requests"
  class InferenceError < Error; end

  # Raised when MCP communication fails.
  #
  # @example
  #   raise MCPError, "Connection to MCP server refused"
  class MCPError < Error; end

  # Raised when message bus communication fails.
  #
  # @example
  #   raise BusError, "No bus configured on this robot"
  class BusError < Error; end

  # Raised when a robot's tool call loop exceeds the configured limit.
  #
  # @example
  #   raise ToolLoopError, "Circuit breaker: 26 tool calls exceeded max_tool_rounds (25)"
  class ToolLoopError < InferenceError; end

  # Raised when a required optional gem dependency is not installed.
  #
  # @example
  #   raise DependencyError, "Add gem 'classifier', '~> 2.3' to your Gemfile"
  class DependencyError < ConfigurationError; end
end
