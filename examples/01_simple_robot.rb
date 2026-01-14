#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 1: Simple Robot
#
# Demonstrates creating and running a basic robot with a system prompt.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/01_simple_robot.rb

require_relative "../lib/robot_lab"

# Configure Ruby LLM
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
end

# Create a simple robot
robot = RobotLab.build(
  name: "helper",
  system: <<~PROMPT,
    You are a helpful assistant. Be concise and friendly in your responses.
  PROMPT
  model: RobotLab::RoboticModel.new("claude-sonnet-4", provider: :anthropic)
)

puts "Running simple robot..."
puts "-" * 40

# Run the robot with a simple query
result = robot.run("What is 2 + 2? Please explain your reasoning briefly.")

# Display the result
puts "Robot: #{robot.name}"
puts "Output:"
result.output.each do |message|
  puts "  #{message.content}" if message.respond_to?(:content)
end
puts "-" * 40
puts "Stop reason: #{result.stop_reason}"
