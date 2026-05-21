# Hook System

RobotLab's hook system lets you intercept any point in a robot's execution pipeline — before, around, or after every LLM call, tool invocation, network run, or task — without modifying core framework code. Hooks are the intended mechanism for building extensions, middleware, instrumentation, and any other cross-cutting concern. They compose safely: multiple registrations at different levels all fire in order, and each registration owns its own isolated state.

---

## Hook Families

There are five hook families. Each family has `before_*`, `around_*`, and `after_*` variants. The `:run`, `:network_run`, and `:task` families additionally have `on_error`.

| Family | Hook names | Fires during |
|--------|-----------|-------------|
| `:run` | `before_run`, `around_run`, `after_run`, `on_error` | every `robot.run(...)` call |
| `:llm_generation` | `before_llm_generation`, `around_llm_generation`, `after_llm_generation` | each LLM API call within a run (may fire multiple times when tool calls loop) |
| `:tool_call` | `before_tool_call`, `around_tool_call`, `after_tool_call` | each tool invocation |
| `:network_run` | `before_network_run`, `around_network_run`, `after_network_run`, `on_error` | every `network.run(...)` call |
| `:task` | `before_task`, `around_task`, `after_task`, `on_error` | each robot task within a network run |

Within a single `robot.run(...)` that triggers two tool calls, the firing order is:

```
before_run
  around_run {
    before_llm_generation
    around_llm_generation { [LLM call 1] }
    after_llm_generation
    before_tool_call
    around_tool_call { [tool invocation] }
    after_tool_call
    before_llm_generation
    around_llm_generation { [LLM call 2] }
    after_llm_generation
  }
after_run
```

---

## Registration Levels

Hooks are registered on three objects and can optionally be scoped to a single call:

| Level | Registration | Scope |
|-------|-------------|-------|
| **Global** | `RobotLab.on(...)` | Every robot, every network |
| **Network** | `network.on(...)` | Only robots inside that network |
| **Robot** | `robot.on(...)` | Only that robot |
| **Per-run** | `robot.run("msg", hooks: { ... })` | A single `run` call |

All four levels are additive. When a run fires, every matching registration executes in order: global → network → robot → per-run. There is no way to suppress an outer registration from an inner one.

---

## The `on` Method

All three registration objects share the same signature:

```ruby
RobotLab.on(hook_name, namespace: nil, context: nil) { |ctx| ... }
network.on(hook_name, namespace: nil, context: nil)  { |ctx| ... }
robot.on(hook_name,   namespace: nil, context: nil)  { |ctx| ... }
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `hook_name` | Symbol | One of the hook names listed in the families table above |
| `namespace:` | Symbol | Isolates this registration's state inside `ctx.local` (strongly recommended) |
| `context:` | Hash\|nil | Default state pre-populated into the namespace's `DotState` before each callback fires |

---

## Namespaces and `ctx.local`

Every registration should declare a `namespace:`. The namespace gives each extension its own isolated key-value store — a `DotState` — accessible via `ctx.local`. State set in `before_run` is visible in `around_run`, `after_run`, and `on_error` for the same run.

```ruby
robot.on(:before_run, namespace: :timer) do |ctx|
  ctx.local.start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

robot.on(:after_run, namespace: :timer) do |ctx|
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - ctx.local.start_time
  puts "run took #{elapsed.round(3)}s"
end
```

`DotState` is an open struct-like object. Keys are written and read with dot notation. Any key can be set; there is no schema.

To read another extension's state from within a hook, use `ctx.ext(:other_namespace)`:

```ruby
robot.on(:after_run, namespace: :reporter) do |ctx|
  timer_data = ctx.ext(:timer)
  puts "elapsed: #{timer_data.start_time}"
end
```

---

## The `context:` Parameter — Extension Default State

Pass `context: { key: value }` to pre-populate the namespace's `DotState` before each callback fires. Keys are only written if they are not already present, making them defaults that earlier hooks at the same level can override:

```ruby
robot.on(:before_run, namespace: :counter, context: { count: 0 }) do |ctx|
  ctx.local.count += 1
  puts "run ##{ctx.local.count}"
