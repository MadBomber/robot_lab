#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 5: Streaming Content
#
# Demonstrates real-time streaming of LLM responses using:
#   1. Stored callback (on_content:) — wired at build time
#   2. Per-call block — passed to run()
#   3. Both together — stored fires first, then block
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/05_streaming.rb

# Configure template path before loading (MywayConfig reads env vars on init)
ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

# Send logger output to a file instead of stdout
require 'logger'
log_file = File.join(__dir__, "05.log")
RobotLab.config.logger = Logger.new(log_file)
RubyLLM.configure { |c| c.logger = Logger.new(log_file) }

puts "Streaming Content Example"
puts "=" * 50
puts ""

# ── 1. Stored callback (on_content:) ─────────────────────────────
#
# Wire streaming at build time. The callback fires on every run() call.

puts "1. Stored callback (on_content:)"
puts "-" * 50

chunks_received = 0
robot = RobotLab.build(
  name: "storyteller",
  system_prompt: "You are a concise storyteller. Keep responses under 3 sentences.",
  on_content: ->(chunk) {
    print chunk.content
    chunks_received += 1
  }
)

result = robot.run("Tell me a one-sentence fact about Ruby programming.")

puts ""
puts "(#{chunks_received} chunks streamed)"
puts ""

# ── 2. Per-call block ────────────────────────────────────────────
#
# Pass a block to run() for one-off streaming.

puts "2. Per-call block"
puts "-" * 50

block_chunks = 0
bare_robot = RobotLab.build(
  name: "factbot",
  system_prompt: "You are concise. Answer in one sentence."
)

bare_robot.run("What year was Ruby created?") { |chunk|
  print chunk.content
  block_chunks += 1
}

puts ""
puts "(#{block_chunks} chunks streamed)"
puts ""

# ── 3. Both together ────────────────────────────────────────────
#
# When both exist, both fire: stored callback first, then block.

puts "3. Both together (stored fires first, then block)"
puts "-" * 50

stored_log = []
block_log  = []

combo_robot = RobotLab.build(
  name: "combo",
  system_prompt: "You are concise. Answer in one sentence.",
  on_content: ->(chunk) { stored_log << chunk.content }
)

combo_robot.run("What is Matz's full name?") { |chunk|
  block_log << chunk.content
  print chunk.content
}

puts ""
puts "(stored callback saw #{stored_log.length} chunks, block saw #{block_log.length} chunks)"
puts "Callbacks fired in sync: #{stored_log == block_log}"
puts ""

# ── 4. Via RunConfig ─────────────────────────────────────────────
#
# on_content participates in the config cascade.

puts "4. Via RunConfig (config cascade)"
puts "-" * 50

config_chunks = 0
config = RobotLab::RunConfig.new(
  on_content: ->(chunk) {
    print chunk.content
    config_chunks += 1
  }
)

config_robot = RobotLab.build(
  name: "config_bot",
  system_prompt: "You are concise. Answer in one sentence.",
  config: config
)

config_robot.run("Who designed the Ruby programming language?")

puts ""
puts "(#{config_chunks} chunks streamed via RunConfig)"
puts ""

# ── Summary ──────────────────────────────────────────────────────

puts "=" * 50
puts "Summary"
puts ""
puts <<~SUMMARY
  on_content: callback  — wired at build time, fires every run()
  run() { |chunk| ... } — per-call streaming block
  Both together         — stored fires first, then block
  RunConfig             — on_content participates in config cascade

  For structured event streaming (lifecycle events, tool deltas,
  sequencing), see RobotLab::Streaming::Context and Events.
SUMMARY
