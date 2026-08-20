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
#   ruby examples/05_streaming.rb

require_relative "common"

# Send logger output to a file instead of stdout
require 'logger'
log_file = File.join(__dir__, "05.log")
RobotLab.config.logger = Logger.new(log_file)
RubyLLM.configure { |c| c.logger = Logger.new(log_file) }

banner "Streaming Content"

# ── 1. Stored callback (on_content:) ─────────────────────────────
#
# Wire streaming at build time. The callback fires on every run() call.

section "1. Stored Callback (on_content:)"

chunks_received = 0
robot = RobotLab.build(
  **llm_opts,
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

section "2. Per-call Block"

block_chunks = 0
bare_robot = RobotLab.build(
  **llm_opts,
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

section "3. Both Together (stored fires first, then block)"

stored_log = []
block_log  = []

combo_robot = RobotLab.build(
  **llm_opts,
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

section "4. Via RunConfig (config cascade)"

config_chunks = 0
# RunConfig accepts only the fields in RunConfig::FIELDS — `provider` is not
# one of them, so it stays on the robot. on_content is a first-class config
# field and cascades normally.
config = RobotLab::RunConfig.new(
  model: LLM[:default].model,
  on_content: ->(chunk) {
    print chunk.content
    config_chunks += 1
  }
)

config_robot = RobotLab.build(
  **llm_opts,
  name: "config_bot",
  system_prompt: "You are concise. Answer in one sentence.",
  config: config
)

config_robot.run("Who designed the Ruby programming language?")

puts ""
puts "(#{config_chunks} chunks streamed via RunConfig)"
puts ""

# ── Summary ──────────────────────────────────────────────────────

section "Summary"
puts <<~SUMMARY
  on_content: callback  — wired at build time, fires every run()
  run() { |chunk| ... } — per-call streaming block
  Both together         — stored fires first, then block
  RunConfig             — on_content participates in config cascade

  For structured event streaming (lifecycle events, tool deltas,
  sequencing), see RobotLab::Streaming::Context and Events.
SUMMARY
