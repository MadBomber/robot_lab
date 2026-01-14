#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 5: Streaming Events
#
# Demonstrates real-time streaming of robot responses.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/05_streaming.rb

require_relative "../lib/robot_lab"

# Configure Ruby LLM
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
end

# Create a streaming handler
streaming_handler = lambda do |event|
  case event[:event]
  when RobotLab::Streaming::Events::RUN_STARTED
    puts "[#{event[:data][:scope]}] Run started: #{event[:data][:run_id]}"
    puts "-" * 40

  when RobotLab::Streaming::Events::TEXT_DELTA
    # Print text deltas without newline for streaming effect
    print event[:data][:delta]
    $stdout.flush

  when RobotLab::Streaming::Events::TOOL_CALL_ARGUMENTS_DELTA
    puts "[Tool call] #{event[:data][:tool_name]}: #{event[:data][:delta]}"

  when RobotLab::Streaming::Events::TOOL_CALL_OUTPUT_DELTA
    puts "[Tool output] #{event[:data][:delta]}"

  when RobotLab::Streaming::Events::RUN_COMPLETED
    puts ""
    puts "-" * 40
    puts "[#{event[:data][:scope]}] Run completed"

  when RobotLab::Streaming::Events::RUN_FAILED
    puts ""
    puts "[ERROR] Run failed: #{event[:data][:error]}"

  else
    # Log other events at debug level
    # puts "[DEBUG] #{event[:event]}: #{event[:data].keys.join(', ')}"
  end
end

# Create streaming context for testing
context = RobotLab::Streaming::Context.new(
  run_id: SecureRandom.uuid,
  message_id: SecureRandom.uuid,
  scope: "robot",
  publish: streaming_handler
)

puts "Streaming Events Example"
puts "=" * 40
puts ""

# Simulate streaming events
puts "Simulating streaming events:"
puts ""

# Simulate run started
context.publish_event(
  event: RobotLab::Streaming::Events::RUN_STARTED,
  data: {}
)

# Simulate text streaming
text = "Hello! I'm demonstrating streaming output. Each word appears as it's generated, creating a real-time effect."
text.split(" ").each do |word|
  context.publish_event(
    event: RobotLab::Streaming::Events::TEXT_DELTA,
    data: { delta: word + " " }
  )
  sleep 0.1 # Simulate generation delay
end

# Simulate completion
context.publish_event(
  event: RobotLab::Streaming::Events::RUN_COMPLETED,
  data: {}
)

puts ""
puts "=" * 40
puts ""
puts "Using streaming with an robot:"
puts ""
puts <<~CODE
  # Create robot with streaming
  robot = RobotLab.build(
    name: "streamer",
    system: "You are helpful",
    model: model
  )

  # Run with streaming callback
  result = robot.run("Tell me a story") do |event|
    case event[:event]
    when "text.delta"
      print event[:data][:delta]
    when "run.completed"
      puts "\\nDone!"
    end
  end
CODE

puts ""
puts "Or with a network:"
puts ""
puts <<~CODE
  streaming_handler = ->(event) { broadcast_to_websocket(event) }

  network.run(
    "Process this request",
    streaming: streaming_handler
  )
CODE
