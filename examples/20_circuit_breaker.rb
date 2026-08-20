#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 20: Tool Loop Circuit Breaker
#
# Demonstrates max_tool_rounds to prevent runaway tool call loops.
#
# A "process runner" robot is given a step tool whose return value always
# instructs the LLM to call it again — it would loop forever without a guard.
# The circuit breaker fires after max_tool_rounds tool calls and raises
# RobotLab::ToolLoopError.
#
# Key behaviour when the breaker fires:
#   The chat history contains a dangling tool_use with no tool_result.
#   Most providers reject any subsequent request with that
#   broken history.  You MUST call robot.clear_messages before reusing the
#   same robot instance — or simply build a fresh robot.
#
# Demonstrates:
#   - max_tool_rounds: N on RobotLab.build
#   - ToolLoopError raised when the limit is exceeded
#   - clear_messages to flush the corrupted chat and recover the robot
#   - Contrast: robot without a circuit breaker on a task that terminates
#
# Usage:
#   ruby examples/20_circuit_breaker.rb

require_relative "common"

# -------------------------------------------------------------------------
# A tool that always says "more steps remain" — designed to induce looping
# -------------------------------------------------------------------------

class MultiStepProcessor < RubyLLM::Tool
  description <<~DESC
    Executes one step of a sequential batch process.
    Returns the result of that step and whether more steps remain.
    You MUST call this tool again for each remaining step until
    the status is "complete".
  DESC

  param :step_number,
        type: "integer",
        desc: "Which step to execute. Start at 1, increment by 1 each call."

  TOTAL_STEPS = 50  # far more than any sensible max_tool_rounds

  def execute(step_number:)
    remaining = TOTAL_STEPS - step_number
    if remaining <= 0
      { status: "complete", step: step_number, message: "All steps finished." }
    else
      {
        status: "in_progress",
        step_completed: step_number,
        remaining_steps: remaining,
        instruction: "Call this tool again with step_number: #{step_number + 1}"
      }
    end
  end
end

banner "Tool Loop Circuit Breaker"

TASK = "Run the batch process from step 1 using the MultiStepProcessor tool. " \
       "Execute every step sequentially until the process reports 'complete'."

# -------------------------------------------------------------------------
# Part 1: Circuit breaker fires — rescue ToolLoopError, then recover
#
# After ToolLoopError the chat contains a dangling tool_use block with no
# matching tool_result. Providers reject any follow-up request with that
# history. Call clear_messages to flush the broken context before reuse.
# -------------------------------------------------------------------------

section "Part 1: Circuit Breaker Fires (max_tool_rounds: 5)"

robot = RobotLab.build(
  **llm_opts,
  name: "process_runner",
  system_prompt: "You are a process runner. Execute tasks exactly as instructed.",
  local_tools: [MultiStepProcessor],
  max_tool_rounds: 5
)

begin
  # tools: :inherit — run() defaults to :none, which sends the provider an
  # empty tool list. With no tool to loop on there would be nothing for the
  # breaker to trip.
  robot.run(TASK, tools: :inherit)
  puts "Process completed (unexpected for this demo)."
rescue RobotLab::ToolLoopError => e
  puts "Circuit breaker fired!"
  puts "  #{e.message}"
end

puts

# -------------------------------------------------------------------------
# Part 2: Recover by flushing the corrupted chat with clear_messages
#
# The robot retains its config (system prompt, tools, max_tool_rounds).
# Only the conversation history is cleared — the robot is then reusable.
# -------------------------------------------------------------------------

section "Part 2: Recover with clear_messages"

robot.clear_messages
puts "Chat flushed. Robot config (tools, max_tool_rounds) is unchanged."
puts "  max_tool_rounds still: #{robot.config.max_tool_rounds}"
puts

result = robot.run("What is 3 + 4? Answer in one sentence.")
puts "Follow-up after recovery: #{result.reply&.strip}"
puts

# -------------------------------------------------------------------------
# Part 3: Robot without a circuit breaker on a task that terminates quickly
#
# Normal tool use works fine with no guard — the breaker is a safety net,
# not a tax on well-behaved tool interactions.
# -------------------------------------------------------------------------

section "Part 3: No Circuit Breaker — Task Terminates Naturally"

class SingleStep < RubyLLM::Tool
  description "Doubles a number and returns the result immediately."
  param :value, type: "integer", desc: "The number to double"

  def execute(value:)
    { result: value * 2, status: "complete" }
  end
end

unguarded = RobotLab.build(
  **llm_opts,
  name: "calculator",
  system_prompt: "Use the provided tool to answer questions.",
  local_tools: [SingleStep]
)

result = unguarded.run("Double the number 21 using the tool.", tools: :inherit)
puts "Result: #{result.reply&.strip}"
puts

hr
puts "Circuit breaker demo complete."
