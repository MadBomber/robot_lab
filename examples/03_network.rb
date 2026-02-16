#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 3: Multi-Robot Network
#
# Demonstrates creating a network of robots with conditional routing
# using SimpleFlow's optional step activation.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/03_network.rb

# Configure template path before loading (MywayConfig reads env vars on init)
ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

# Classifier robot that activates the appropriate specialist
class ClassifierRobot < RobotLab::Robot
  def call(result)
    run_context = extract_run_context(result)
    message = run_context.delete(:message)
    robot_result = run(message, **run_context)

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    # Examine LLM output and activate appropriate specialist
    category = robot_result.reply.to_s.strip.downcase

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
  model: "claude-3-haiku-20240307"
)

billing_robot = RobotLab.build(
  name: "billing",
  template: :billing,
  model: "claude-3-haiku-20240307"
)

technical_robot = RobotLab.build(
  name: "technical",
  template: :technical,
  model: "claude-3-haiku-20240307"
)

general_robot = RobotLab.build(
  name: "general",
  template: :general,
  model: "claude-3-haiku-20240307"
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
  puts "   Classification: #{classifier_result.reply}"
end

# Show specialist result (the final value)
if result.value.is_a?(RobotLab::RobotResult)
  puts "\n2. Robot: #{result.value.robot_name}"
  content = result.value.reply
  puts "   Response: #{content[0..200]}..." if content
end

puts "-" * 40
