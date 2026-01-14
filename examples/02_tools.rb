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
  case input[:operation]
  when "add" then input[:a] + input[:b]
  when "subtract" then input[:a] - input[:b]
  when "multiply" then input[:a] * input[:b]
  when "divide" then input[:a].to_f / input[:b]
  else "Unknown operation"
  end
end

weather_tool = RobotLab.create_tool(
  name: "get_weather",
  description: "Get the current weather for a location",
  parameters: {
    type: "object",
    properties: {
      location: { type: "string", description: "City name" }
    },
    required: ["location"]
  }
) do |input, **_context|
  # Simulated weather data
  {
    location: input[:location],
    temperature: rand(60..85),
    conditions: %w[sunny cloudy rainy].sample
  }.to_json
end

# Create robot with tools
robot = RobotLab.build(
  name: "assistant",
  system: <<~PROMPT,
    You are a helpful assistant with access to tools.
    Use the calculator for math and get_weather for weather queries.
  PROMPT
  tools: [calculator_tool, weather_tool],
  model: RobotLab::RoboticModel.new("claude-sonnet-4", provider: :anthropic)
)

puts "Running robot with tools..."
puts "-" * 40

# Run the robot
result = robot.run("What is 15 multiplied by 7? Also, what's the weather in Tokyo?")

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
  puts "  #{tool_result.tool_name}: #{tool_result.content}"
end

puts "-" * 40
