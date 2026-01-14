# frozen_string_literal: true

module RobotLab
  # Global configuration for RobotLab
  #
  # @example
  #   RobotLab.configure do |config|
  #     config.default_provider = :anthropic
  #     config.default_model = "claude-sonnet-4"
  #     config.max_iterations = 10
  #   end
  #
  class Configuration
    attr_accessor :default_provider,
                  :default_model,
                  :max_iterations,
                  :max_tool_iterations,
                  :streaming_enabled,
                  :logger

    def initialize
      @default_provider = :anthropic
      @default_model = "claude-sonnet-4"
      @max_iterations = 10
      @max_tool_iterations = 10
      @streaming_enabled = true
      @logger = default_logger
    end

    private

    def default_logger
      if defined?(Rails) && Rails.respond_to?(:logger)
        Rails.logger
      else
        require "logger"
        Logger.new($stdout, level: Logger::INFO)
      end
    end
  end
end
