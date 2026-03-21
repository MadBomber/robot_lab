# Observability & Safety

Three facilities that help you monitor, control, and improve robot behaviour across runs:

- **Token & Cost Tracking** — measure LLM usage per run and cumulatively
- **Tool Loop Circuit Breaker** — guard against runaway tool call loops
- **Learning Accumulation** — build up cross-run observations that guide future runs

---

## Token & Cost Tracking

### Per-Run Counts

Every `robot.run()` returns a `RobotResult` that carries the token usage for that call:

```ruby
robot = RobotLab.build(
  name: "analyst",
  system_prompt: "You are a concise technical analyst.",
  model: "claude-haiku-4-5-20251001"
)

result = robot.run("What is the difference between a stack and a queue?")

puts result.input_tokens   # tokens sent to the model this run
puts result.output_tokens  # tokens generated this run
puts result.input_tokens + result.output_tokens  # total for this call
```

Token counts are `0` for providers that do not report usage data.

### Cumulative Totals

The robot accumulates totals across all `run()` calls:

```ruby
3.times { |i| robot.run("Question #{i + 1}") }

puts robot.total_input_tokens   # sum across all three runs
puts robot.total_output_tokens
```

### Cost Estimation

Use per-provider pricing constants to estimate cost:

```ruby
HAIKU_INPUT_CPM  = 0.80   # $ per 1M input tokens
HAIKU_OUTPUT_CPM = 4.00   # $ per 1M output tokens

def run_cost(input, output)
  (input * HAIKU_INPUT_CPM + output * HAIKU_OUTPUT_CPM) / 1_000_000.0
end

result = robot.run("Explain memoization.")
puts "$#{"%.5f" % run_cost(result.input_tokens, result.output_tokens)}"
```

### Batch Accounting with reset_token_totals

`reset_token_totals` clears the accounting counters without touching the chat history. Use it to isolate the cost of a specific task batch:

```ruby
# Batch 1
prompts_batch_1.each { |p| robot.run(p) }
puts "Batch 1 cost: $#{"%.4f" % run_cost(robot.total_input_tokens, robot.total_output_tokens)}"

robot.reset_token_totals   # start fresh accounting

# Batch 2 — totals start at zero, but chat history is still intact
prompts_batch_2.each { |p| robot.run(p) }
puts "Batch 2 cost: $#{"%.4f" % run_cost(robot.total_input_tokens, robot.total_output_tokens)}"
```

> **Important:** Because the chat history keeps growing after a reset, the next run's `input_tokens` will be larger than the first batch's runs. This is expected — it is the real cost of sending the full accumulated context to the API. The counter reset tracks *accounting*, not context size.

For a truly fresh context and fresh counters, build a new robot:

```ruby
fresh = RobotLab.build(
  name: "analyst",
  system_prompt: "You are a concise technical analyst."
)
result = fresh.run("Explain memoization.")
puts result.input_tokens  # smallest possible — no prior history
```

---

## Tool Loop Circuit Breaker

### The Problem

When a tool always instructs the LLM to call it again (e.g., a step-processor returning "more steps remain"), the robot loops indefinitely. Without a guard this consumes tokens, API quota, and time without bound.

### max_tool_rounds

Set `max_tool_rounds:` on the robot to cap how many tool calls can happen in a single `run()`. When the limit is exceeded, `RobotLab::ToolLoopError` is raised.

```ruby
robot = RobotLab.build(
  name: "runner",
  system_prompt: "Execute every step sequentially.",
  local_tools: [StepTool],
  max_tool_rounds: 10
)

begin
  robot.run("Run all steps.")
rescue RobotLab::ToolLoopError => e
  puts "Circuit breaker fired: #{e.message}"
  # => "Circuit breaker fired: Tool call limit of 10 exceeded"
end
```

`max_tool_rounds` can also be supplied via `RunConfig`:

```ruby
config = RobotLab::RunConfig.new(max_tool_rounds: 10)
robot = RobotLab.build(name: "runner", system_prompt: "...", config: config)
```

### Recovering After ToolLoopError

