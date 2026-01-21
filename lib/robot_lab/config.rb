# frozen_string_literal: true

require "myway_config"

module RobotLab
  # Modern configuration class using MywayConfig for RobotLab.
  #
  # Provides:
  # - Nested configuration with a dedicated `ruby_llm:` section
  # - Environment-specific settings (development, test, production)
  # - XDG config file loading (~/.config/robot_lab/config.yml)
  # - Environment variable overrides (ROBOT_LAB_*)
  # - Automatic RubyLLM configuration application
  #
  # @example Access configuration values
  #   RobotLab.config.ruby_llm.model            #=> "claude-sonnet-4"
  #   RobotLab.config.ruby_llm.request_timeout  #=> 120
  #   RobotLab.config.development?              #=> true
  #
  # @example Override via environment variables
  #   # ROBOT_LAB_RUBY_LLM__MODEL=gpt-4
  #   # ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...
  #
  # @example User config file (~/.config/robot_lab/config.yml)
  #   defaults:
  #     ruby_llm:
  #       anthropic_api_key: <%= ENV['ANTHROPIC_API_KEY'] %>
  #
  class Config < MywayConfig::Base
    config_name :robot_lab
    env_prefix :robot_lab
    defaults_path File.expand_path("config/defaults.yml", __dir__)
    auto_configure!

    # @!attribute [rw] logger
    #   @return [Logger] the logger instance (runtime-only, not from config file)
    attr_writer :logger

    # Returns the logger instance.
    #
    # @return [Logger] the configured logger or default
    def logger
      @logger ||= default_logger
    end

    # Apply RubyLLM configuration after loading.
    #
    # This method should be called after initialization to configure
    # the RubyLLM gem with the values from the ruby_llm section,
    # and to set up the template library.
    #
    # @return [void]
    def after_load
      apply_ruby_llm_config!
      apply_template_path!
    end

    # Apply all RubyLLM settings from the ruby_llm configuration section.
    #
    # @return [void]
    def apply_ruby_llm_config!
      return unless ruby_llm

      RubyLLM.configure do |c|
        apply_provider_api_keys(c)
        apply_provider_endpoints(c)
        apply_openai_options(c)
        apply_default_models(c)
        apply_connection_settings(c)
        apply_logging_options(c)
      end
    end

    private

    def apply_provider_api_keys(c)
      c.anthropic_api_key = ruby_llm.anthropic_api_key if ruby_llm.anthropic_api_key
      c.openai_api_key = ruby_llm.openai_api_key if ruby_llm.openai_api_key
      c.gemini_api_key = ruby_llm.gemini_api_key if ruby_llm.gemini_api_key
      c.deepseek_api_key = ruby_llm.deepseek_api_key if ruby_llm.deepseek_api_key
      c.mistral_api_key = ruby_llm.mistral_api_key if ruby_llm.mistral_api_key
      c.perplexity_api_key = ruby_llm.perplexity_api_key if ruby_llm.perplexity_api_key
      c.openrouter_api_key = ruby_llm.openrouter_api_key if ruby_llm.openrouter_api_key
      c.gpustack_api_key = ruby_llm.gpustack_api_key if ruby_llm.gpustack_api_key
      c.xai_api_key = ruby_llm.xai_api_key if ruby_llm.xai_api_key

      # AWS Bedrock
      c.bedrock_api_key = ruby_llm.bedrock_api_key if ruby_llm.bedrock_api_key
      c.bedrock_secret_key = ruby_llm.bedrock_secret_key if ruby_llm.bedrock_secret_key
      c.bedrock_region = ruby_llm.bedrock_region if ruby_llm.bedrock_region
      c.bedrock_session_token = ruby_llm.bedrock_session_token if ruby_llm.bedrock_session_token

      # Google Vertex AI
      c.vertexai_project_id = ruby_llm.vertexai_project_id if ruby_llm.vertexai_project_id
      c.vertexai_location = ruby_llm.vertexai_location if ruby_llm.vertexai_location
    end

    def apply_provider_endpoints(c)
      c.openai_api_base = ruby_llm.openai_api_base if ruby_llm.openai_api_base
      c.gemini_api_base = ruby_llm.gemini_api_base if ruby_llm.gemini_api_base
      c.ollama_api_base = ruby_llm.ollama_api_base if ruby_llm.ollama_api_base
      c.gpustack_api_base = ruby_llm.gpustack_api_base if ruby_llm.gpustack_api_base
      c.xai_api_base = ruby_llm.xai_api_base if ruby_llm.xai_api_base
    end

    def apply_openai_options(c)
      c.openai_organization_id = ruby_llm.openai_organization_id if ruby_llm.openai_organization_id
      c.openai_project_id = ruby_llm.openai_project_id if ruby_llm.openai_project_id
      c.openai_use_system_role = ruby_llm.openai_use_system_role unless ruby_llm.openai_use_system_role.nil?
    end

    def apply_default_models(c)
      c.default_model = ruby_llm.default_model if ruby_llm.default_model
      c.default_embedding_model = ruby_llm.default_embedding_model if ruby_llm.default_embedding_model
      c.default_image_model = ruby_llm.default_image_model if ruby_llm.default_image_model
      c.default_moderation_model = ruby_llm.default_moderation_model if ruby_llm.default_moderation_model
    end

    def apply_connection_settings(c)
      c.request_timeout = ruby_llm.request_timeout if ruby_llm.request_timeout
      c.max_retries = ruby_llm.max_retries if ruby_llm.max_retries
      c.retry_interval = ruby_llm.retry_interval if ruby_llm.retry_interval
      c.retry_backoff_factor = ruby_llm.retry_backoff_factor if ruby_llm.retry_backoff_factor
      c.retry_interval_randomness = ruby_llm.retry_interval_randomness if ruby_llm.retry_interval_randomness
      c.http_proxy = ruby_llm.http_proxy if ruby_llm.http_proxy
    end

    def apply_logging_options(c)
      c.log_file = ruby_llm.log_file if ruby_llm.log_file
      c.log_level = ruby_llm.log_level if ruby_llm.log_level
      c.log_stream_debug = ruby_llm.log_stream_debug unless ruby_llm.log_stream_debug.nil?
    end

    def apply_template_path!
      path = resolved_template_path
      return unless path

      require "ruby_llm/template"
      RubyLLM::Template.configure do |config|
        config.template_directory = path
      end
    end

    def resolved_template_path
      return template_path if template_path

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
