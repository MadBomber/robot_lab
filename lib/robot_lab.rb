# frozen_string_literal: true

require "zeitwerk"
require "json"
require "securerandom"
require "digest"

# Core dependencies
require "ruby_llm"
require "async"

# Define the module first so Zeitwerk can populate it
#
# RobotLab is a Ruby framework for building and orchestrating multi-robot LLM workflows.
# It provides a modular architecture with adapters for multiple LLM providers (Anthropic,
# OpenAI, Gemini), MCP (Model Context Protocol) integration, streaming support, and
# history management.
#
# @example Basic usage with a single robot
#   robot = RobotLab.build(name: "assistant", template: "chat.erb")
#   result = robot.run("Hello, world!")
#
# @example Creating a network of robots
#   network = RobotLab.create_network(name: "pipeline") do
#     step :analyzer, analyzer, depends_on: :none
#     step :writer, writer, depends_on: [:analyzer]
#     step :reviewer, reviewer, depends_on: [:writer]
#   end
#   result = network.run(message: "Process this document")
#
# @example Configuration
#   # Via environment variables (ROBOT_LAB_* prefix)
#   # ROBOT_LAB_DEFAULT_MODEL=gpt-4
#   # ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...
#
#   # Or via config files (~/.config/robot_lab/config.yml or ./config/robot_lab.yml)
#   # See lib/robot_lab/config/defaults.yml for all options
#
#   # Access configuration values:
#   RobotLab.config.default_model           #=> "claude-sonnet-4"
#   RobotLab.config.ruby_llm.request_timeout  #=> 120
#
module RobotLab
end

loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
loader.ignore("#{__dir__}/generators")
loader.ignore("#{__dir__}/robot_lab/rails")

# Custom inflections for classes that don't follow Zeitwerk naming conventions
loader.inflector.inflect(
  "robot_lab" => "RobotLab",
  "robotic_model" => "RoboticModel",
  "mcp" => "MCP",
  "openai" => "OpenAI",
  "sse" => "SSE",
  "streamable_http" => "StreamableHTTP",
  "websocket" => "WebSocket"
)

# Note: adapters/ is NOT collapsed since files define RobotLab::Adapters::* classes

loader.setup

# Eager load for proper constant resolution
loader.eager_load

module RobotLab
  # Error classes are defined in lib/robot_lab/error.rb

  class << self
    # Returns the Config object (MywayConfig-based).
    #
    # Configuration is automatically loaded from:
    # - Bundled defaults (lib/robot_lab/config/defaults.yml)
    # - Environment-specific overrides (development, test, production)
    # - XDG config files (~/.config/robot_lab/config.yml)
    # - Project config (./config/robot_lab.yml)
    # - Environment variables (ROBOT_LAB_*)
    #
    # @return [Config] the config instance
    #
    # @example
    #   RobotLab.config.default_model             #=> "claude-sonnet-4"
    #   RobotLab.config.ruby_llm.request_timeout  #=> 120
    #   RobotLab.config.development?              #=> true
    def config
      @config ||= Config.new.tap(&:after_load)
    end

    # Reload configuration from all sources.
    #
    # Clears the cached Config instance, forcing it to be
    # reloaded on next access.
    #
    # @return [Config] the new config instance
    def reload_config!
      @config = nil
      config
    end

    # Factory method to create a new Robot instance.
    #
    # @param name [String] the unique identifier for the robot
    # @param template [Symbol, nil] the ERB template for the robot's prompt
    # @param system_prompt [String, nil] inline system prompt (can be used alone or with template)
    # @param context [Hash] variables to pass to the template
    # @param enable_cache [Boolean] whether to enable semantic caching (default: true)
    # @param options [Hash] additional options passed to Robot.new
    # @return [Robot] a new Robot instance
    # @raise [ArgumentError] if neither template nor system_prompt is provided
    #
    # @example Robot with template
    #   robot = RobotLab.build(
    #     name: "assistant",
    #     template: :assistant,
    #     context: { tone: "friendly" }
    #   )
    #
    # @example Robot with inline system prompt
    #   robot = RobotLab.build(
    #     name: "helper",
    #     system_prompt: "You are a helpful assistant."
    #   )
    #
    # @example Robot with both template and system prompt
    #   robot = RobotLab.build(
    #     name: "support",
    #     template: :support_agent,
    #     system_prompt: "Today's date is #{Date.today}."
    #   )
    #
    # @example Robot with caching disabled
    #   robot = RobotLab.build(
    #     name: "simple",
    #     system_prompt: "You are helpful.",
    #     enable_cache: false
    #   )
    def build(name:, template: nil, system_prompt: nil, context: {}, enable_cache: true, **options)
      Robot.new(
        name: name,
        template: template,
        system_prompt: system_prompt,
        context: context,
        enable_cache: enable_cache,
        **options
      )
    end

    # Factory method to create a new Network of robots.
    #
    # @param name [String] the unique identifier for the network
    # @param concurrency [Symbol] concurrency model (:auto, :threads, :async)
    # @yield Block for defining pipeline steps
    # @return [Network] a new Network instance
    #
    # @example Sequential pipeline
    #   network = RobotLab.create_network(name: "pipeline") do
    #     step :first, robot1, depends_on: :none
    #     step :second, robot2, depends_on: [:first]
    #   end
    #
    # @example With optional routing
    #   network = RobotLab.create_network(name: "support") do
    #     step :classifier, classifier, depends_on: :none
    #     step :billing, billing_robot, depends_on: :optional
    #     step :technical, technical_robot, depends_on: :optional
    #   end
    #
    # @example Parallel execution
    #   network = RobotLab.create_network(name: "analysis") do
    #     step :fetch, fetcher, depends_on: :none
    #     step :sentiment, sentiment_bot, depends_on: [:fetch]
    #     step :entities, entity_bot, depends_on: [:fetch]
    #     step :merge, merger, depends_on: [:sentiment, :entities]
    #   end
    def create_network(name:, concurrency: :auto, &block)
      Network.new(name: name, concurrency: concurrency, &block)
    end

    # Factory method to create a new Memory object.
    #
    # @param data [Hash] initial runtime data
    # @param enable_cache [Boolean] whether to enable semantic caching (default: true)
    # @param options [Hash] additional options passed to Memory.new
    # @return [Memory] a new Memory instance
    #
    # @example Basic memory
    #   memory = RobotLab.create_memory(data: { user_id: 123 })
    #
    # @example Memory with custom values
    #   memory = RobotLab.create_memory(data: { category: nil })
    #   memory[:session_id] = "abc123"
    #
    # @example Memory with caching disabled
    #   memory = RobotLab.create_memory(data: {}, enable_cache: false)
    def create_memory(data: {}, enable_cache: true, **options)
      Memory.new(data: data, enable_cache: enable_cache, **options)
    end
  end
end

# Load Rails integration if Rails is defined
if defined?(Rails::Engine)
  require "robot_lab/rails/engine"
  require "robot_lab/rails/railtie"
end
