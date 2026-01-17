#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 7: Network Memory with Concurrent Robots
#
# Demonstrates the reactive shared memory system where:
# - Multiple robots run concurrently and write to shared memory
# - Robots can wait for values written by other robots
# - Subscriptions provide real-time notifications of memory changes
# - Network broadcast sends messages to all robots
#
# Architecture:
#   ┌─────────────────────────────────────────────────────────────┐
#   │                    PARALLEL ANALYSIS                         │
#   │                                                              │
#   │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
#   │  │  Sentiment  │  │  Entities   │  │  Keywords   │         │
#   │  │  Analyzer   │  │  Extractor  │  │  Extractor  │         │
#   │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
#   │         │                │                │                 │
#   │         ▼                ▼                ▼                 │
#   │  memory.set(       memory.set(      memory.set(            │
#   │   :sentiment)       :entities)       :keywords)            │
#   │         │                │                │                 │
#   │         └────────────────┼────────────────┘                 │
#   │                          ▼                                  │
#   │  ┌──────────────────────────────────────────────────────┐  │
#   │  │                  SHARED MEMORY                        │  │
#   │  │  { sentiment: {...}, entities: {...}, keywords: {...} │  │
#   │  └──────────────────────────────────────────────────────┘  │
#   │                          │                                  │
#   │                          ▼                                  │
#   │  ┌──────────────────────────────────────────────────────┐  │
#   │  │                   Synthesizer                         │  │
#   │  │    memory.get(:sentiment, :entities, :keywords,       │  │
#   │  │               wait: true)                             │  │
#   │  └──────────────────────────────────────────────────────┘  │
#   │                                                              │
#   └─────────────────────────────────────────────────────────────┘
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/07_network_memory.rb

require_relative "../lib/robot_lab"
require "json"

# Configure RobotLab
RobotLab.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.template_path = File.join(__dir__, "prompts")
end

puts "=" * 60
puts "Example 7: Network Memory with Concurrent Robots"
puts "=" * 60
puts

# -----------------------------------------------------------------------------
# Custom Robot Classes that Write to Shared Memory
# -----------------------------------------------------------------------------

# Base class for analysis robots that write results to memory
class AnalysisRobot < RobotLab::Robot
  def initialize(memory_key:, **opts)
    super(**opts)
    @memory_key = memory_key
  end

  def call(result)
    run_context = extract_run_context(result)
    network_memory = run_context.delete(:network_memory)

    robot_result = run(network_memory: network_memory, **run_context)

    # Parse the JSON response and write to shared memory
    if network_memory
      content = robot_result.last_text_content.to_s

      # Set writer before writing to memory
      network_memory.current_writer = @name

      begin
        parsed = JSON.parse(content)
        network_memory.set(@memory_key, parsed)
        puts "  [#{@name}] Wrote JSON to memory[:#{@memory_key}]"
      rescue JSON::ParserError
        # If not valid JSON, store the raw text
        network_memory.set(@memory_key, content)
        puts "  [#{@name}] Wrote text to memory[:#{@memory_key}]"
      end
    end

    result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)
  end
end

# Synthesizer robot that reads from shared memory and synthesizes results
class SynthesizerRobot < RobotLab::Robot
  def call(result)
    run_context = extract_run_context(result)
    network_memory = run_context.delete(:network_memory)

    puts "  [#{@name}] Reading analysis results from memory..."

    if network_memory
      # Read results from memory - they should already be there since
      # SimpleFlow ensures our dependencies completed first
      sentiment = network_memory.get(:sentiment)
      entities = network_memory.get(:entities)
      keywords = network_memory.get(:keywords)

      puts "  [#{@name}] Got sentiment: #{sentiment.nil? ? 'nil' : 'present'}"
      puts "  [#{@name}] Got entities: #{entities.nil? ? 'nil' : 'present'}"
      puts "  [#{@name}] Got keywords: #{keywords.nil? ? 'nil' : 'present'}"

      # Format for the template
      run_context[:sentiment] = format_for_template(sentiment)
      run_context[:entities] = format_for_template(entities)
      run_context[:keywords] = format_for_template(keywords)
    else
      run_context[:sentiment] = "Not available"
      run_context[:entities] = "Not available"
      run_context[:keywords] = "Not available"
    end

    robot_result = run(network_memory: network_memory, **run_context)

    result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)
  end

  private

  def format_for_template(value)
    case value
    when Hash, Array
      JSON.pretty_generate(value)
    when nil
      "Not available"
    else
      value.to_s
    end
  end
end

# -----------------------------------------------------------------------------
# Create the Robots
# -----------------------------------------------------------------------------

sentiment_robot = AnalysisRobot.new(
  name: "sentiment_analyzer",
  template: :sentiment_analyzer,
  memory_key: :sentiment,
  model: "claude-sonnet-4"
)

