# frozen_string_literal: true

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
  def build_network(name:, robots:, **options)
    RobotLab::Network.new(
      name: name,
      robots: robots,
      **options
    )
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
