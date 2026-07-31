# Error Reference

All RobotLab exceptions inherit from `RobotLab::Error`, which inherits from `StandardError`. Rescue `RobotLab::Error` to catch any framework exception in one clause, or rescue specific subclasses for targeted handling.

## Hierarchy

```
StandardError
└── RobotLab::Error
    ├── RobotLab::ConfigurationError
    │   └── RobotLab::DependencyError
    ├── RobotLab::InferenceError
    │   └── RobotLab::ToolLoopError
    ├── RobotLab::ToolNotFoundError
    ├── RobotLab::MCPError
    ├── RobotLab::BusError
    ├── RobotLab::RactorBoundaryError
    ├── RobotLab::ToolError
    ├── RobotLab::BudgetExceeded
    └── RobotLab::AwaitTimeout
```

`AwaitTimeout` is defined in `lib/robot_lab/memory.rb` and raised by
[`Memory#get`](core/memory.md#get) when a blocking read expires.

Additionally, `DelegationFuture` defines its own scoped error:

```
StandardError
└── RobotLab::Error
    └── RobotLab::DelegationFuture::DelegationTimeout
```

---

## RobotLab::Error

Base class for all RobotLab errors. Rescue this to catch any framework exception.

```ruby
begin
  robot.run("hello")
rescue RobotLab::Error => e
  puts "RobotLab error: #{e.message}"
end
```

---

## RobotLab::ConfigurationError

Raised when configuration is invalid or missing required values.

```ruby
# Example: missing API key, invalid template path
begin
  robot.run("hello")
rescue RobotLab::ConfigurationError => e
  puts "Bad config: #{e.message}"
end
```

---

## RobotLab::DependencyError < ConfigurationError

Raised when a required optional gem dependency is not installed. There are three
distinct raise sites in core, each with its own message:

| Raised by | Missing dependency | Message |
|-----------|--------------------|---------|
| `TextAnalysis.require_classifier!` — reached from `Convergence`, `HistoryCompressor`, `Robot#compress_history`, `Robot#search_history` | `classifier` gem | `The 'classifier' gem is required for text analysis features. Add it to your Gemfile: gem 'classifier', '~> 2.3'` |
| `Memory`'s document-store methods (`store_document`, `search_documents`, `document_keys`, `delete_document`) | `robot_lab-document_store` gem | `document storage requires the robot_lab-document_store gem. Add \`gem 'robot_lab-document_store'\` to your Gemfile.` |
| `Network#run` under `parallel_mode: :ractor` | `robot_lab-ractor` gem | `parallel_mode: :ractor requires the robot_lab-ractor gem. Add \`gem 'robot_lab-ractor'\` to your Gemfile.` |

```ruby
begin
  robot.compress_history
rescue RobotLab::DependencyError => e
  warn e.message
end
```

Two places swallow it rather than propagate: `auto_compact: :context_window`
logs the message at `:warn` and skips compaction, and
`MCP::ServerDiscovery` rescues it and falls back.

---

## RobotLab::InferenceError

Raised when LLM inference fails (API errors, timeouts, rate limits).

```ruby
begin
  robot.run("hello")
rescue RobotLab::InferenceError => e
  puts "LLM call failed: #{e.message}"
end
```

---

## RobotLab::ToolLoopError < InferenceError

Raised when a robot's tool call count exceeds `max_tool_rounds:`. The chat history will contain a dangling `tool_use` block with no matching `tool_result`; call `robot.clear_messages` before reusing the robot.

```ruby
robot = RobotLab.build(
  name: "runner",
  system_prompt: "Execute every step.",
  local_tools: [StepTool],
  max_tool_rounds: 10
)

begin
  robot.run("Run all steps.", tools: :inherit)
rescue RobotLab::ToolLoopError => e
  puts e.message
  # "Circuit breaker triggered: 11 tool calls exceeded max_tool_rounds (10)"
  robot.clear_messages  # required before reuse
end
```

The message format is:

```
Circuit breaker triggered: <N> tool calls exceeded max_tool_rounds (<M>)
```

`N` is the call count that tripped the breaker (always `M + 1`); `M` is the configured limit.

---

## RobotLab::ToolNotFoundError

Raised when a tool name is referenced but cannot be found in the `ToolManifest`.

---

## RobotLab::MCPError

Raised when MCP server communication fails (connection refused, timeout, protocol error).

```ruby
begin
  robot.run("hello", mcp: :inherit, tools: :inherit)
rescue RobotLab::MCPError => e
  puts "MCP failed: #{e.message}"
end
```

`MCPError.new(message, retryable: true)` marks a specific instance as safe to retry (see [Retryable Errors](#retryable-errors) below). The connection-lost and timeout errors raised internally by `MCP::ConnectionPoller` are always constructed with `retryable: true`.

---

## RobotLab::BusError

Raised when message bus communication fails (no bus configured, channel not found).

```ruby
begin
  robot.send_message(to: :bob, content: "hi")
rescue RobotLab::BusError => e
  puts "Bus error: #{e.message}"
end
```

---

## RobotLab::RactorBoundaryError

Raised when a value cannot be made Ractor-shareable before crossing a Ractor boundary (e.g., a live `IO` object, a `Proc`, or an object with mutable state).

!!! note "The error class is core; the machinery that raises it is not"
    `RobotLab::RactorBoundaryError` is defined in core
    (`lib/robot_lab/error.rb`) so hosts can rescue it without loading anything
    extra. But `RactorBoundary`, `RactorWorkerPool`, and `RactorMemoryProxy` are
    **not defined in core** — they ship in the separate **`robot_lab-ractor`**
    gem. Core only *references* `RactorBoundary.freeze_deep` from
    `Network#build_robot_spec`, which is reachable only under
    `parallel_mode: :ractor`, which itself raises `DependencyError` unless that
    gem is loaded.

```ruby
require "robot_lab"
require "robot_lab/ractor"   # provides RactorBoundary and the worker pool

begin
  RobotLab::RactorBoundary.freeze_deep({ io: StringIO.new })
rescue RobotLab::RactorBoundaryError => e
  puts e.message
end
```

---

## RobotLab::ToolError

An opt-in error type for tool failures. Core raises it nowhere itself — you raise
it from your own `execute`, and the `robot_lab-ractor` worker pool raises it when
unwrapping a failure that happened inside a Ractor.

`ToolError.new(message, retryable: true)` marks a specific instance as retryable.

When a tool raises inside `Tool#call`, the error is caught and returned to the
LLM as text rather than propagating (unless the class sets
`self.raise_on_error = true`). RobotLab appends `" (retryable)"` whenever
`RobotLab::Errors.retryable?(error)` is true, so the model itself can see that
another attempt is worth trying:

```ruby
class Fetch < RobotLab::Tool
  description "Fetch a record"
  param :id, type: "string", desc: "record id"

  def execute(id:)
    raise RobotLab::ToolError.new("upstream unavailable", retryable: true)
  end
end

Fetch.new.call({ "id" => "1" })
# => "Error (fetch): upstream unavailable (retryable)"
```

Unlike the generic `StandardError` path, the `ToolError` path writes **nothing**
to the logger. See [Tool#call](core/tool.md#call).

---

## RobotLab::BudgetExceeded

Raised when a Robot's configured `token_budget` or `cost_budget` is already exhausted **before** an LLM call is attempted (see [Budgets](../guides/observability.md#budgets-token-cost) and `RobotLab::Budget::Ledger`). This is distinct from the pre-existing `InferenceError` "Token budget exceeded" message, which covers a call that *completed* but pushed cumulative usage over budget — `BudgetExceeded` means the call was refused outright, before any tokens were spent.

```ruby
robot = RobotLab.build(name: "capped", system_prompt: "...", cost_budget: 0.50)

begin
  robot.run("Do the expensive thing")
rescue RobotLab::BudgetExceeded => e
  puts e.message  # "budget exceeded for cost: 0.62 > 0.5"
end
```

Raised by `Budget::Ledger#reserve!`; the message format is
`"budget exceeded for <dimension>: <committed + amount> > <limit>"` where
`<dimension>` is `tokens` or `cost`.

The post-call `InferenceError` messages are formatted differently:

| Dimension | Message |
|-----------|---------|
| `token_budget` | `Token budget exceeded: <N> tokens used, budget is <M>` |
| `cost_budget` | `Cost budget exceeded: $0.523100 used, budget is $0.500000` (both values via `%.6f`) |

---

## RobotLab::AwaitTimeout

Raised by [`Memory#get`](core/memory.md#get) when a blocking read
(`wait: true` or `wait: <seconds>`) expires before the key is written.

```ruby
begin
  memory.get(:sentiment, wait: 30)
rescue RobotLab::AwaitTimeout => e
  puts e.message  # "Timeout waiting for :sentiment after 30 seconds"
end
```

With multiple keys the timeout is applied **per missing key**, so
`get(:a, :b, wait: 30)` can block for up to 60 seconds before raising.

Not retryable per `RobotLab::Errors.retryable?` — it falls into the
"everything else" bucket.

---

## Retryable Errors

`RobotLab::Errors.retryable?(error)` classifies whether a host (an ActiveJob `retry_on` list, `robot_lab-to`'s takeover loop, a custom retry wrapper) should retry the operation that raised `error`:

| Error | Retryable? |
|-------|------------|
| `InferenceError` (and subclasses, except `ToolLoopError`) | Always |
| `ToolLoopError` | Never — it's a circuit breaker; retrying immediately re-triggers the same loop |
| `MCPError` / `ToolError` | Only when raised with `retryable: true` at the raise site |
| Everything else (`ConfigurationError`, `ToolNotFoundError`, `DependencyError`, `RactorBoundaryError`, `BusError`, `BudgetExceeded`, `AwaitTimeout`, `DelegationTimeout`, non-RobotLab errors) | Never |

```ruby
begin
  robot.run(task)
rescue RobotLab::Error => e
  retry if RobotLab::Errors.retryable?(e)
  raise
end
```

`RobotLab::Errors.retryable_classes` returns `[RobotLab::InferenceError]` — an always-retryable allow-list for explicit ActiveJob-style `retry_on` declarations. It excludes `MCPError`/`ToolError` because their retryability is per-raise (via `retryable:`), not per-class.

---

## RobotLab::DelegationFuture::DelegationTimeout

Raised by `DelegationFuture#value(timeout: N)` when the delegated task does not complete within `N` seconds.

```ruby
future = manager.delegate(to: analyst, task: "...", async: true)

begin
  result = future.value(timeout: 10)
rescue RobotLab::DelegationFuture::DelegationTimeout => e
  puts e.message  # "Delegation to 'analyst' timed out after 10s"
end
```

---

## Related

- [Building Robots](../guides/building-robots.md) — Tool loop circuit breaker, delegation
- [Observability & Safety](../guides/observability.md) — circuit breaker and tool loop errors
- [MCP Integration](../guides/mcp-integration.md) — MCP connection errors
