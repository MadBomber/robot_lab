#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 19: Per-Robot Token / Cost Tracking
#
# Demonstrates per-run and cumulative token tracking:
#   - result.input_tokens / result.output_tokens  — tokens used in that run
#   - robot.total_input_tokens / total_output_tokens — running totals on the robot
#   - robot.reset_token_totals  — reset the accounting counter (not the chat)
#
# Key distinction:
#   reset_token_totals resets the robot's *accounting counter* only.
#   The underlying chat history keeps growing, so input_tokens per run
#   naturally increase as conversation context accumulates.
#   Use a fresh robot.build when you need a genuinely fresh context.
#
# Ollama reports usage counts like the hosted providers do, so the tracking
# API behaves identically — only the price per token differs. Token counts are
# zero for providers that don't report usage data.
#
# Usage:
#   ruby examples/19_token_tracking.rb

require_relative "common"

# Cost model. A local Ollama model bills nothing, so the interesting number is
# what the same traffic WOULD have cost on a hosted model — set RATE_INPUT_CPM
# and RATE_OUTPUT_CPM to your provider's $-per-1M-token rates to see it.
# Defaults are zero: local inference is free.
RATE_INPUT_CPM  = ENV.fetch("RATE_INPUT_CPM",  "0").to_f
RATE_OUTPUT_CPM = ENV.fetch("RATE_OUTPUT_CPM", "0").to_f

def token_summary(input, output)
  "in=#{input}  out=#{output}  total=#{input + output}"
end

def run_cost(input, output)
  return "$0.00000 (local)" if RATE_INPUT_CPM.zero? && RATE_OUTPUT_CPM.zero?

  dollars = (input * RATE_INPUT_CPM + output * RATE_OUTPUT_CPM) / 1_000_000.0
  "$#{"%.5f" % dollars}"
end

def first_line(text)
  text&.strip&.lines&.first&.strip || ""
end

banner "Per-Robot Token & Cost Tracking"

puts "Model: #{LLM[:default].provider}/#{LLM[:default].model}"
if RATE_INPUT_CPM.zero? && RATE_OUTPUT_CPM.zero?
  puts "Rates: none set — local inference is free."
  puts "       Set RATE_INPUT_CPM / RATE_OUTPUT_CPM to price the same traffic"
  puts "       against a hosted provider."
else
  puts "Rates: $#{RATE_INPUT_CPM}/1M in, $#{RATE_OUTPUT_CPM}/1M out"
end
puts

robot = RobotLab.build(
  **llm_opts,
  name: "analyst",
  system_prompt: "You are a concise technical analyst. Keep every reply under 40 words."
)

prompts = [
  "What is the difference between a stack and a queue?",
  "Name three Ruby gems that every Rails project should consider.",
  "Why does database indexing improve query performance?"
]

puts "Running #{prompts.size} prompts...\n\n"

prompts.each_with_index do |prompt, i|
  result = robot.run(prompt)

  puts "Run #{i + 1}: #{prompt}"
  puts "  Reply:      #{first_line(result.reply)}"
  puts "  This run:   #{token_summary(result.input_tokens, result.output_tokens)}"
  puts "  Cost:       #{run_cost(result.input_tokens, result.output_tokens)}"
  puts "  Cumulative: #{token_summary(robot.total_input_tokens, robot.total_output_tokens)}"
  puts
end

hr
puts "After #{prompts.size} runs:"
puts "  Total tokens: #{token_summary(robot.total_input_tokens, robot.total_output_tokens)}"
puts "  Total cost:   #{run_cost(robot.total_input_tokens, robot.total_output_tokens)}"
puts

# ---------------------------------------------------------------
# reset_token_totals: resets the accounting counter only.
# Useful when you want to measure cost for a specific task batch
# while keeping the robot alive for the next batch.
#
# Note: input_tokens will still reflect the full chat history sent
# to the API — that's the real cost, not an error.
# ---------------------------------------------------------------

puts "Resetting token totals (batch 1 complete, starting batch 2)..."
robot.reset_token_totals
puts "  Counter now:  #{token_summary(robot.total_input_tokens, robot.total_output_tokens)}"
puts
puts "  Note: the next run's input_tokens will be larger than run 1's"
puts "  because the LLM receives the full accumulated chat context."
puts "  The counter reset tracks *accounting* — it doesn't clear the chat."
puts

result = robot.run("What is memoization?")
puts "Batch 2 — Run 1: What is memoization?"
puts "  Reply:      #{first_line(result.reply)}"
puts "  This run:   #{token_summary(result.input_tokens, result.output_tokens)}"
puts "  Batch total: #{token_summary(robot.total_input_tokens, robot.total_output_tokens)}"
puts

# ---------------------------------------------------------------
# To start truly fresh (new context, new counter), build a new robot.
# ---------------------------------------------------------------

hr
puts "Fresh robot — genuinely zero context:"
puts

fresh = RobotLab.build(
  **llm_opts,
  name: "analyst2",
  system_prompt: "You are a concise technical analyst. Keep every reply under 40 words."
)

result = fresh.run("What is memoization?")
puts "Run 1 (fresh robot): What is memoization?"
puts "  Reply:      #{first_line(result.reply)}"
puts "  This run:   #{token_summary(result.input_tokens, result.output_tokens)}"
puts "  Cumulative: #{token_summary(fresh.total_input_tokens, fresh.total_output_tokens)}"
puts

hr
puts "Token tracking demo complete."
