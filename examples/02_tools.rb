#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 2: Robot with Tools
#
# Demonstrates creating a robot with custom tools using RubyLLM::Tool.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/02_tools.rb

require_relative "../lib/robot_lab"

# Configure RobotLab
RobotLab.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.template_path = File.join(__dir__, "prompts")
end

# Define tools using RubyLLM::Tool
class Calculator < RubyLLM::Tool
  description "Performs basic arithmetic operations"

  param :operation,
        type: "string",
        desc: "The operation to perform (add, subtract, multiply, divide)"

  param :a,
        type: "number",
        desc: "First operand"

  param :b,
        type: "number",
        desc: "Second operand"

  def execute(operation:, a:, b:)
    case operation
    when "add" then a + b
    when "subtract" then a - b
    when "multiply" then a * b
    when "divide" then a.to_f / b
    else "Unknown operation: #{operation}"
    end
  end
end

class FortuneCookie < RubyLLM::Tool
  description "Get a fortune cookie message with wisdom and lucky numbers"

  param :category,
        type: "string",
        desc: "The category of fortune (wisdom, love, career, adventure)"

  FORTUNES = {
    "wisdom" => [
      "The obstacle in the path becomes the path.",
      "A journey of a thousand miles begins with a single step.",
      "The best time to plant a tree was 20 years ago. The second best time is now."
    ],
    "love" => [
      "The heart that loves is always young.",
      "To love and be loved is to feel the sun from both sides.",
      "Love is not about finding the right person, but being the right person."
    ],
    "career" => [
      "Opportunity dances with those already on the dance floor.",
      "Your work is your signature. Sign it with excellence.",
      "The expert in anything was once a beginner."
    ],
    "adventure" => [
      "Life shrinks or expands in proportion to one's courage.",
      "Not all who wander are lost.",
      "The biggest adventure you can take is to live the life of your dreams."
    ]
  }.freeze

  def execute(category:)
    {
      category: category,
      fortune: FORTUNES.fetch(category, FORTUNES["wisdom"]).sample,
      lucky_numbers: Array.new(6) { rand(1..49) }.sort
    }
  end
end

# Create robot with tools
robot = RobotLab.build(
  name: "assistant",
  template: :assistant,
  tools: [Calculator, FortuneCookie],
  model: "claude-sonnet-4"
)

puts "Running robot with tools..."
puts "-" * 40

# Run the robot
result = robot.run(message: "What is 15 multiplied by 7? Also, give me a fortune about my career.")

# Display results
puts "Robot: #{robot.name}"
puts "\nOutput:"
result.output.each do |message|
  puts "  #{message.content}" if message.respond_to?(:content)
end

puts "-" * 40
