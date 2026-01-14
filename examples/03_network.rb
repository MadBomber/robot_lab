#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 3: Multi-Robot Network
#
# Demonstrates creating a network of robots with routing.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/03_network.rb

require_relative "../lib/robot_lab"

# Configure RobotLab
RobotLab.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.template_path = File.join(__dir__, "prompts")
end

# Create specialized robots using templates
classifier = RobotLab.build(
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

# Create router function
router = lambda do |args|
  # First call: run classifier
  return ["classifier"] if args.call_count.zero?

  # Second call: route based on classification
  if args.call_count == 1
    classification = args.last_result&.output&.last&.content.to_s.downcase.strip

    case classification
    when /billing/
      args.network.state.data[:category] = "billing"
      return ["billing"]
    when /technical/
      args.network.state.data[:category] = "technical"
      return ["technical"]
    else
      args.network.state.data[:category] = "general"
      return ["general"]
    end
  end

  # After specialist responds, we're done
  nil
end

# Create network
network = RobotLab.create_network(
  name: "support_network",
  robots: [classifier, billing_robot, technical_robot, general_robot],
  router: router,
  state: RobotLab.create_state(data: { category: nil })
)

puts "Running multi-robot network..."
puts "-" * 40

# Run the network with a billing question
result = network.run(message: "I was charged twice for my subscription last month. Can you help?")

# Display results
puts "Network: #{network.name}"
puts "Final category: #{result.state.data[:category]}"
puts "\nConversation flow:"
result.state.results.each_with_index do |robot_result, index|
  puts "\n#{index + 1}. Robot: #{robot_result.robot_name}"
  robot_result.output.each do |message|
    puts "   #{message.content[0..100]}..." if message.respond_to?(:content)
  end
end

puts "-" * 40
