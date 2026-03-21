# Observability & Safety

Facilities that help you monitor, control, improve, and scale robot behaviour:

- **Token & Cost Tracking** — measure LLM usage per run and cumulatively
- **Tool Loop Circuit Breaker** — guard against runaway tool call loops
- **Learning Accumulation** — build up cross-run observations that guide future runs
- **Context Window Compression** — prune irrelevant history to stay within token budgets
- **Convergence Detection** — detect when independent agents reach the same conclusion
- **Structured Delegation** — synchronous inter-robot calls with duration and token metadata

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

## Context Window Compression

### The Problem

Long conversations accumulate turns that are no longer relevant to the current topic. Sending all of them to the LLM on every `run()` wastes tokens and money, and risks exceeding the model's context window.

### robot.compress_history

```ruby
robot.compress_history(
  recent_turns:    3,      # last N user+assistant pairs — always protected
  keep_threshold:  0.6,    # score >= this → keep verbatim
  drop_threshold:  0.2,    # score < this  → drop
  summarizer:      nil     # optional lambda(text) -> String for medium tier
)
```

Internally, each old turn is scored against the mean of the recent turns using stemmed term-frequency cosine similarity (via the `classifier` gem). Turns that score high are kept; turns that score low are dropped; turns in the middle band are either summarized or dropped depending on whether a `summarizer` is provided.

**Always preserved regardless of score:**

- System messages
- Tool call/result message pairs
- All messages within the `recent_turns` window

### Thresholds

```
score >= keep_threshold   →  keep verbatim
score <  drop_threshold   →  drop
otherwise                 →  summarize (if summarizer given) or drop
```

A good starting point: `keep_threshold: 0.6, drop_threshold: 0.2`. Widen the drop band (raise `drop_threshold`) to compress more aggressively; raise `keep_threshold` to summarize more.

### Without a Summarizer (Drop Mode)

```ruby
robot.compress_history(recent_turns: 3, keep_threshold: 0.6, drop_threshold: 0.2)
```

Medium-relevance turns are dropped along with low-relevance ones. This is the simplest form — no extra LLM calls, no added latency.

### With an LLM Summarizer

```ruby
summarizer_bot = RobotLab.build(
  name:          "summarizer",
  system_prompt: "Summarize the following text in one sentence."
)

robot.compress_history(
  recent_turns:    3,
  keep_threshold:  0.6,
  drop_threshold:  0.2,
  summarizer:      ->(text) { summarizer_bot.run("Summarize: #{text}").reply }
)
```

The summarizer replaces each medium-relevance turn with a one-sentence digest, preserving some context while reducing token count. The summary inherits the **original message's role** so the user/assistant alternation required by LLM APIs is maintained.

### Optional Dependency

`compress_history` requires the `classifier` gem. Add it to your Gemfile:

```ruby
gem "classifier", "~> 2.3"
```

Without it, calling `compress_history` raises `RobotLab::DependencyError` with an install hint.

---

## Convergence Detection

### The Problem

Multi-robot verification patterns (two independent reviewers, a debate network, a fact-checker) typically ask a reconciler robot to resolve any differences. But when both verifiers already agree, paying for that reconciler call is pure waste.

### RobotLab::Convergence

```ruby
score = RobotLab::Convergence.similarity(text_a, text_b)  # Float 0.0..1.0
agreed = RobotLab::Convergence.detected?(text_a, text_b)  # Boolean (threshold: 0.85)
agreed = RobotLab::Convergence.detected?(text_a, text_b, threshold: 0.6)
```

Similarity is computed via L2-normalized stemmed term-frequency cosine similarity. Term frequencies (not TF-IDF) are used because fitting TF-IDF on a 2-document corpus suppresses shared terms to near-zero IDF, giving counter-intuitively low scores for texts that agree on the same topic.

Texts shorter than 30 characters always return `0.0`.

### Typical Scores

| Relationship | Typical Score |
|---|---|
| Identical | 1.000 |
| Same conclusion, different phrasing | 0.60 – 0.75 |
| Same topic, different emphasis | 0.45 – 0.60 |
| Unrelated | < 0.15 |

### Router Fast-Path Pattern

Skip the reconciler when verifiers agree:

