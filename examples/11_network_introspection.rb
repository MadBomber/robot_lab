#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 11: Network Visualization & Introspection
#
# Demonstrates network inspection and visualization without making any
# LLM calls. Covers:
#   - to_mermaid() — Mermaid diagram export
#   - to_dot()     — Graphviz DOT export
#   - execution_plan() — text execution order
#   - visualize()  — ASCII pipeline visualization
#   - robot(name) / [name] — access individual robots
#   - available_robots() — list all robots
#   - add_robot() — dynamically add a robot
#   - to_h() — network introspection hash (via amazing_print)
#   - Task-specific config (context:, depends_on:)
#   - broadcast() and on_broadcast
#
# Usage:
#   bundle exec ruby examples/11_network_introspection.rb

# Configure template path before loading
ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"
require "amazing_print"
require "tempfile"

# On macOS + iTerm2, render DOT as a PNG and display inline via imgcat.
# Returns true if the image was displayed, false otherwise.
def render_dot_image(dot_source)
  return false unless RUBY_PLATFORM.include?("darwin")

  dot_cmd  = `which dot 2>/dev/null`.chomp
  imgcat   = File.expand_path("~/.iterm2/imgcat")
  imgcat   = `which imgcat 2>/dev/null`.chomp unless File.executable?(imgcat)

  return false unless File.executable?(dot_cmd) && File.executable?(imgcat)
  return false unless ENV["TERM_PROGRAM"] == "iTerm.app"

  Tempfile.create(["pipeline", ".png"]) do |png|
    IO.popen([dot_cmd, "-Tpng", "-o", png.path], "w") { |io| io.write(dot_source) }

    if $?.success? && File.size(png.path) > 0
      system(imgcat, png.path)
      true
    else
      false
    end
  end
end

puts "=" * 70
puts "Example 11: Network Visualization & Introspection"
puts "=" * 70
puts

# Shared RunConfig for all robots in this network
shared_config = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.5)

# Per-task RunConfig override for the writer (higher creativity)
creative_config = RobotLab::RunConfig.new(temperature: 0.9)

# Build robots (no LLM calls, just instances)
classifier = RobotLab.build(name: "classifier", system_prompt: "Classify input")
analyst    = RobotLab.build(name: "analyst",    system_prompt: "Analyze data")
writer     = RobotLab.build(name: "writer",     system_prompt: "Write summary")

# Build network with RunConfig, dependencies, and per-task config
network = RobotLab.create_network(name: "demo_pipeline", run_config: shared_config) do
  task :classify, classifier, depends_on: :none
  task :analyze, analyst, context: { depth: "deep" }, depends_on: [:classify]
  task :write, writer, run_config: creative_config, depends_on: [:analyze]
end

# =============================================================================
# Section 1: Visualization outputs
# =============================================================================

puts "--- Section 1: Visualization ---"
puts

mermaid = network.to_mermaid
if mermaid
  puts "Mermaid diagram:"
  puts mermaid
  puts
end

dot = network.to_dot
if dot
  puts "Graphviz DOT:"
  puts dot
  puts

  if render_dot_image(dot)
    puts "(Rendered pipeline graph above via Graphviz + imgcat)"
    puts
  end
end

plan = network.execution_plan
if plan
  puts "Execution plan:"
  puts plan
  puts
end

ascii = network.visualize
if ascii
  puts "ASCII visualization:"
  puts ascii
  puts
end

# If none of the visualization methods returned output, note it
unless mermaid || dot || plan || ascii
  puts "(Visualization methods returned nil — depends on simple_flow version)"
  puts
end

# =============================================================================
# Section 2: Robot access
# =============================================================================

puts "--- Section 2: Robot Access ---"
puts

# Access by task name with robot() method
# Note: robots are keyed by task name (the first arg to task()), not robot.name
puts "network.robot('classify').name  = #{network.robot('classify').name.inspect}"

# Access with [] shorthand
puts "network['analyze'].name         = #{network['analyze'].name.inspect}"

# Also works with symbols
puts "network[:write].name            = #{network[:write].name.inspect}"
puts

# List all robots
puts "available_robots:"
ap network.available_robots.map(&:name)
puts

# =============================================================================
# Section 3: Dynamic robot addition
# =============================================================================

puts "--- Section 3: Dynamic Robot Addition ---"
puts

reviewer = RobotLab.build(name: "reviewer", system_prompt: "Review output")
network.add_robot(reviewer)

puts "After add_robot(reviewer):"
ap network.available_robots.map(&:name)
puts

# Attempting to add a duplicate raises an error
begin
  network.add_robot(reviewer)
rescue ArgumentError => e
  puts "Duplicate add_robot raises: #{e.message}"
end
puts

# =============================================================================
# Section 4: Network introspection
# =============================================================================

puts "--- Section 4: Network Introspection ---"
puts

puts "network.to_h:"
ap network.to_h
puts

# Individual robot introspection
puts "network['classify'].to_h:"
ap network["classify"].to_h
puts

puts "network['analyze'].to_h:"
ap network["analyze"].to_h
puts

# =============================================================================
# Section 5: RunConfig Introspection
# =============================================================================

puts "--- Section 5: RunConfig Introspection ---"
puts

puts "Network RunConfig (shared defaults):"
ap network.run_config.to_h
puts

puts "Merged effective config for :write task (network + task override):"
effective = shared_config.merge(creative_config)
ap effective.to_h
puts "  model inherited from network, temperature overridden by task"
puts

# =============================================================================
# Section 6: Broadcast
# =============================================================================

puts "--- Section 6: Broadcast ---"
puts

broadcast_messages = []

network.on_broadcast do |msg|
  broadcast_messages << msg
end

puts "Registered broadcast handler"

network.broadcast(event: :demo, message: "Hello from network!")

# Give async handler time to fire
sleep 0.1

if broadcast_messages.any?
  puts "Broadcast received:"
  ap broadcast_messages.first
else
  puts "(No broadcast received — handler may be async)"
end
puts

# =============================================================================
# Section 7: Shared memory access
# =============================================================================

puts "--- Section 7: Shared Network Memory ---"
puts

puts "network.memory is a #{network.memory.class}"
puts "network.memory.network_name = #{network.memory.network_name.inspect}"

# Robots in a network share this memory during run()
network.memory.set(:demo_key, "shared value")
puts "network.memory.get(:demo_key) = #{network.memory.get(:demo_key).inspect}"
puts

puts "network.memory.to_h:"
ap network.memory.to_h
puts

puts "=" * 70
puts "All sections completed without any LLM calls."
puts "=" * 70
