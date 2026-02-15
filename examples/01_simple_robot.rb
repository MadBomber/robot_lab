#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 1: Simple Robot
#
# Demonstrates creating and running a basic robot with a template.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/01_simple_robot.rb

# Configure template path before loading (MywayConfig reads env vars on init)
ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

# Create a simple robot using a template
robot = RobotLab.build(
  name: "helper",
  template: :helper,
  model: "claude-3-haiku-20240307"
)

puts "Running simple robot..."
puts "-" * 40

# Run the robot
result = robot.run("What is 2 + 2? Please explain your reasoning briefly.")

# Display the result
puts "Robot: #{robot.name}"
puts "Output:"
result.output.each do |message|
  puts "  #{message.content}" if message.respond_to?(:content)
end
puts "-" * 40
