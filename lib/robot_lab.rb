# frozen_string_literal: true

require "zeitwerk"
require "json"
require "securerandom"
require "digest"

# Core dependencies
require "ruby_llm"
require "async"

# Define the module first so Zeitwerk can populate it
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
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    # Factory methods for creating robots and networks
    def build(name:, template:, context: {}, **options)
      Robot.new(name: name, template: template, context: context, **options)
    end

    def create_network(name:, robots:, **options)
      Network.new(name: name, robots: robots, **options)
    end

    def create_state(data: {}, **options)
      State.new(data: data, **options)
    end
  end
end

# Load Rails integration if Rails is defined
if defined?(Rails::Engine)
  require "robot_lab/rails/engine"
  require "robot_lab/rails/railtie"
end
