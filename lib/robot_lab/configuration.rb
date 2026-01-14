# frozen_string_literal: true

module RobotLab
  # Global configuration for RobotLab
  #
  # @example
  #   RobotLab.configure do |config|
  #     config.default_provider = :anthropic
  #     config.default_model = "claude-sonnet-4"
  #     config.template_path = "app/prompts"
  #     config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
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
      @template_path = nil
    end

    # API key setters that configure RubyLLM internally
    def anthropic_api_key=(key)
      RubyLLM.configure { |c| c.anthropic_api_key = key }
    end

    def openai_api_key=(key)
      RubyLLM.configure { |c| c.openai_api_key = key }
    end

    def gemini_api_key=(key)
      RubyLLM.configure { |c| c.gemini_api_key = key }
    end

    def bedrock_api_key=(key)
      RubyLLM.configure { |c| c.bedrock_api_key = key }
    end

    def openrouter_api_key=(key)
      RubyLLM.configure { |c| c.openrouter_api_key = key }
    end

    # Set the template path and configure ruby_llm-template
    #
    # @param path [String] Path to the templates directory
    #
    def template_path=(path)
      @template_path = path
      configure_template_library if path
    end

    def template_path
      @template_path || default_template_path
    end

    private

    def configure_template_library
      require "ruby_llm/template"
      RubyLLM::Template.configure do |config|
        config.template_directory = @template_path
      end
    end

    def default_template_path
      if defined?(Rails) && Rails.root
        Rails.root.join("app", "prompts").to_s
      else
        "prompts"
      end
    end

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
