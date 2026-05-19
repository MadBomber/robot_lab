# frozen_string_literal: true

require 'zeitwerk'
require 'json'
require 'securerandom'
require 'digest'

# Core dependencies
require 'ruby_llm'
require 'prompt_manager'
require 'async'
require 'typed_bus'

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
#   RobotLab.config.ruby_llm.model            #=> "claude-sonnet-4"
#   RobotLab.config.ruby_llm.request_timeout  #=> 120
#
module RobotLab
end

loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
loader.ignore("#{__dir__}/robot_lab/robot")

# Custom inflections for classes that don't follow Zeitwerk naming conventions
loader.inflector.inflect(
  'robot_lab' => 'RobotLab',
  'mcp' => 'MCP',
  'openai' => 'OpenAI',
  'sse' => 'SSE',
  'streamable_http' => 'StreamableHTTP',
  'websocket' => 'WebSocket'
)

loader.setup

# These files define multiple classes that Zeitwerk cannot autoload
# individually (e.g. TextMessage lives in message.rb, not text_message.rb).
# Require them explicitly so their constants are available without eager loading.
require_relative 'robot_lab/error'
require_relative 'robot_lab/message'
require_relative 'robot_lab/memory'

# Eager load everything in Rails or when explicitly requested.
# Otherwise Zeitwerk's lazy autoloading keeps boot fast.
loader.eager_load if defined?(Rails::Engine) || ENV["ROBOT_LAB_EAGER_LOAD"]

module RobotLab
  # Error classes are defined in lib/robot_lab/error.rb

  @extensions = {}

  class << self
    # Registers an extension gem so core can detect it without depending on it.
    #
    # Extension gems call this at load time to announce themselves. Core uses
    # extension_loaded? to guard optional behavior instead of defined?/respond_to?.
    #
    # @param name [Symbol] identifier for the extension (e.g. :durable, :ractor)
    # @param mod [Module, Object] the extension's primary module or a sentinel value
    def register_extension(name, mod)
      @extensions[name] = mod
    end

    # Returns true if the named extension gem has been loaded.
    #
    # @param name [Symbol] extension identifier
    def extension_loaded?(name)
      @extensions.key?(name)
    end

    # Returns the module registered for the named extension, or nil.
    #
    # @param name [Symbol] extension identifier
    def extension(name)
      @extensions[name]
    end

    # Returns the list of registered extension names.
    #
    # @return [Array<Symbol>]
    def loaded_extensions
      @extensions.keys
    end

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
    #   RobotLab.config.ruby_llm.model            #=> "claude-sonnet-4"
    #   RobotLab.config.ruby_llm.request_timeout  #=> 120
    #   RobotLab.config.development?              #=> true
    def config
      @config ||= Config.new.tap(&:after_load)
    end

    # Yields the Config object for block-style configuration.
    #
    # @yield [Config] the config instance
    # @return [Config] the config instance
    #
    # @example
    #   RobotLab.configure do |c|
    #     c.default_model = "claude-sonnet-4"
    #   end
    def configure
      yield config
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
    # @param name [String, nil] the unique identifier for the robot (auto-generated if nil)
    # @param template [Symbol, nil] the prompt_manager template for the robot's prompt
    # @param system_prompt [String, nil] inline system prompt (can be used alone or with template)
    # @param context [Hash] variables to pass to the template
    # @param enable_cache [Boolean] whether to enable semantic caching (default: true)
    # @param options [Hash] additional options passed to Robot.new
    # @return [Robot] a new Robot instance
    #
    # @example Bare robot (no template or prompt)
    #   robot = RobotLab.build
    #   robot.with_instructions("You are helpful.").run("Hello!")
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
    def build(name: "robot", template: nil, system_prompt: nil, context: {}, enable_cache: true, bus: nil, skills: nil,
              config: nil, **)
      Robot.new(
        name: name,
        template: template,
        system_prompt: system_prompt,
        context: context,
        enable_cache: enable_cache,
        bus: bus,
        skills: skills,
        config: config,
        **
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
    def create_network(name:, concurrency: :auto, config: nil, &)
      Network.new(name: name, concurrency: concurrency, config: config, &)
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
    def create_memory(data: {}, enable_cache: true, **)
      Memory.new(data: data, enable_cache: enable_cache, **)
    end
  end
end
