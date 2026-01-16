# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  add_filter "/vendor/"

  add_group "Core", "lib/robot_lab"
  add_group "Adapters", "lib/robot_lab/adapters"
  add_group "MCP", "lib/robot_lab/mcp"
  add_group "History", "lib/robot_lab/history"
  add_group "Streaming", "lib/robot_lab/streaming"
  add_group "Rails", "lib/robot_lab/rails"

  enable_coverage :branch
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "robot_lab"
require "minitest/autorun"

# Configure RobotLab for testing
RobotLab.configure do |config|
  config.logger = Logger.new(nil)
  config.template_path = File.expand_path("../examples/prompts", __dir__)
end

# Test helpers
module RobotLabTestHelpers
  # Create a real Robot instance for testing
  def build_robot(name:, template: :assistant, **options)
    RobotLab::Robot.new(
      name: name,
      template: template,
      **options
    )
  end

  # Create a real Network instance for testing
  def build_network(name:, **options, &block)
    RobotLab::Network.new(name: name, **options, &block)
  end

  # Create a Tool for testing
  def build_tool(name:, description: "Test tool", &block)
    RobotLab::Tool.new(
      name: name,
      description: description,
      &block
    )
  end
end

class Minitest::Test
  include RobotLabTestHelpers
end
