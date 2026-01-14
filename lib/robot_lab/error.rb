# frozen_string_literal: true

module RobotLab
  # Base error class for all RobotLab errors
  class Error < StandardError; end

  # Configuration errors
  class ConfigurationError < Error; end

  # Tool errors
  class ToolNotFoundError < Error; end

  # Inference/LLM errors
  class InferenceError < Error; end

  # MCP errors
  class MCPError < Error; end
end
