#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 3: Multi-Robot Network
#
# Demonstrates creating a network of robots with conditional routing
# using SimpleFlow's optional step activation.
#
# Usage:
#   ruby examples/03_network.rb

require_relative "common"

SPECIALIST_TASKS = %i[billing technical general].freeze

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

# Shared RunConfig — operational defaults every robot in this network inherits.
#
# RunConfig has no `provider` field (see RunConfig::FIELDS), and an Ollama
# model is absent from RubyLLM's registry, so provider and model still travel
# together on each robot via **llm_opts. The RunConfig carries the settings
# that genuinely are shared.
shared_config = RobotLab::RunConfig.new(temperature: 0.3, max_tool_rounds: 5)

classifier = ClassifierRobot.new(
  **llm_opts,
  name: "classifier",
  template: :classifier,
  config: shared_config
)

billing_robot = RobotLab.build(
  **llm_opts,
  name: "billing",
  template: :billing,
  config: shared_config
)

technical_robot = RobotLab.build(
  **llm_opts,
  name: "technical",
  template: :technical,
  config: shared_config
)

general_robot = RobotLab.build(
  **llm_opts,
  name: "general",
  template: :general,
  config: shared_config
)

# Create network with optional task routing and shared config
network = RobotLab.create_network(name: "support_network", config: shared_config) do
  task :classifier, classifier, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
  task :technical, technical_robot, depends_on: :optional
  task :general, general_robot, depends_on: :optional
end

banner "Multi-Robot Network"
puts "Routing plan:"
puts "  Entry task: classifier"
puts "  Optional specialists: #{SPECIALIST_TASKS.join(', ')}"
puts "  Runtime behavior: classifier activates exactly one specialist"
puts
puts "Underlying SimpleFlow structure:"
puts "  Optional tasks: #{network.to_h[:optional_tasks].join(', ')}"
hr

# Run the network with a billing question
result = network.run(message: "I was charged twice for my subscription last month. Can you help?")

# Display results
puts "Network: #{network.name}"
puts "Executed tasks: #{result.context.keys.grep_v(:run_params).join(', ')}"
puts "Skipped specialists: #{(SPECIALIST_TASKS - result.context.keys).join(', ')}"
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

hr
