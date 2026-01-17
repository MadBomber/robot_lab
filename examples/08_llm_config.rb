#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 8: LLM Configuration via llm.yml
#
# Demonstrates a new concept: placing an llm.yml file in the template's directory
# to configure RubyLLM settings per environment (similar to Rails database.yml).
#
# The llm.yml file supports ERB processing, allowing environment variables
# to be embedded directly in the configuration:
#   <%= ENV['API_KEY'] %>
#   <%= ENV.fetch('MODEL', 'default-model') %>
#
# The llm.yml file structure:
#   - defaults: shared settings inherited by all environments
#   - development: settings for development (default)
#   - test: settings for testing (faster/cheaper models)
#   - production: settings for production deployment
#
# Environment is determined by LLM_ENV, RAILS_ENV, or RACK_ENV.
#
# Supported configuration options (see https://rubyllm.com/configuration/):
#   - Provider API keys (anthropic, openai, gemini, bedrock, etc.)
#   - Provider endpoints (for self-hosted models)
#   - Default models (chat, embedding, image, moderation)
#   - Connection settings (timeout, retries, proxy)
#   - Logging options
#   - RobotLab-specific settings (streaming, iterations)
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/08_llm_config.rb
#   LLM_ENV=test ANTHROPIC_API_KEY=your_key ruby examples/08_llm_config.rb
#   LLM_ENV=production ANTHROPIC_API_KEY=your_key ruby examples/08_llm_config.rb

require_relative "../lib/robot_lab"
require "yaml"
require "erb"

