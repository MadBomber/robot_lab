#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 3: Multi-Robot Network
#
# Demonstrates creating a network of robots with conditional routing
# using SimpleFlow's optional step activation.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/03_network.rb

require_relative "../lib/robot_lab"

# Configure RobotLab
RobotLab.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.template_path = File.join(__dir__, "prompts")
end

# Classifier robot that activates the appropriate specialist
class ClassifierRobot < RobotLab::Robot
  def call(result)
    robot_result = run(**extract_run_context(result))

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    # Examine LLM output and activate appropriate specialist
    category = robot_result.last_text_content.to_s.strip.downcase

    case category
    when /billing/
      new_result.activate(:billing)
    when /technical/
      new_result.activate(:technical)
    else
      new_result.activate(:general)
    end
  end
end

# Create specialized robots
classifier = ClassifierRobot.new(
  name: "classifier",
  template: :classifier,
  model: "claude-sonnet-4"
)

billing_robot = RobotLab.build(
  name: "billing",
  template: :billing,
  model: "claude-sonnet-4"
)

technical_robot = RobotLab.build(
  name: "technical",
  template: :technical,
  model: "claude-sonnet-4"
)

general_robot = RobotLab.build(
  name: "general",
  template: :general,
  model: "claude-sonnet-4"
)

# Create network with optional task routing
network = RobotLab.create_network(name: "support_network") do
  task :classifier, classifier, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
  task :technical, technical_robot, depends_on: :optional
  task :general, general_robot, depends_on: :optional
end

puts "Running multi-robot network..."
puts "-" * 40
puts "Network structure:"
puts network.visualize
puts "-" * 40

# Run the network with a billing question
result = network.run(message: "I was charged twice for my subscription last month. Can you help?")

# Display results
puts "Network: #{network.name}"
puts "\nConversation flow:"

# Show classifier result
if result.context[:classifier]
  classifier_result = result.context[:classifier]
  puts "\n1. Robot: classifier"
  puts "   Classification: #{classifier_result.last_text_content}"
end

# Show specialist result (the final value)
if result.value.is_a?(RobotLab::RobotResult)
  puts "\n2. Robot: #{result.value.robot_name}"
  content = result.value.last_text_content
  puts "   Response: #{content[0..200]}..." if content
end

puts "-" * 40