end
```

This is the intended pattern for extensions to declare their required state without asking callers to initialize it. Without `context:`, accessing an unset key on `DotState` returns `nil`.

---

## Around Hooks

Around hooks receive the context and a block. They must call `block.call` and must return its return value — that is how the actual LLM call, network step, or task is executed:

```ruby
robot.on(:around_run, namespace: :timer) do |ctx, &block|
  t0     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = block.call   # MUST call — this is the actual run
  elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1)
  puts "#{ctx.request.inspect} — #{elapsed}ms"
  result               # MUST return — callers expect the real result
end
```

> **Important:** If an around hook does not return the block's return value, the run returns `nil`. This is a silent failure — there is no exception.

Around hooks registered across different namespaces are chained: each wraps the next, with the actual operation at the innermost layer.

### `around_tool_call` is different

Tool call hooks use `ctx.tool_result` as the result carrier, not the block's return value. `Tool#call` always returns `context.tool_result` regardless of what the around hook returns.

To **let the tool execute normally**, call `block.call` — it sets `ctx.tool_result` — and then do any post-processing:

```ruby
RobotLab.on(:around_tool_call, namespace: :timing) do |ctx, &block|
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  block.call   # executes the tool and populates ctx.tool_result
  ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1)
  $stderr.puts "[tool] #{ctx.tool_name} — #{ms}ms"
end
```

To **short-circuit the tool** (skip execution entirely), skip `block.call` and set `ctx.tool_result` directly:

```ruby
RobotLab.on(:around_tool_call, namespace: :guard) do |ctx, &block|
  if AllowList.permitted?(ctx.tool_name, ctx.robot&.name)
    block.call
  else
    # not permitted — set result directly without calling block
    ctx.tool_result = "Operation not permitted: #{ctx.tool_name}"
  end
end
```

---

## Context Objects

