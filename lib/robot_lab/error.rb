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
end
