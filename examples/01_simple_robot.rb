#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 1: Simple Robot
#
# Demonstrates creating and running a basic robot with a template.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/01_simple_robot.rb

require_relative "../lib/robot_lab"

# Configure RobotLab
RobotLab.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.template_path = File.join(__dir__, "prompts")
end

# Create a simple robot using a template
robot = RobotLab.build(
  name: "helper",
  template: :helper,
  model: "claude-sonnet-4"
)

puts "Running simple robot..."
puts "-" * 40

# Run the robot with a simple query
result = robot.run(message: "What is 2 + 2? Please explain your reasoning briefly.")

# Display the result
puts "Robot: #{robot.name}"
puts "Output:"
result.output.each do |message|
  puts "  #{message.content}" if message.respond_to?(:content)
end
puts "-" * 40