After a `ToolLoopError` the chat contains a **dangling `tool_use` block** with no matching `tool_result`. Anthropic and most other providers will reject any subsequent request with that broken history:

```
Error: tool_use ids were found without tool_result blocks immediately after
```

Call `clear_messages` to flush the corrupted history before reusing the robot. The system prompt and all configuration (tools, `max_tool_rounds`, etc.) are preserved:

```ruby
rescue RobotLab::ToolLoopError => e
  puts "Breaker fired: #{e.message}"
end

robot.clear_messages
# Robot is healthy — config unchanged
puts robot.config.max_tool_rounds  # still 10

result = robot.run("Start fresh with a simple question.")
```

### Normal Tool Use Is Unaffected

`max_tool_rounds` is a safety net, not a tax. A robot that calls a tool once and terminates works identically with or without the guard:

```ruby
unguarded = RobotLab.build(
  name: "calculator",
  system_prompt: "Use the provided tool to answer questions.",
  local_tools: [DoubleTool]
)
result = unguarded.run("Double the number 21 using the tool.")
puts result.reply  # "The result is 42."
```

---

## Learning Accumulation

### The Problem

A robot's inherent memory persists key-value data, but there is no built-in way to tell the LLM "here is what I've learned from previous interactions." Learning accumulation fills that gap.

### robot.learn

```ruby
robot.learn(text)
```

Records `text` as an observation. On every subsequent `run()`, active learnings are automatically prepended to the user message:

```
LEARNINGS FROM PREVIOUS RUNS:
- This codebase prefers map/collect over manual array accumulation
- Explicit nil comparisons appear frequently here

<original user message>
```

This gives the LLM access to prior context without requiring a persistent conversation history.

### Bidirectional Deduplication

Learnings deduplicate bidirectionally:

- If the new text is already contained in an existing learning, it is dropped.
- If an existing learning is contained in the new text (the new one is broader), the narrower one is replaced.

```ruby
robot.learn("avoid using puts")
robot.learn("avoid using puts and p in production code")

robot.learnings.size  # => 1 — broader learning replaced the narrower one
robot.learnings.first # => "avoid using puts and p in production code"
```

### Accumulated Learnings

```ruby
robot.learnings  # => Array<String>
```

Returns the current list of active learnings in insertion order.

### Full Example

```ruby
reviewer = RobotLab.build(
  name: "reviewer",
  system_prompt: <<~PROMPT
    You are a concise Ruby code reviewer.
    Identify the main issue in one sentence and show the fix.
  PROMPT
)

snippets = [snippet_a, snippet_b, snippet_c]
insights = [
  "This codebase prefers map/collect over manual accumulation",
  "Explicit nil comparisons appear frequently",
  "Cart logic tends to have missing edge cases around nil discounts"
]

snippets.each_with_index do |code, i|
  result = reviewer.run("Review this snippet:\n\n#{code}")
  puts result.reply

  reviewer.learn(insights[i])
  puts "Added learning ##{reviewer.learnings.size}"
end
```

After all three runs, `reviewer.learnings` contains up to three insights (fewer if any are subsets of others).

### Memory Persistence

Learnings are stored in `memory[:learnings]`. They survive a robot rebuild when the same `Memory` object is passed to the new robot:

```ruby
shared_memory = original_robot.memory

rebuilt = RobotLab.build(
  name: "reviewer",
  system_prompt: "You review code."
)
rebuilt.instance_variable_set(:@memory, shared_memory)
persisted = shared_memory.get(:learnings)
rebuilt.instance_variable_set(:@learnings, Array(persisted))

puts rebuilt.learnings.size  # same as original_robot.learnings.size
```

---

## See Also

- [Robot API](../api/core/robot.md#token--cost-tracking)
- [Example 19 — Token & Cost Tracking](../../examples/19_token_tracking.rb)
- [Example 20 — Tool Loop Circuit Breaker](../../examples/20_circuit_breaker.rb)
- [Example 21 — Learning Accumulation Loop](../../examples/21_learning_loop.rb)
