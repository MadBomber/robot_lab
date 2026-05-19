#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 1: Simple Robot
#
# Demonstrates creating and running a basic robot with a template.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/01_simple_robot.rb

require_relative "common"

# Create a simple robot using a template
robot = RobotLab.build(
  model: LLM[:default].model,
  name: "helper",
  template: :helper
)

banner "Simple Robot"

# Run the robot
result = robot.run("What is 2 + 2? Please explain your reasoning briefly.")

# Display the result
puts "Robot: #{robot.name}"
puts "Output:"
result.output.each do |message|
  puts "  #{message.content}" if message.respond_to?(:content)
end
hr