Each hook family receives a typed context object. All context objects provide access to `ctx.local` (the namespace's `DotState`) and `ctx.ext(:name)` (cross-namespace reads).

### RunHookContext

Passed to `:run` hooks (`before_run`, `around_run`, `after_run`, `on_error`).

| Attribute | Type | Notes |
|-----------|------|-------|
| `event` | Symbol | `:run` |
| `robot` | Robot | The robot executing |
| `network` | Network\|nil | Present when running inside a network |
| `task` | Task\|nil | Present when running as a network task |
| `request` | String\|nil | The message passed to `run` |
| `response` | RobotResult\|nil | Set after the run completes; readable in `after_run` and `on_error` |
| `error` | Exception\|nil | Set when `on_error` fires |
| `metadata` | ExtensionState | Namespace-isolated state (backing store for `ctx.local` / `ctx.ext`) |

### LlmGenerationHookContext

Extends `RunHookContext` and is passed to `:llm_generation` hooks. All `RunHookContext` attributes are present, plus:

| Attribute | Type | Notes |
|-----------|------|-------|
| `generation_response` | RubyLLM::Message\|nil | Set after the LLM responds; readable in `after_llm_generation` |
| `iteration` | Integer | Which LLM call within this run, 0-based |

### ToolCallHookContext

Passed to `:tool_call` hooks (`before_tool_call`, `around_tool_call`, `after_tool_call`).

| Attribute | Type | Notes |
|-----------|------|-------|
| `event` | Symbol | `:tool_call` |
| `tool` | Tool | The tool instance being called |
| `tool_name` | String | |
| `tool_args` | Hash | Arguments passed to the tool |
| `tool_result` | Object\|nil | Set after the tool executes; readable in `after_tool_call` |
| `tool_error` | Exception\|nil | Set if the tool raised an exception |
| `metadata` | ExtensionState | |

### NetworkRunHookContext

Passed to `:network_run` hooks (`before_network_run`, `around_network_run`, `after_network_run`, `on_error`).

| Attribute | Type | Notes |
|-----------|------|-------|
| `event` | Symbol | `:network_run` |
| `network` | Network | |
| `context` | Hash | The run parameters |
| `result` | Object\|nil | Set after the network completes |
| `error` | Exception\|nil | Set when `on_error` fires |
| `metadata` | ExtensionState | |

### TaskHookContext

Passed to `:task` hooks (`before_task`, `around_task`, `after_task`, `on_error`).

| Attribute | Type | Notes |
|-----------|------|-------|
| `event` | Symbol | `:task` |
| `network` | Network\|nil | |
| `task` | Task | |
| `task_name` | Symbol | |
| `robot` | Robot | The robot executing this task |
| `result` | Object\|nil | Set after the task completes |
| `error` | Exception\|nil | Set when `on_error` fires |
| `metadata` | ExtensionState | |

---

## Per-Run Hooks

For one-off instrumentation tied to a single call, pass a `hooks:` hash to `robot.run`. The hash must include `namespace:` and any hook name keys mapping to a `Proc` or an array of procs:

```ruby
result = robot.run(
  "summarize this",
  hooks: {
    namespace:  :trace,
    before_run: proc { |ctx| puts "starting: #{ctx.request.inspect}" },
    after_run:  proc { |ctx| puts "done: #{ctx.response.reply}" }
  }
)
```

To register multiple callbacks for the same hook name at the per-run level, pass an array of procs:

```ruby
result = robot.run(
  "run with multiple after hooks",
  hooks: {
    namespace: :multi,
    after_run: [
      proc { |ctx| log_result(ctx.response) },
      proc { |ctx| metrics.increment("robot.run") }
    ]
  }
)
```

Per-run hooks fire after robot-level hooks, in the order supplied.

---

## Error Hooks

The `on_error` hook fires when an unhandled exception escapes a run, network run, or task. It receives the same context object as its family's `after_*` hook, with the `error` attribute set:

```ruby
robot.on(:on_error, namespace: :alerting) do |ctx|
  puts "ERROR in #{ctx.robot.name}: #{ctx.error.class} — #{ctx.error.message}"
  Alerting.notify(ctx.error, robot: ctx.robot.name, request: ctx.request)
end

network.on(:on_error, namespace: :alerting) do |ctx|
  puts "Network error: #{ctx.error.message}"
end
```

`on_error` does not suppress the exception. The error continues to propagate after all `on_error` hooks finish.

---

## Writing an Extension

The recommended pattern is a module with a class-level `attach_hooks` method. Keeping all registrations in one method makes the extension easy to attach to different registries (global, a specific network, or a specific robot) and easy to test in isolation.

```ruby
module MyExtension
  NAMESPACE = :my_ext

  class << self
    attr_writer :logger
    def logger
      @logger ||= Logger.new($stdout)
    end

    def attach_hooks(registry: RobotLab)
      registry.on(:before_run, namespace: NAMESPACE, context: { call_count: 0 }) do |ctx|
        ctx.local.call_count += 1
        logger.info("run ##{ctx.local.call_count} starting: #{ctx.request.inspect}")
      end

      registry.on(:after_run, namespace: NAMESPACE) do |ctx|
        logger.info("run done: #{ctx.response&.reply.to_s[0, 80]}")
      end

      registry.on(:on_error, namespace: NAMESPACE) do |ctx|
        logger.error("run failed: #{ctx.error.class} — #{ctx.error.message}")
      end
    end
  end
end
```

To attach globally:

```ruby
MyExtension.attach_hooks
```

To attach only to a specific network:

```ruby
MyExtension.attach_hooks(registry: network)
```

To attach only to a specific robot:

```ruby
MyExtension.attach_hooks(registry: robot)
```

### Extension Guidelines

- Always declare a `namespace:` constant so state is isolated from other extensions.
- Use `context:` to declare default state rather than guarding against `nil` inside the block.
- Around hooks (`around_run`, `around_llm_generation`, `around_network_run`, `around_task`) must call `block.call` and return its value — omitting either causes the run to return `nil`. `around_tool_call` is the exception: the result is carried in `ctx.tool_result`, so call `block.call` to let the tool run or set `ctx.tool_result` directly to short-circuit.
- Keep error hooks non-raising. Exceptions from hook callbacks propagate and can mask the original error.
- Test each hook callback in isolation by constructing a context object directly and calling the proc.

---

## Common Patterns

### Performance Timer

```ruby
RobotLab.on(:around_run, namespace: :perf) do |ctx, &block|
  t0     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = block.call
  ms     = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1)
  $stderr.puts "[perf] #{ctx.robot.name} #{ms}ms"
  result
end
```

### Request/Response Tracer

```ruby
robot.on(:before_run, namespace: :trace) do |ctx|
  puts "→ #{ctx.robot.name}: #{ctx.request.inspect}"
end

robot.on(:after_run, namespace: :trace) do |ctx|
  puts "← #{ctx.robot.name}: #{ctx.response&.reply.to_s[0, 120]}"
end
```

### LLM Response Cache

Use `around_llm_generation` to skip the LLM call entirely when a cached response exists. A `before_llm_generation` hook cannot short-circuit the call — it must be an `around_` hook:

```ruby
robot.on(:around_llm_generation, namespace: :cache, context: { hits: 0 }) do |ctx, &block|
  cached = ResponseCache.get(ctx.request)
  if cached
    ctx.local.hits += 1
    cached              # return cached value — block.call (LLM) is skipped
  else
    result = block.call # LLM call happens here
    ResponseCache.set(ctx.request, result)
    result
  end
end
```

### Tool Call Audit Log

```ruby
RobotLab.on(:before_tool_call, namespace: :audit) do |ctx|
  AuditLog.write(
    robot:     ctx.robot&.name,
    tool:      ctx.tool_name,
    args:      ctx.tool_args,
    timestamp: Time.now.utc
  )
end
```

### Run Counter Per Robot

```ruby
RobotLab.on(:before_run, namespace: :metrics, context: { counts: {} }) do |ctx|
  counts = ctx.local.counts
  name   = ctx.robot.name
  counts[name] = (counts[name] || 0) + 1
end
```

---

## Application Use Cases

Hooks are the primary extension point in RobotLab. Below are concrete patterns that production applications commonly build on top of them.

### Observability and Distributed Tracing

Instrument every LLM call with a trace ID and structured log entry for ingestion into OpenTelemetry, Datadog, or a custom logging pipeline:

```ruby
RobotLab.on(:before_run, namespace: :trace) do |ctx|
  ctx.local.trace_id   = SecureRandom.hex(8)
  ctx.local.started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

RobotLab.on(:after_run, namespace: :trace) do |ctx|
  elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - ctx.local.started_at) * 1000).round(1)
  Logger.info(
    event:      "robot.run.completed",
    trace_id:   ctx.local.trace_id,
    robot:      ctx.robot.name,
    elapsed_ms: elapsed_ms,
    reply:      ctx.response&.reply.to_s[0, 120]
  )
end

RobotLab.on(:on_error, namespace: :trace) do |ctx|
  Logger.error(
    event:    "robot.run.failed",
    trace_id: ctx.local.trace_id,
    robot:    ctx.robot.name,
    error:    ctx.error.class.to_s,
    message:  ctx.error.message
  )
end
```

### Cost Enforcement

Cap total spending across all robots in a session and raise before an expensive run would push you over budget:

```ruby
COST_PER_INPUT_TOKEN  = 0.80 / 1_000_000   # example: Haiku pricing
COST_PER_OUTPUT_TOKEN = 4.00 / 1_000_000

SESSION_BUDGET_USD = 0.50

RobotLab.on(:before_run, namespace: :budget, context: { total_cost: 0.0 }) do |ctx|
  if ctx.local.total_cost >= SESSION_BUDGET_USD
    raise RobotLab::Error, "Session budget of $#{SESSION_BUDGET_USD} exceeded"
  end
end

RobotLab.on(:after_run, namespace: :budget) do |ctx|
  r = ctx.response
  ctx.local.total_cost +=
    r.input_tokens  * COST_PER_INPUT_TOKEN +
    r.output_tokens * COST_PER_OUTPUT_TOKEN
end
```

### Tool Access Control

Allow only approved tools to execute for a given robot or network, without hard-coding restrictions in the tool itself:

```ruby
ALLOWED_TOOLS = %w[web_search calculator].freeze

network.on(:around_tool_call, namespace: :access_control) do |ctx, &block|
  if ALLOWED_TOOLS.include?(ctx.tool_name)
    block.call
  else
    ctx.tool_result = "[blocked] Tool '#{ctx.tool_name}' is not permitted in this network."
  end
end
```

### Audit Logging for Compliance

Record every tool invocation with its arguments and result for security audits or regulatory compliance:

```ruby
RobotLab.on(:after_tool_call, namespace: :audit) do |ctx|
  AuditLog.append(
    robot:     ctx.robot&.name,
    tool:      ctx.tool_name,
    args:      ctx.tool_args,
    result:    ctx.tool_result.to_s[0, 500],
    timestamp: Time.now.utc.iso8601
  )
end
```

### Retry with Exponential Backoff

Wrap `around_run` to retry on transient LLM failures without changing any robot code:

```ruby
MAX_RETRIES  = 3
BACKOFF_BASE = 0.5  # seconds

RobotLab.on(:around_run, namespace: :retry) do |ctx, &block|
  attempts = 0
  begin
    attempts += 1
    block.call
  rescue RobotLab::InferenceError => e
    raise if attempts >= MAX_RETRIES

    sleep(BACKOFF_BASE * (2**(attempts - 1)))
    retry
  end
end
```

### Test Doubles Without Network Calls

Inject canned LLM responses in tests by short-circuiting `around_llm_generation`. No VCR cassettes, no HTTP mocks:

```ruby
# In test setup:
CANNED_RESPONSES = {
  "classify this" => FakeResponse.new(content: "positive"),
  "summarize"     => FakeResponse.new(content: "short summary")
}.freeze

RobotLab.on(:around_llm_generation, namespace: :test_double) do |ctx, &block|
  canned = CANNED_RESPONSES[ctx.request]
  canned ? canned : block.call
end
```

### Per-Network Latency Metrics

Collect timing data scoped to a specific network without touching global hooks:

```ruby
network.on(:before_network_run, namespace: :metrics) do |ctx|
  ctx.local.started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

network.on(:after_network_run, namespace: :metrics) do |ctx|
  elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - ctx.local.started_at) * 1000).round(1)
  Metrics.histogram("network.run.duration_ms", elapsed_ms, tags: { network: ctx.network.name })
end
```

### Sensitive Data Redaction

Scrub PII from requests before they are logged or sent to the LLM:

```ruby
PII_PATTERN = /\b[A-Z]{2}\d{6,9}\b/  # example: passport numbers

RobotLab.on(:before_run, namespace: :redaction) do |ctx|
  ctx.request = ctx.request&.gsub(PII_PATTERN, "[REDACTED]")
end
```

---

## See Also

- [examples/35_hooks.rb](https://github.com/MadBomber/robot_lab/blob/main/examples/35_hooks.rb) — full demo with xyzzy extension, perf timer, LLM response cache, and tracer hooks
- [examples/xyzzy.rb](https://github.com/MadBomber/robot_lab/blob/main/examples/xyzzy.rb) — single-file reference extension that registers for every hook family
- [Robot Execution](../architecture/robot-execution.md)
- [Observability & Safety](observability.md)
