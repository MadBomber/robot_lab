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
  #
  #     # Global MCP servers available to all networks and robots
  #     config.mcp = [
  #       { name: "github", transport: { type: "stdio", command: "github-mcp" } }
  #     ]
  #
  #     # Global tools whitelist (only these tools are available)
  #     config.tools = %w[search_code create_issue]
  #   end
  #
  class Configuration
    # @!attribute [rw] default_provider
    #   @return [Symbol] the default LLM provider (defaults to :anthropic)
    # @!attribute [rw] default_model
    #   @return [String] the default model to use (defaults to "claude-sonnet-4")
    # @!attribute [rw] max_iterations
    #   @return [Integer] maximum robot iterations per network run (defaults to 10)
    # @!attribute [rw] max_tool_iterations
    #   @return [Integer] maximum tool iterations per robot run (defaults to 10)
    # @!attribute [rw] streaming_enabled
    #   @return [Boolean] whether streaming is enabled by default (defaults to true)
    # @!attribute [rw] logger
    #   @return [Logger] the logger instance
    # @!attribute [rw] mcp
    #   @return [Symbol, Array] global MCP server configuration (:none, :inherit, or array)
    # @!attribute [rw] tools
    #   @return [Symbol, Array] global tools whitelist (:none, :inherit, or array)
    attr_accessor :default_provider,
                  :default_model,
                  :max_iterations,
                  :max_tool_iterations,
                  :streaming_enabled,
                  :logger,
                  :mcp,
                  :tools

    # Creates a new Configuration with default values.
    def initialize
      @default_provider = :anthropic
      @default_model = "claude-sonnet-4"
      @max_iterations = 10
      @max_tool_iterations = 10
      @streaming_enabled = true
      @logger = default_logger
      @template_path = nil
      @mcp = :none
      @tools = :none
    end

    # Sets the Anthropic API key.
    #
    # @param key [String] the API key
    # @return [void]
    def anthropic_api_key=(key)
      RubyLLM.configure { |c| c.anthropic_api_key = key }
    end

    # Sets the OpenAI API key.
    #
    # @param key [String] the API key
    # @return [void]
    def openai_api_key=(key)
      RubyLLM.configure { |c| c.openai_api_key = key }
    end

    # Sets the Google Gemini API key.
    #
    # @param key [String] the API key
    # @return [void]
    def gemini_api_key=(key)
      RubyLLM.configure { |c| c.gemini_api_key = key }
    end

    # Sets the AWS Bedrock API key.
    #
    # @param key [String] the API key
    # @return [void]
    def bedrock_api_key=(key)
      RubyLLM.configure { |c| c.bedrock_api_key = key }
    end

    # Sets the OpenRouter API key.
    #
    # @param key [String] the API key
    # @return [void]
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

    # Returns the template path.
    #
    # @return [String] the configured template path or default
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