entity_robot = AnalysisRobot.new(
  name: "entity_extractor",
  template: :entity_extractor,
  memory_key: :entities,
  model: "claude-sonnet-4"
)

keyword_robot = AnalysisRobot.new(
  name: "keyword_extractor",
  template: :keyword_extractor,
  memory_key: :keywords,
  model: "claude-sonnet-4"
)

synthesizer = SynthesizerRobot.new(
  name: "synthesizer",
  template: :synthesizer,
  model: "claude-sonnet-4"
)

# -----------------------------------------------------------------------------
# Create the Network with Shared Memory
# -----------------------------------------------------------------------------

network = RobotLab.create_network(name: "parallel_analysis") do
  # Three analysis robots run in parallel (all depend on nothing)
  task :sentiment, sentiment_robot, depends_on: :none
  task :entities, entity_robot, depends_on: :none
  task :keywords, keyword_robot, depends_on: :none

  # Synthesizer waits for all three to complete
  task :synthesize, synthesizer, depends_on: [:sentiment, :entities, :keywords]
end

# -----------------------------------------------------------------------------
# Set Up Memory Subscriptions (for monitoring)
# -----------------------------------------------------------------------------

puts "Setting up memory subscriptions for monitoring..."
puts

# Note: In concurrent execution, change.writer may be unreliable due to race
# conditions. For production use, consider including writer info in the value.
network.memory.subscribe(:sentiment, :entities, :keywords) do |change|
  value_preview = case change.value
                  when Hash then change.value.keys.join(", ")
                  when String then change.value[0..50]
                  else change.value.class.name
                  end
  puts "  [MONITOR] Memory[:#{change.key}] updated with keys: #{value_preview}"
end

# -----------------------------------------------------------------------------
# Set Up Broadcast Handler
# -----------------------------------------------------------------------------

network.on_broadcast do |message|
  puts "  [BROADCAST] #{message[:payload][:event]}: #{message[:payload][:details]}"
end

# -----------------------------------------------------------------------------
# Run the Network
# -----------------------------------------------------------------------------

sample_text = <<~TEXT
  Apple Inc. announced today that CEO Tim Cook will be presenting the new iPhone 15
  at their headquarters in Cupertino, California on September 12th, 2024.
  Industry analysts are extremely excited about the new features, though some
  consumer advocates have expressed concerns about the expected price increase.
  Samsung and Google are reportedly preparing competitive responses for later this year.
TEXT

puts "Network structure:"
puts network.visualize
puts
puts "-" * 60
puts "Input text:"
puts sample_text.strip
puts "-" * 60
puts

# Send a broadcast before starting
network.broadcast(event: "analysis_started", details: "Beginning parallel analysis")

puts "Running parallel analysis..."
puts
start_time = Time.now

result = network.run(message: sample_text)

elapsed = Time.now - start_time
puts
puts "-" * 60
puts "Analysis complete in #{elapsed.round(2)} seconds"
puts "-" * 60

# Send completion broadcast
network.broadcast(event: "analysis_complete", details: "All robots finished")

# -----------------------------------------------------------------------------
# Display Results
# -----------------------------------------------------------------------------

puts
puts "=" * 60
puts "FINAL SYNTHESIS"
puts "=" * 60
puts

if result.value.is_a?(RobotLab::RobotResult)
  puts result.value.last_text_content
end

puts
puts "=" * 60
puts "MEMORY STATE"
puts "=" * 60
puts

# Show what's in shared memory
memory = network.memory
puts "Sentiment: #{memory.get(:sentiment)&.to_json}"
puts
puts "Entities: #{memory.get(:entities)&.to_json}"
puts
puts "Keywords: #{memory.get(:keywords)&.to_json}"

# -----------------------------------------------------------------------------
# Demonstrate Blocking Wait (without pipeline dependencies)
# -----------------------------------------------------------------------------

puts
puts "=" * 60
puts "DEMONSTRATING BLOCKING WAIT"
puts "=" * 60
puts

# Create a fresh memory for this demo
demo_memory = RobotLab::Memory.new(network_name: "wait_demo")

# Simulate a concurrent scenario where one thread waits for another
puts "Starting writer thread (will write after 1 second)..."
puts "Starting reader thread (will wait for value)..."

reader_result = nil
writer_done = false

reader = Thread.new do
  start = Time.now
  puts "  [reader] Waiting for :delayed_result..."
  value = demo_memory.get(:delayed_result, wait: 10)
  elapsed = Time.now - start
  reader_result = value
  puts "  [reader] Got value after #{elapsed.round(2)}s: #{value}"
end

writer = Thread.new do
  sleep 1
  demo_memory.set(:delayed_result, { status: "complete", data: [1, 2, 3] })
  writer_done = true
  puts "  [writer] Wrote :delayed_result to memory"
end

# Wait for both threads
writer.join
reader.join

puts
puts "Blocking wait demonstration complete!"
puts "Reader received: #{reader_result.inspect}"
