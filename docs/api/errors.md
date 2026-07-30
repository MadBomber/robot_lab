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
    └── RobotLab::BudgetExceeded
```

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
rescue RobotLab::ConfigurationError => e
  puts "Bad config: #{e.message}"
end
```

---

## RobotLab::DependencyError < ConfigurationError

Raised when a required optional gem dependency is not installed.

```ruby
# Triggered by: Convergence, HistoryCompressor when 'classifier' gem is absent
rescue RobotLab::DependencyError => e
  puts e.message  # "Add gem 'classifier', '~> 2.3' to your Gemfile"
end
```

---

## RobotLab::InferenceError

Raised when LLM inference fails (API errors, timeouts, rate limits).

```ruby
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
  robot.run("Run all steps.")
rescue RobotLab::ToolLoopError => e
  puts e.message  # "Tool call limit of 10 exceeded"
  robot.clear_messages  # required before reuse
end
```

---

## RobotLab::ToolNotFoundError

Raised when a tool name is referenced but cannot be found in the `ToolManifest`.

---

## RobotLab::MCPError

Raised when MCP server communication fails (connection refused, timeout, protocol error).

```ruby
rescue RobotLab::MCPError => e
  puts "MCP failed: #{e.message}"
end
```

`MCPError.new(message, retryable: true)` marks a specific instance as safe to retry (see [Retryable Errors](#retryable-errors) below). The connection-lost and timeout errors raised internally by `MCP::ConnectionPoller` are always constructed with `retryable: true`.

---

## RobotLab::BusError

Raised when message bus communication fails (no bus configured, channel not found).

```ruby
rescue RobotLab::BusError => e
  puts "Bus error: #{e.message}"
end
```

---

## RobotLab::RactorBoundaryError

Raised when a value cannot be made Ractor-shareable before crossing a Ractor boundary (e.g., a live `IO` object, a `Proc`, or an object with mutable state).

```ruby
begin
  RobotLab::RactorBoundary.freeze_deep({ io: StringIO.new })
rescue RobotLab::RactorBoundaryError => e
  puts e.message  # "Cannot make value Ractor-shareable: ..."
end
```

Raised proactively by `RactorWorkerPool#submit` and `RactorMemoryProxy#set` before any Ractor is involved.

---

## RobotLab::ToolError

Raised when a tool fails during execution inside a Ractor worker (the pool unwraps `RactorJobError` and re-raises as `ToolError`).

```ruby
begin
  pool.submit("MyTool", { input: "bad" })
rescue RobotLab::ToolError => e
  puts e.message  # "Tool 'MyTool' failed in Ractor: ..."
end
```

Like `MCPError`, `ToolError.new(message, retryable: true)` marks a specific instance as retryable. When a tool raises inside `Tool#call`, RobotLab appends `" (retryable)"` to the formatted error text returned to the LLM whenever `RobotLab::Errors.retryable?(error)` is true, so the model itself can see that another attempt is worth trying.

---

## RobotLab::BudgetExceeded

Raised when a Robot's configured `token_budget` or `cost_budget` is already exhausted **before** an LLM call is attempted (see [Budgets](../guides/observability.md#budgets-token--cost) and `RobotLab::Budget::Ledger`). This is distinct from the pre-existing `InferenceError` "Token budget exceeded" message, which covers a call that *completed* but pushed cumulative usage over budget — `BudgetExceeded` means the call was refused outright, before any tokens were spent.

```ruby
robot = RobotLab.build(name: "capped", system_prompt: "...", cost_budget: 0.50)

begin
  robot.run("Do the expensive thing")
rescue RobotLab::BudgetExceeded => e
  puts e.message  # "budget exceeded for cost: 0.62 > 0.5"
end
```

---

## Retryable Errors

`RobotLab::Errors.retryable?(error)` classifies whether a host (an ActiveJob `retry_on` list, `robot_lab-to`'s takeover loop, a custom retry wrapper) should retry the operation that raised `error`:

| Error | Retryable? |
|-------|------------|
| `InferenceError` (and subclasses, except `ToolLoopError`) | Always |
| `ToolLoopError` | Never — it's a circuit breaker; retrying immediately re-triggers the same loop |
| `MCPError` / `ToolError` | Only when raised with `retryable: true` at the raise site |
| Everything else (`ConfigurationError`, `ToolNotFoundError`, `DependencyError`, `RactorBoundaryError`, `BusError`, `BudgetExceeded`, non-RobotLab errors) | Never |

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
