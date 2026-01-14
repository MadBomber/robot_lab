#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 2: Robot with Tools
#
# Demonstrates creating an robot with custom tools.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/02_tools.rb

require_relative "../lib/robot_lab"

# Configure Ruby LLM
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
end

# Define tools
calculator_tool = RobotLab.create_tool(
  name: "calculator",
  description: "Performs basic arithmetic operations",
  parameters: {
    type: "object",
    properties: {
      operation: {
        type: "string",
        enum: %w[add subtract multiply divide],
        description: "The operation to perform"
      },
      a: { type: "number", description: "First operand" },
      b: { type: "number", description: "Second operand" }
    },
    required: %w[operation a b]
  }
) do |input, **_context|
  result = case input[:operation]
  when "add" then input[:a] + input[:b]
  when "subtract" then input[:a] - input[:b]
  when "multiply" then input[:a] * input[:b]
  when "divide" then input[:a].to_f / input[:b]
  else "Unknown operation"
  end
  result
end

fortune_tool = RobotLab.create_tool(
  name: "fortune_cookie",
  description: "Get a fortune cookie message with wisdom and lucky numbers",
  parameters: {
    type: "object",
    properties: {
      category: {
        type: "string",
        enum: %w[wisdom love career adventure],
        description: "The category of fortune to receive"
      }
    },
    required: ["category"]
  }
) do |input, **_context|
  fortunes = {
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
  }

  result = {
    category: input[:category],
    fortune: fortunes[input[:category]].sample,
    lucky_numbers: Array.new(6) { rand(1..49) }.sort
  }.to_json
  result
end

# Create robot with tools
robot = RobotLab.build(
  name: "assistant",
  system: <<~PROMPT,
    You are a helpful assistant with access to tools.
    Use the calculator for math and fortune_cookie for fortune requests.
  PROMPT
  tools: [calculator_tool, fortune_tool],
  model: RobotLab::RoboticModel.new("claude-sonnet-4", provider: :anthropic)
)

puts "Running robot with tools..."
puts "-" * 40

# Run the robot
result = robot.run("What is 15 multiplied by 7? Also, give me a fortune about my career.")

# Display results
puts "Robot: #{robot.name}"
puts "\nOutput:"
result.output.each do |message|
  case message
  when RobotLab::TextMessage
    puts "  Text: #{message.content}"
  when RobotLab::ToolCallMessage
    puts "  Tool calls: #{message.tools.map { |t| t[:name] }.join(', ')}"
  end
end

puts "\nTool Results:"
result.tool_calls.each do |tool_result|
  puts "  #{tool_result.tool.name}: #{tool_result.data}"
end

puts "-" * 40