```ruby
router = ->(args) do
  a = args.context[:verifier_a]&.reply.to_s
  b = args.context[:verifier_b]&.reply.to_s

  if RobotLab::Convergence.detected?(a, b)
    nil                  # both agree — network halts, no reconciler call
  else
    ["reconciler"]       # diverged — send to reconciler
  end
end

network = RobotLab.create_network(
  name:   "fact_check",
  robots: [verifier_a, verifier_b, reconciler],
  router: router
)
```

Tune `threshold:` to control how strictly "agreement" is defined. A lower threshold (e.g., `0.6`) accepts more variation between verifiers; a higher threshold (e.g., `0.9`) only fast-paths near-identical responses.

### Optional Dependency

`RobotLab::Convergence` requires the `classifier` gem (same as `compress_history`):

```ruby
gem "classifier", "~> 2.3"
```

---

---

## Structured Delegation

### The Problem

RobotLab has two existing patterns for one robot to involve another:

- **Pipelines** — predefined sequences where robots share memory and run in order
- **Bus messaging** — fire-and-forget pub/sub with no return value

Neither gives you a synchronous call that returns a result with provenance and cost metadata. `delegate` fills that gap.

### Synchronous delegation

Blocks until the delegatee finishes and returns a `RobotResult` annotated with provenance and timing:

```ruby
result = manager.delegate(to: specialist, task: "Analyze this data: ...")

puts result.reply          # specialist's answer
puts result.robot_name     # => "specialist"   (who did the work)
puts result.delegated_by   # => "manager"      (who asked)
puts result.duration       # => 1.43           (wall-clock seconds)
puts result.input_tokens   # => 812
puts result.output_tokens  # => 94
```

All keyword arguments are forwarded to the delegatee's `run()`:

```ruby
result = manager.delegate(to: worker, task: "hello", company_name: "Acme")
```

### Asynchronous delegation — parallel fan-out

Pass `async: true` to get a `DelegationFuture` back immediately. The delegatee runs in a background thread. Call `future.value` to block for the result, or `future.resolved?` to poll without blocking.

```ruby
# Fire both delegations simultaneously
f1 = manager.delegate(to: summarizer, task: "Summarize: #{doc}", async: true)
f2 = manager.delegate(to: analyst,    task: "Key metric: #{doc}", async: true)

# Both are running in parallel here
puts f1.resolved?   # false (probably)

# Collect when ready (optional timeout in seconds)
summary  = f1.value(timeout: 30)
analysis = f2.value(timeout: 30)
```

If the delegatee raises an error, `future.value` re-raises it. If `timeout:` expires before the result arrives, `DelegationFuture::DelegationTimeout` is raised.

### When to Use Each Pattern

| Pattern | Return value | Concurrent | Use when |
|---|---|---|---|
| `pipeline` | shared memory | yes (parallel groups) | fixed workflow graph |
| `bus` messaging | none (fire-and-forget) | yes | notify without waiting for a reply |
| `delegate` | `RobotResult` with metadata | no | need the result back, one at a time |
| `delegate(async: true)` | `DelegationFuture` | yes | parallel fan-out, collect results later |

### Full Example

```ruby
manager    = RobotLab.build(name: "manager",    system_prompt: "You are a project manager.")
summarizer = RobotLab.build(name: "summarizer", system_prompt: "Summarize in 1-2 sentences.")
analyst    = RobotLab.build(name: "analyst",    system_prompt: "Identify the key metric.")

# Parallel fan-out
f1 = manager.delegate(to: summarizer, task: "Summarize: #{document}", async: true)
f2 = manager.delegate(to: analyst,    task: "Key metric: #{document}", async: true)

summary  = f1.value(timeout: 60)
analysis = f2.value(timeout: 60)

puts "#{summary.robot_name} (#{summary.duration.round(2)}s): #{summary.reply}"
puts "#{analysis.robot_name} (#{analysis.duration.round(2)}s): #{analysis.reply}"
```

---

## See Also

- [Robot API](../api/core/robot.md#token--cost-tracking)
- [Example 19 — Token & Cost Tracking](../../examples/19_token_tracking.rb)
- [Example 20 — Tool Loop Circuit Breaker](../../examples/20_circuit_breaker.rb)
- [Example 21 — Learning Accumulation Loop](../../examples/21_learning_loop.rb)
- [Example 22 — Context Window Compression](../../examples/22_context_compression.rb)
- [Example 23 — Convergence Detection](../../examples/23_convergence.rb)
- [Example 24 — Structured Delegation](../../examples/24_structured_delegation.rb)