# Helper class to load and parse llm.yml configuration
# Supports ERB processing and Rails database.yml-style inheritance
class LlmConfig
  attr_reader :config, :environment, :config_path

  # All RubyLLM configuration keys organized by category
  PROVIDER_API_KEYS = %i[
    anthropic_api_key openai_api_key gemini_api_key
    deepseek_api_key mistral_api_key perplexity_api_key
    openrouter_api_key gpustack_api_key xai_api_key
    bedrock_api_key bedrock_secret_key bedrock_region bedrock_session_token
    vertexai_project_id vertexai_location
  ].freeze

  PROVIDER_ENDPOINTS = %i[
    openai_api_base gemini_api_base ollama_api_base
    gpustack_api_base xai_api_base
  ].freeze

  OPENAI_OPTIONS = %i[
    openai_organization_id openai_project_id openai_use_system_role
  ].freeze

  DEFAULT_MODELS = %i[
    default_model default_embedding_model
    default_image_model default_moderation_model
  ].freeze

  CONNECTION_SETTINGS = %i[
    request_timeout max_retries retry_interval
    retry_backoff_factor retry_interval_randomness http_proxy
  ].freeze

  LOGGING_OPTIONS = %i[
    log_file log_level log_stream_debug
  ].freeze

  ROBOTLAB_SETTINGS = %i[
    streaming_enabled max_iterations max_tool_iterations
  ].freeze

  ALL_KEYS = (
    PROVIDER_API_KEYS + PROVIDER_ENDPOINTS + OPENAI_OPTIONS +
    DEFAULT_MODELS + CONNECTION_SETTINGS + LOGGING_OPTIONS + ROBOTLAB_SETTINGS
  ).freeze

  def initialize(template_path, template_name)
    @environment = determine_environment
    @config_path = File.join(template_path, template_name.to_s, "llm.yml")
    @config = load_config
  end

  def determine_environment
    ENV["LLM_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
  end

  def load_config
    return {} unless File.exist?(@config_path)

    # Parse YAML with ERB support (like Rails does)
    yaml_content = ERB.new(File.read(@config_path)).result
    full_config = YAML.safe_load(yaml_content, aliases: true)

    # Get environment-specific config, falling back to defaults
    env_config = full_config[@environment] || full_config["defaults"] || {}

    # Symbolize keys and convert types
    normalize_config(env_config)
  end

  def [](key)
    @config[key.to_sym]
  end

  def to_h
    @config
  end

  def exist?
    File.exist?(@config_path)
  end

  # Apply configuration to RubyLLM
  def apply_to_ruby_llm!
    RubyLLM.configure do |c|
      # Provider API Keys
      c.anthropic_api_key = self[:anthropic_api_key] if self[:anthropic_api_key]
      c.openai_api_key = self[:openai_api_key] if self[:openai_api_key]
      c.gemini_api_key = self[:gemini_api_key] if self[:gemini_api_key]
      c.deepseek_api_key = self[:deepseek_api_key] if self[:deepseek_api_key]
      c.mistral_api_key = self[:mistral_api_key] if self[:mistral_api_key]
      c.perplexity_api_key = self[:perplexity_api_key] if self[:perplexity_api_key]
      c.openrouter_api_key = self[:openrouter_api_key] if self[:openrouter_api_key]
      c.gpustack_api_key = self[:gpustack_api_key] if self[:gpustack_api_key]
      c.xai_api_key = self[:xai_api_key] if self[:xai_api_key]

      # AWS Bedrock
      c.bedrock_api_key = self[:bedrock_api_key] if self[:bedrock_api_key]
      c.bedrock_secret_key = self[:bedrock_secret_key] if self[:bedrock_secret_key]
      c.bedrock_region = self[:bedrock_region] if self[:bedrock_region]
      c.bedrock_session_token = self[:bedrock_session_token] if self[:bedrock_session_token]

      # Google Vertex AI
      c.vertexai_project_id = self[:vertexai_project_id] if self[:vertexai_project_id]
      c.vertexai_location = self[:vertexai_location] if self[:vertexai_location]

      # Provider Endpoints
      c.openai_api_base = self[:openai_api_base] if self[:openai_api_base]
      c.gemini_api_base = self[:gemini_api_base] if self[:gemini_api_base]
      c.ollama_api_base = self[:ollama_api_base] if self[:ollama_api_base]
      c.gpustack_api_base = self[:gpustack_api_base] if self[:gpustack_api_base]
      c.xai_api_base = self[:xai_api_base] if self[:xai_api_base]

      # OpenAI-Specific
      c.openai_organization_id = self[:openai_organization_id] if self[:openai_organization_id]
      c.openai_project_id = self[:openai_project_id] if self[:openai_project_id]
      c.openai_use_system_role = self[:openai_use_system_role] unless self[:openai_use_system_role].nil?

      # Default Models
      c.default_model = self[:default_model] if self[:default_model]
      c.default_embedding_model = self[:default_embedding_model] if self[:default_embedding_model]
      c.default_image_model = self[:default_image_model] if self[:default_image_model]
      c.default_moderation_model = self[:default_moderation_model] if self[:default_moderation_model]

      # Connection Settings
      c.request_timeout = self[:request_timeout] if self[:request_timeout]
      c.max_retries = self[:max_retries] if self[:max_retries]
      c.retry_interval = self[:retry_interval] if self[:retry_interval]
      c.retry_backoff_factor = self[:retry_backoff_factor] if self[:retry_backoff_factor]
      c.retry_interval_randomness = self[:retry_interval_randomness] if self[:retry_interval_randomness]
      c.http_proxy = self[:http_proxy] if self[:http_proxy]

      # Logging
      c.log_file = self[:log_file] if self[:log_file]
      c.log_level = self[:log_level].to_sym if self[:log_level]
      c.log_stream_debug = self[:log_stream_debug] unless self[:log_stream_debug].nil?
    end
  end

  # Apply configuration to RobotLab
  def apply_to_robot_lab!
    RobotLab.configure do |c|
      # API keys (RobotLab passes these to RubyLLM)
      c.anthropic_api_key = self[:anthropic_api_key] if self[:anthropic_api_key]
      c.openai_api_key = self[:openai_api_key] if self[:openai_api_key]
      c.gemini_api_key = self[:gemini_api_key] if self[:gemini_api_key]
      c.openrouter_api_key = self[:openrouter_api_key] if self[:openrouter_api_key]
      c.bedrock_api_key = self[:bedrock_api_key] if self[:bedrock_api_key]

      # RobotLab-specific settings
      c.default_model = self[:default_model] if self[:default_model]
      c.streaming_enabled = self[:streaming_enabled] unless self[:streaming_enabled].nil?
      c.max_iterations = self[:max_iterations] if self[:max_iterations]
      c.max_tool_iterations = self[:max_tool_iterations] if self[:max_tool_iterations]
    end
  end

  # Convenience method to apply to both
  def apply!
    apply_to_ruby_llm!
    apply_to_robot_lab!
  end

  # Display configuration summary (hiding sensitive values)
  def summary
    lines = []
    @config.each do |key, value|
      display_value = if key.to_s.include?("api_key") || key.to_s.include?("secret")
                        value ? "[SET]" : "(not set)"
                      elsif value.nil?
                        "(not set)"
                      else
                        value.inspect
                      end
      lines << "  #{key}: #{display_value}"
    end
    lines.join("\n")
  end

  private

  def normalize_config(hash)
    hash.transform_keys(&:to_sym).transform_values do |value|
      convert_type(value)
    end
  end

  def convert_type(value)
    case value
    when "true" then true
    when "false" then false
    when /\A\d+\z/ then value.to_i
    when /\A\d+\.\d+\z/ then value.to_f
    when "", nil then nil
    else value
    end
  end
end

# =============================================================================
# Demonstration
# =============================================================================

puts "=" * 70
puts "Example 8: LLM Configuration via llm.yml (with ERB support)"
puts "=" * 70
puts

template_path = File.join(__dir__, "prompts")
template_name = :llm_config_demo

# Load the llm.yml configuration
llm_config = LlmConfig.new(template_path, template_name)

puts "Environment: #{llm_config.environment}"
puts "Config file: prompts/#{template_name}/llm.yml"
puts "File exists: #{llm_config.exist?}"
puts
puts "Loaded configuration (after ERB processing):"
puts llm_config.summary
puts

# Apply configuration to RobotLab (which also configures RubyLLM)
RobotLab.configure do |config|
  config.template_path = template_path
end
llm_config.apply!

# Create a robot using the template
robot = RobotLab.build(
  name: "config_demo",
  template: template_name,
  model: llm_config[:default_model] || "claude-sonnet-4",
  context: {
    environment: llm_config.environment,
    model: llm_config[:default_model],
    provider: "anthropic"
  }
)

puts "-" * 70
puts "Running robot with #{llm_config.environment} configuration..."
puts "Model: #{llm_config[:default_model] || 'default'}"
puts "Streaming: #{llm_config[:streaming_enabled]}"
puts "Request timeout: #{llm_config[:request_timeout]}s"
puts "Max retries: #{llm_config[:max_retries]}"
puts "-" * 70
puts

# Run the robot
result = robot.run(
  message: "Briefly explain how the llm.yml configuration file works, " \
           "and why it's useful to have environment-specific LLM settings."
)

# Display the result
puts "Response:"
result.output.each do |message|
  puts message.content if message.respond_to?(:content)
end

puts <<~FOOTER

  #{"=" * 70}
  Configuration concept demonstrated successfully!

  The llm.yml file supports ERB and all RubyLLM configuration options:
    - Provider API keys (anthropic, openai, gemini, bedrock, etc.)
    - Custom endpoints (for self-hosted models)
    - Connection settings (timeout, retries, proxy)
    - Logging options

  Example ERB usage in llm.yml:
    anthropic_api_key: <%= ENV['ANTHROPIC_API_KEY'] %>
    default_model: <%= ENV.fetch('LLM_MODEL', 'claude-sonnet-4') %>
    request_timeout: <%= ENV.fetch('LLM_TIMEOUT', '120') %>

  Try running with different environments:
    LLM_ENV=test ruby examples/08_llm_config.rb
    LLM_ENV=production ruby examples/08_llm_config.rb
    LLM_MODEL=claude-haiku-3-5 ruby examples/08_llm_config.rb
  #{"=" * 70}
FOOTER
