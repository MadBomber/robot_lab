#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 24: Structured Delegation
#
# Demonstrates robot.delegate(to:, task:) for structured inter-robot calls,
# in both synchronous (blocking) and asynchronous (parallel fan-out) modes.
#
# Demonstrates:
#   - robot.delegate(to:, task:)              — sync: blocks, returns RobotResult
#   - robot.delegate(to:, task:, async: true) — async: returns DelegationFuture
#   - future.value / future.value(timeout: N) — block until result ready
#   - future.resolved?                        — non-blocking poll
#   - result.delegated_by — which robot delegated
#   - result.robot_name   — which robot did the work
#   - result.duration     — wall-clock seconds for the delegated call
#   - result.input_tokens / result.output_tokens — delegatee's token usage
#   - Contrast with bus messaging (fire-and-forget) and pipelines (predefined)
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/24_structured_delegation.rb

require_relative "common"

banner "Structured Delegation"

# ---------------------------------------------------------------------------
# Build a manager and two specialist robots
# ---------------------------------------------------------------------------
manager = RobotLab.build(
  model: LLM[:default].model,
  name:          "manager",
  system_prompt: "You are a project manager. Delegate tasks concisely."
)

summarizer = RobotLab.build(
  model: LLM[:default].model,
  name:          "summarizer",
  system_prompt: "You are a concise summarizer. Produce a 1-2 sentence summary."
)

analyst = RobotLab.build(
  model: LLM[:default].model,
  name:          "analyst",
  system_prompt: "You are a data analyst. Identify the key metric in one sentence."
)

# ---------------------------------------------------------------------------
# Manager delegates to each specialist in turn
# ---------------------------------------------------------------------------
document = <<~TEXT
  Q4 revenue came in at $4.2M, up 18% year-over-year. Customer acquisition
  cost dropped to $120, the lowest in three years. Churn held steady at 2.1%.
  Net promoter score improved from 42 to 58. The mobile app drove 34% of new
  sign-ups, compared to 19% in Q3.
TEXT

puts "Document:"
puts document
hr

# ---------------------------------------------------------------------------
# Synchronous delegation — sequential, blocks until each result arrives
# ---------------------------------------------------------------------------
section "Synchronous (sequential)"

puts "Delegating to summarizer (blocking)..."
summary_result = manager.delegate(to: summarizer, task: "Summarize this report:\n\n#{document}")

puts "Summary (from #{summary_result.robot_name}, delegated by #{summary_result.delegated_by}):"
puts "  #{summary_result.reply}"
puts "  Duration: #{"%.2f" % summary_result.duration}s | " \
     "Tokens: #{summary_result.input_tokens} in / #{summary_result.output_tokens} out"
puts

puts "Delegating to analyst (blocking)..."
analysis_result = manager.delegate(to: analyst, task: "What is the single most important metric here?\n\n#{document}")

puts "Analysis (from #{analysis_result.robot_name}, delegated by #{analysis_result.delegated_by}):"
puts "  #{analysis_result.reply}"
puts "  Duration: #{"%.2f" % analysis_result.duration}s | " \
     "Tokens: #{analysis_result.input_tokens} in / #{analysis_result.output_tokens} out"
puts

# ---------------------------------------------------------------------------
# Asynchronous delegation — parallel fan-out, results collected later
# ---------------------------------------------------------------------------
section "Asynchronous (parallel fan-out)"

# Fresh robots — each delegate call should start from a clean slate
async_summarizer = RobotLab.build(
  model: LLM[:default].model,
  name:          "summarizer",
  system_prompt: "You are a concise summarizer. Produce a 1-2 sentence summary."
)
async_analyst = RobotLab.build(
  model: LLM[:default].model,
  name:          "analyst",
  system_prompt: "You are a data analyst. Identify the key metric in one sentence."
)

puts "Firing both delegations in parallel..."
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

f_summary  = manager.delegate(to: async_summarizer, task: "Summarize this report:\n\n#{document}",                     async: true)
f_analysis = manager.delegate(to: async_analyst,    task: "What is the single most important metric?\n\n#{document}", async: true)

puts "Both futures launched. Futures resolved? " \
     "summary=#{f_summary.resolved?} analysis=#{f_analysis.resolved?}"
puts "Collecting results..."

summary  = f_summary.value(timeout: 60)
analysis = f_analysis.value(timeout: 60)

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

puts
puts "Summary  (#{summary.robot_name}):  #{summary.reply}"
puts "Analysis (#{analysis.robot_name}): #{analysis.reply}"
puts
puts "Total wall time with parallelism: #{"%.2f" % elapsed}s " \
     "(vs ~#{"%.2f" % (summary.duration + analysis.duration)}s sequential)"
puts

# ---------------------------------------------------------------------------
# Contrast with the alternatives
# ---------------------------------------------------------------------------
section "When to Use delegate vs. the Alternatives"
puts <<~TEXT

  bus messaging       — fire-and-forget; no return value; async
                        use when: you want to notify without waiting

  pipeline            — predefined sequence; robots share memory
                        use when: you have a fixed workflow graph

  delegate()          — synchronous; blocks; returns RobotResult with metadata
                        use when: one robot needs the result of another's work

  delegate(async:true) — returns DelegationFuture immediately
                         use when: you want to run multiple delegates in
                         parallel and collect results when ready

TEXT

puts "Done."
