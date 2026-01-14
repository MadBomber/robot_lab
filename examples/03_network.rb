#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 3: Multi-Robot Network
#
# Demonstrates creating a network of robots with routing.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/03_network.rb

require_relative "../lib/robot_lab"

# Configure Ruby LLM
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
end

model = RobotLab::RoboticModel.new("claude-sonnet-4", provider: :anthropic)

# Create specialized robots
classifier = RobotLab.build(
  name: "classifier",
  system: <<~PROMPT,
    You are a request classifier. Analyze the user's request and classify it
    as either "billing", "technical", or "general".

    Respond with ONLY the category name, nothing else.
  PROMPT
  model: model
)

billing_robot = RobotLab.build(
  name: "billing",
  system: <<~PROMPT,
    You are a billing support specialist. Help users with:
    - Invoice questions
    - Payment issues
    - Subscription management
    - Refunds

    Be professional and helpful.
  PROMPT
  model: model
)

technical_robot = RobotLab.build(
  name: "technical",
  system: <<~PROMPT,
    You are a technical support specialist. Help users with:
    - Bug reports
    - Feature questions
    - Integration help
    - Troubleshooting

    Be technical but clear.
  PROMPT
  model: model
)

general_robot = RobotLab.build(
  name: "general",
  system: <<~PROMPT,
    You are a general support robot. Help users with any questions
    that don't fit into billing or technical categories.

    Be friendly and helpful.
  PROMPT
  model: model
)

# Create router function
router = lambda do |input:, network:, last_result:, call_count:|
  # First call: run classifier
  return ["classifier"] if call_count.zero?

  # Second call: route based on classification
  if call_count == 1
    classification = last_result&.output&.last&.content.to_s.downcase.strip

    case classification
    when /billing/
      network.state.data[:category] = "billing"
      return ["billing"]
    when /technical/
      network.state.data[:category] = "technical"
      return ["technical"]
    else
      network.state.data[:category] = "general"
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
  default_model: model,
  state: RobotLab.create_state(data: { category: nil })
)

puts "Running multi-robot network..."
puts "-" * 40

# Run the network with a billing question
result = network.run("I was charged twice for my subscription last month. Can you help?")

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
