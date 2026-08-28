# Hook System

RobotLab's hook system lets you intercept any point in a robot's execution pipeline — before, around, or after every LLM call, tool invocation, network run, or task — without modifying core framework code. Hooks are implemented as handler classes: subclasses of `RobotLab::Hook` that define lifecycle callbacks as class methods. Hooks are the intended mechanism for building extensions, middleware, instrumentation, and any other cross-cutting concern. They compose safely: multiple registrations at different levels all fire in order, and each handler class owns its own isolated state.

---

## Hook Families

There are seven hook families. Each family has `before_*`, `around_*`, and `after_*` variants. The `:run`, `:network_run`, and `:task` families additionally have `on_error`. The `:compaction` and `:learn` families additionally have point hooks (`on_compaction` and `on_learn`) that allow extensions to replace or augment the core behaviour.

| Family | Hook names | Fires during |
|--------|-----------|-------------|
| `:run` | `before_run`, `around_run`, `after_run`, `on_error` | every `robot.run(...)` call |
| `:llm_generation` | `before_llm_generation`, `around_llm_generation`, `after_llm_generation` | exactly once per `robot.run(...)` — it wraps the whole generation phase, including the provider's tool loop |
| `:tool_call` | `before_tool_call`, `around_tool_call`, `after_tool_call` | each tool invocation |
| `:network_run` | `before_network_run`, `around_network_run`, `after_network_run`, `on_error` | every `network.run(...)` call |
| `:task` | `before_task`, `around_task`, `after_task`, `on_error` | each robot task within a network run |
| `:compaction` | `before_compaction`, `around_compaction`, `after_compaction`, `on_compaction` | when conversation history is about to be compressed |
| `:learn` | `before_learn`, `around_learn`, `after_learn`, `on_learn` | every `robot.learn(text)` call that carries non-empty text |

Within a single `robot.run(...)` that triggers two tool calls and one compaction, the firing order is:

```
before_run
  around_run {
    before_llm_generation
    around_llm_generation {
      before_compaction
      around_compaction {
        on_compaction          # only fires if a handler is registered
        [compress history]
      }
      after_compaction
      [LLM call 1]
      before_tool_call
      around_tool_call { [tool invocation 1] }
      after_tool_call
      [LLM call 2]
      before_tool_call
      around_tool_call { [tool invocation 2] }
      after_tool_call
      [LLM call 3]
    }
    after_llm_generation
  }
after_run
```

> [!IMPORTANT]
> The `:llm_generation` family fires **once per `run`**, not once per LLM API
> call. The provider's tool loop — every LLM round trip and every tool call —
> happens *inside* the `around_llm_generation` block. Tool hooks therefore fire
> nested within it, never between two `llm_generation` cycles. If you need
> per-API-call instrumentation, `:tool_call` hooks are the only per-round signal
> the hook system exposes.

Compaction hooks fire at most once per `run` — they live inside the same single `llm_generation` block — and only when the compaction threshold is actually exceeded (or a custom `Proc` strategy is configured). They do not fire on every `run` invocation.

The `:learn` family fires synchronously inside `robot.learn(text)`, once per call. Hooks do not fire when `text` is blank.

---

## Handler Classes

All hook logic is implemented as a subclass of `RobotLab::Hook`. Lifecycle callbacks are defined as `class << self` methods — one method per hook name. Any method that is not defined is silently skipped when that hook fires.

```ruby
class MyHook < RobotLab::Hook
  class << self
    def before_run(ctx)
      # fires before every robot.run call
    end

    def after_run(ctx)
      # fires after every robot.run call
    end

    def on_error(ctx)
      # fires when an unhandled exception escapes a run
    end
  end
end
```

### Namespace auto-derivation

Every handler class has a namespace that isolates its `ctx.local` state from other handlers. The namespace is derived automatically from the class name by snake_casing the final segment:

| Class name | Auto namespace |
|-----------|---------------|
| `TimerHook` | `:timer_hook` |
| `AuditHook` | `:audit_hook` |
| `PerfMonitor` | `:perf_monitor` |
| `MyExt::Tracer` | `:tracer` |

Override the auto-derived namespace at the class level:

```ruby
class TimerHook < RobotLab::Hook
  self.namespace = :timer   # use :timer instead of :timer_hook
end
```

### `RobotLab::Hook` base class

```ruby
class Hook
  class << self
    attr_writer :namespace

    def namespace
      return @namespace if @namespace
      return nil if self == Hook
      name.split('::').last
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase.to_sym
    end

    def call(hook_name, context, &block)
      if singleton_class.public_method_defined?(hook_name)
        block ? public_send(hook_name, context, &block) : public_send(hook_name, context)
      elsif block
        block.call
      end
    end
  end
end
```

---

## Registration Levels

Hooks are registered on three objects and can optionally be scoped to a single call:

| Level | Registration | Scope |
|-------|-------------|-------|
| **Global** | `RobotLab.on(...)` | Every robot, every network |
| **Network** | `network.on(...)` | Only robots inside that network |
| **Robot** | `robot.on(...)` | Only that robot |
| **Per-run** | `robot.run("msg", hooks: ...)` | A single `run` call |

All four levels are additive. When a run fires, every matching registration executes in order: global → network → robot → per-run. There is no way to suppress an outer registration from an inner one.

> [!WARNING]
> The **`:task` family is the exception.** `Task#call` resolves its handlers from
> `[RobotLab.hooks, network.hooks]` only — the robot's own registry is not
> consulted. A `before_task`/`around_task`/`after_task`/`on_error` handler
> registered with `robot.on(...)` (or per-run `hooks:`) **never fires**. Register
> task hooks globally or on the network.
>
> The `:network_run` family likewise reads `[RobotLab.hooks, network.hooks]`,
> which is the same set it would see anyway since networks have no robot scope.

---

## The `on` Method

All three registration objects share the same signature:

```ruby
RobotLab.on(handler_class, context: nil)
network.on(handler_class, context: nil)
robot.on(handler_class,   context: nil)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `handler_class` | Class | A subclass of `RobotLab::Hook` |
| `context:` | Hash\|nil | Default state pre-populated into the handler's namespace `DotState` before each callback fires |

`handler_class` must be a subclass of `RobotLab::Hook`. The namespace is read from `handler_class.namespace` — there is no `namespace:` parameter on `on`.

---

## Namespaces and `ctx.local`

Each handler class's namespace gives it an isolated key-value store — a `DotState` — accessible via `ctx.local`. State set in `before_run` is visible in `around_run`, `after_run`, and `on_error` for the same run, and in the `:llm_generation`, `:tool_call`, and `:compaction` contexts nested inside it.

> [!WARNING]
> **`ctx.local` lives for exactly one run.** Its backing store is a fresh
> `ExtensionState` created with each `HookContext`, so the next `robot.run` starts
> from an empty slate (or from whatever `context:` defaults you declared).
> `ctx.local` is a scratchpad for correlating the phases of a single run — it is
> **not** a place to accumulate counters, totals, or caches across runs. For
> cross-run state, use a class-level `attr_accessor` on the handler itself, or an
> external store.

```ruby
class TimerHook < RobotLab::Hook
  self.namespace = :timer

  def self.before_run(ctx)
    ctx.local.start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.after_run(ctx)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - ctx.local.start_time
    puts "run took #{elapsed.round(3)}s"
  end
end
```

`DotState` is an open struct-like object. Keys are written and read with dot notation. Any key can be set; there is no schema.

To read another handler's state from within a hook, use `ctx.ext(:other_namespace)`:

```ruby
class ReporterHook < RobotLab::Hook
  self.namespace = :reporter

  def self.after_run(ctx)
    timer_data = ctx.ext(:timer)
    puts "elapsed since start: #{timer_data.start_time}"
  end
end
```

---

## The `context:` Parameter — Default State

Pass `context: { key: value }` to pre-populate the handler's namespace `DotState` before each callback fires. Keys are only written if they are not already present, making them defaults that earlier hooks in the same run can override:

```ruby
class TagHook < RobotLab::Hook
  self.namespace = :tagging

  def self.before_run(ctx)
    # ctx.local.environment is pre-populated from context:, so no nil guard needed
    puts "[#{ctx.local.environment}] #{ctx.robot.name}: #{ctx.request.inspect}"
  end
end

RobotLab.on(TagHook, context: { environment: "staging" })
```

This is the intended pattern for extensions to declare their required state without asking callers to initialize it. Without `context:`, accessing an unset key on `DotState` returns `nil`.

Because `ctx.local` is re-created per run, the defaults are re-applied on *every* run — a `context: { count: 0 }` default means `ctx.local.count` is `0` at the start of each run, not a counter that survives. Keep cross-run tallies on the handler class:

```ruby
class RunCounter < RobotLab::Hook
  self.namespace = :run_counter

  class << self
    def count = @count ||= 0

    def before_run(_ctx)
      @count = count + 1
      puts "run ##{@count}"   # 1, 2, 3, ... across runs
    end
  end
end

RobotLab.on(RunCounter)
```

---

## Around Hooks

Around hooks are class methods that accept the context and a block. They must call `block.call` and must return its return value — that is how the actual LLM call, network step, or task is executed:

```ruby
class PerfHook < RobotLab::Hook
  self.namespace = :perf

  def self.around_run(ctx, &block)
    t0     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = block.call   # MUST call — this is the actual run
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1)
    puts "#{ctx.request.inspect} — #{elapsed}ms"
    result               # MUST return — callers expect the real result
  end
end
```

> [!IMPORTANT]
> If `around_run`, `around_llm_generation`, `around_network_run`, or `around_task`
> does not return the block's return value, the operation returns `nil`. This is a
> silent failure — there is no exception.
>
> `around_compaction` and `around_learn` are the return-value-agnostic exceptions:
> nothing consumes their result, so forgetting the return value is harmless. They
> must still call `block.call` — skipping it suppresses the compaction or the
> learning entirely. `around_tool_call` is different again; see below.

Around hooks registered across different handler classes are chained: each wraps the next, with the actual operation at the innermost layer.

### `around_tool_call` is different

Tool call hooks use `ctx.tool_result` as the result carrier, not the block's return value. `Tool#call` always returns `context.tool_result` regardless of what the around hook returns.

To **let the tool execute normally**, call `block.call` — it sets `ctx.tool_result` — and then do any post-processing:

```ruby
class ToolTimingHook < RobotLab::Hook
  self.namespace = :timing

  def self.around_tool_call(ctx, &block)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    block.call   # executes the tool and populates ctx.tool_result
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1)
    $stderr.puts "[tool] #{ctx.tool_name} — #{ms}ms"
  end
end
```

To **short-circuit the tool** (skip execution entirely), skip `block.call` and set `ctx.tool_result` directly:

```ruby
class ToolGuardHook < RobotLab::Hook
  self.namespace = :guard

  ALLOWED_TOOLS = %w[web_search calculator].freeze

  def self.around_tool_call(ctx, &block)
    if ALLOWED_TOOLS.include?(ctx.tool_name)
      block.call
    else
      ctx.tool_result = "Operation not permitted: #{ctx.tool_name}"
    end
  end
end
```

### `on_compaction` — Replacing the Core Strategy

`on_compaction` is a point hook inside the `around_compaction` block. Unlike the other hooks in this family, it is not a lifecycle observer — it is an escape hatch that lets an extension supply its own message array in place of the built-in `HistoryCompressor`.

To replace the core algorithm, assign `ctx.compacted_messages` in an `on_compaction` handler. Once assigned, `ctx.handled?` returns `true` and the core skips `compress_history`, using the handler's message array instead:

```ruby
class SemanticCompressor < RobotLab::Hook
  self.namespace = :semantic_compressor

  def self.on_compaction(ctx)
    ctx.compacted_messages = MyCompressor.run(ctx.messages_before, ctx.robot)
  end
end

robot.on(SemanticCompressor)
```

If `on_compaction` does not assign `ctx.compacted_messages`, the core algorithm runs as normal.

> [!WARNING]
> With multiple `on_compaction` handlers, **the last one to assign
> `ctx.compacted_messages` wins.** `Hooks.call(:on_compaction, ...)` runs every
> registered handler unconditionally, and `compacted_messages` is a plain
> accessor — `handled?` is only consulted *after* all of them have run, so a later
> handler silently overwrites an earlier handler's message array. Register at most
> one compaction-replacing handler, or have later handlers check `ctx.handled?`
> themselves before assigning.

> **Note:** `on_compaction` fires inside the core block of `Hooks.run(:compaction)`. It is not a standard `before_*/around_*/after_*` hook — it does not compose with around handlers or produce a chainable result. Use `around_compaction` if you need to wrap the entire process including observation of the final result.

### `on_learn` — Implementing Long-Term Persistence

`on_learn` is a point hook that fires inside the core block of `Hooks.run(:learn)`, after the session-level deduplication and storage have already run. Its purpose is to give extensions the opportunity to persist a learning to long-term storage without the core knowing anything about how or where.

The hook receives a `LearnHookContext` with `ctx.stored` already set, so an extension can decide whether to persist based on whether the learning was genuinely new to this session:

```ruby
class DurableMemoryHook < RobotLab::Hook
  self.namespace = :durable

  def self.on_learn(ctx)
    return unless ctx.stored   # skip deduplicated-away learnings

    LongTermStore.write(
      text:   ctx.text,
      robot:  ctx.robot.name,
      domain: ctx.local.domain
    )
  end
end

robot.on(DurableMemoryHook, context: { domain: "customer_support" })
```

Unlike `on_compaction`, `on_learn` does not use a `handled?` flag — there is no "default persistence" in the core to replace. Every registered `on_learn` handler fires; each extension independently decides what to do with the learning.

`on_learn` fires even when `ctx.stored` is `false` (the text was deduplicated away). This allows extensions to apply their own deduplication policy for long-term storage, which may differ from the session-level substring logic. Check `ctx.stored` explicitly if you only want to act on genuinely new learnings.

---

## Context Objects

Each hook family receives a typed context object. All context objects provide access to `ctx.local` (the handler's namespace `DotState`) and `ctx.ext(:name)` (cross-namespace reads).

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
| `iteration` | Integer | **Always `0`.** The field exists but is never passed a value, because the family fires once per run rather than once per LLM call. Do not branch on it. |

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

### CompactionHookContext

Passed to `:compaction` hooks (`before_compaction`, `around_compaction`, `after_compaction`, `on_compaction`).

| Attribute | Type | Notes |
|-----------|------|-------|
| `event` | Symbol | `:compaction` |
| `robot` | Robot | The robot whose history is being compacted |
| `messages_before` | Array (frozen) | Snapshot of `@chat.messages` at the moment compaction was triggered |
| `config` | RunConfig | The robot's active configuration |
| `strategy` | Symbol | `:context_window` when triggered by the threshold check; `:custom` when triggered by a `Proc` |
| `compacted_messages` | Array\|nil | Set by the core algorithm after compaction, or set by an `on_compaction` handler to replace the core algorithm |
| `error` | Exception\|nil | Set if compaction raises |
| `metadata` | ExtensionState | |

#### `ctx.handled?`

Returns `true` once `ctx.compacted_messages` has been assigned. The core compaction algorithm checks `handled?` after `on_compaction` fires — if `true`, it skips `compress_history` and calls `replace_messages` with the handler's result instead. See [on_compaction](#on_compaction-replacing-the-core-strategy) below.

### LearnHookContext

Passed to `:learn` hooks (`before_learn`, `around_learn`, `after_learn`, `on_learn`).

| Attribute | Type | Notes |
|-----------|------|-------|
| `event` | Symbol | `:learn` |
| `robot` | Robot | The robot learning |
| `text` | String | The stripped, non-empty learning text passed to `robot.learn` |
| `learnings_before` | Array (frozen) | Snapshot of `robot.learnings` at the moment `learn` was called |
| `stored` | Boolean | `true` if the text was added to session learnings; `false` if it was skipped because an existing learning already covers it. Set during the core block — readable in `on_learn` and `after_learn`. |
| `error` | Exception\|nil | Set if the learn block raises |
| `metadata` | ExtensionState | |

#### `ctx.stored`

`false` means the text was deduplicated away at the session level — an existing learning already contains or supersedes it. Extensions implementing `on_learn` should check this flag when their own deduplication policy matches the session-level policy. Extensions with a different policy (for example, treating every explicit instruction as authoritative regardless of overlap) may ignore it.

---

## Per-Run Hooks

For one-off instrumentation tied to a single call, pass a `hooks:` argument to `robot.run`. Supply a single handler class or an array of handler classes:

```ruby
result = robot.run("summarize this", hooks: TraceHook)
```

```ruby
result = robot.run("summarize this", hooks: [TraceHook, MetricsHook])
```

Per-run hooks fire after robot-level hooks, in the order supplied.

---

## Error Hooks

The `on_error` hook fires when an unhandled exception escapes a run, network run, or task. It receives the same context object as its family's `after_*` hook, with the `error` attribute set:

```ruby
class AlertingHook < RobotLab::Hook
  self.namespace = :alerting

  def self.on_error(ctx)
    if ctx.respond_to?(:robot)
      puts "ERROR in #{ctx.robot.name}: #{ctx.error.class} — #{ctx.error.message}"
      Alerting.notify(ctx.error, robot: ctx.robot.name, request: ctx.request)
    else
      puts "Network error: #{ctx.error.message}"
    end
  end
end

RobotLab.on(AlertingHook)
```

`on_error` does not suppress the exception. The error continues to propagate after all `on_error` hooks finish.

---

## Writing an Extension

The recommended pattern is a subclass of `RobotLab::Hook` with all lifecycle callbacks defined in a `class << self` block. Keeping all callbacks in one class makes the extension easy to attach to different registries (global, a specific network, or a specific robot) and easy to test in isolation.

```ruby
class MyExtension < RobotLab::Hook
  self.namespace = :my_ext

  class << self
    attr_writer :logger
    def logger
      @logger ||= Logger.new($stdout)
    end

    attr_accessor :call_count   # class-level: survives across runs

    def before_run(ctx)
      self.call_count = call_count.to_i + 1
      ctx.local.started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      logger.info("run ##{call_count} starting: #{ctx.request.inspect}")
    end

    def after_run(ctx)
      logger.info("run done: #{ctx.response&.reply.to_s[0, 80]}")
    end

    def on_error(ctx)
      logger.error("run failed: #{ctx.error.class} — #{ctx.error.message}")
    end
  end
end
```

To attach globally:

```ruby
RobotLab.on(MyExtension)
```

To attach only to a specific network:

```ruby
network.on(MyExtension)
```

To attach only to a specific robot:

```ruby
robot.on(MyExtension)
```

With per-registration default state — re-applied at the start of every run, so use it for constants and configuration, not for accumulators:

```ruby
RobotLab.on(MyExtension, context: { service: "checkout" })
```

### Extension Guidelines

- Set `self.namespace = :my_name` explicitly so callers can read the namespace without relying on class naming conventions.
- Use `context:` on the `on(...)` call to declare default state rather than guarding against `nil` inside callbacks. Remember the defaults are re-applied per run — keep anything that must accumulate on the handler class instead of in `ctx.local`.
- Around hooks whose block result is the operation's result (`around_run`, `around_llm_generation`, `around_network_run`, `around_task`) must call `block.call` **and** return its value — omitting either causes the run to return `nil`.
- `around_compaction` and `around_learn` are return-value-agnostic: nothing consumes their result, so forgetting to return the block's value is harmless. They must still call `block.call` — skipping it suppresses the compaction (or the learning) entirely.
- `around_tool_call` is different again: the result is carried in `ctx.tool_result`, so call `block.call` to let the tool run, or set `ctx.tool_result` directly to short-circuit.
- Keep error hooks non-raising. Exceptions from hook callbacks propagate and can mask the original error.
- Test each callback method in isolation by constructing a context object directly and calling the class method.

---

## Common Patterns

### Performance Timer

```ruby
class PerfHook < RobotLab::Hook
  self.namespace = :perf

  def self.around_run(ctx, &block)
    t0     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = block.call
    ms     = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1)
    $stderr.puts "[perf] #{ctx.robot.name} #{ms}ms"
    result
  end
end

RobotLab.on(PerfHook)
```

### Request/Response Tracer

```ruby
class TraceHook < RobotLab::Hook
  self.namespace = :trace

  def self.before_run(ctx)
    puts "→ #{ctx.robot.name}: #{ctx.request.inspect}"
  end

  def self.after_run(ctx)
    puts "← #{ctx.robot.name}: #{ctx.response&.reply.to_s[0, 120]}"
  end
end

robot.on(TraceHook)
```

### LLM Response Cache

Use `around_llm_generation` to skip the LLM call entirely when a cached response exists. A `before_llm_generation` hook cannot short-circuit the call — it must be an `around_` hook:

```ruby
class LlmCacheHook < RobotLab::Hook
  self.namespace = :cache

  class << self
    attr_accessor :hits   # class-level — ctx.local resets every run

    def around_llm_generation(ctx, &block)
      cached = ResponseCache.get(ctx.request)
      if cached
        self.hits = hits.to_i + 1
        cached              # return cached value — block.call (LLM) is skipped
      else
        result = block.call # LLM call happens here
        ResponseCache.set(ctx.request, result)
        result
      end
    end
  end
end

robot.on(LlmCacheHook)
```

Skipping `block.call` here skips the *entire* generation phase for that run, including the provider's tool loop — the `:llm_generation` family wraps the whole phase, not one API round trip.

### Tool Call Audit Log

```ruby
class ToolAuditHook < RobotLab::Hook
  self.namespace = :audit

  def self.before_tool_call(ctx)
    AuditLog.write(
      robot:     ctx.robot&.name,
      tool:      ctx.tool_name,
      args:      ctx.tool_args,
      timestamp: Time.now.utc
    )
  end
end

RobotLab.on(ToolAuditHook)
```

### Learn Audit Log

Record every learning attempt — including the ones that were deduplicated away — for debugging or analytics:

```ruby
class LearnAuditHook < RobotLab::Hook
  self.namespace = :learn_audit

  def self.after_learn(ctx)
    status = ctx.stored ? "stored" : "skipped (covered)"
    $stderr.puts "[learn] #{ctx.robot.name}: #{status} — #{ctx.text.inspect}"
  end
end

RobotLab.on(LearnAuditHook)
```

### Long-Term Memory Promotion via `on_learn`

Persist new learnings to durable storage. `on_learn` fires after session storage so the session state is already updated when the extension runs:

```ruby
class DurableLearnHook < RobotLab::Hook
  self.namespace = :durable

  def self.on_learn(ctx)
    return unless ctx.stored

    DurableStore.promote(
      text:      ctx.text,
      robot:     ctx.robot.name,
      domain:    ctx.local.domain,
      timestamp: Time.now.utc
    )
  end
end

robot.on(DurableLearnHook, context: { domain: "finance" })
```

### Blocking Unauthorised Learnings

Use `around_learn` to gate what a robot is allowed to learn — useful when the robot's system prompt comes from untrusted input:

```ruby
class LearnGuardHook < RobotLab::Hook
  self.namespace = :learn_guard

  BLOCKED_PATTERN = /ignore previous instructions|forget everything/i

  def self.around_learn(ctx, &block)
    if BLOCKED_PATTERN.match?(ctx.text)
      $stderr.puts "[learn_guard] Blocked: #{ctx.text.inspect}"
      # Do not call block.call — the learning is silently dropped
    else
      block.call
    end
  end
end

RobotLab.on(LearnGuardHook)
```

### Compaction Observability

Log when and why history compression fires, and how much it reduced the message count:

```ruby
class CompactionLoggerHook < RobotLab::Hook
  self.namespace = :compaction_logger

  def self.before_compaction(ctx)
    ctx.local.before_count = ctx.messages_before.size
    ctx.local.started_at   = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.after_compaction(ctx)
    after_count = ctx.compacted_messages&.size || ctx.local.before_count
    elapsed_ms  = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - ctx.local.started_at) * 1000).round(1)
    dropped     = ctx.local.before_count - after_count
    $stderr.puts "[compaction] #{ctx.robot.name} #{ctx.strategy}: " \
                 "#{ctx.local.before_count} → #{after_count} messages " \
                 "(-#{dropped}) in #{elapsed_ms}ms"
  end
end

RobotLab.on(CompactionLoggerHook)
```

### Promote Session Learnings Before Compaction

When conversation history is about to be compressed, an extension can inspect the messages about to be dropped and promote important information to long-term storage before it is lost:

```ruby
class LearningPromotionHook < RobotLab::Hook
  self.namespace = :learning_promotion

  def self.before_compaction(ctx)
    ctx.local.message_ids_before = ctx.messages_before.map(&:object_id).to_set
  end

  def self.after_compaction(ctx)
    return unless ctx.compacted_messages
    surviving_ids = ctx.compacted_messages.map(&:object_id).to_set
    dropped = ctx.messages_before.reject { |m| surviving_ids.include?(m.object_id) }
    LongTermStore.promote(dropped, domain: ctx.robot.name) if dropped.any?
  end
end

robot.on(LearningPromotionHook)
```

### Custom Compaction Strategy

Replace the built-in term-frequency compressor with a domain-specific algorithm using `on_compaction`:

```ruby
class SummarizerCompactor < RobotLab::Hook
  self.namespace = :summarizer_compactor

  KEEP_RECENT = 4  # always keep the last N user+assistant pairs verbatim

  def self.on_compaction(ctx)
    messages  = ctx.messages_before
    pinned    = messages.select { |m| %i[system tool tool_result].include?(m.role) }
    scoreable = messages.reject { |m| %i[system tool tool_result].include?(m.role) }

    recent    = scoreable.last(KEEP_RECENT * 2)
    older     = scoreable.first([scoreable.size - KEEP_RECENT * 2, 0].max)

    summary_text = ctx.robot.run("Summarize in two sentences: #{older.map(&:content).join(' ')}")
                          .reply

    summary_msg  = OpenStruct.new(role: :assistant, content: summary_text,
                                  tool_calls: nil, stop_reason: :stop)

    ctx.compacted_messages = pinned + [summary_msg] + recent
  end
end

robot.on(SummarizerCompactor)
```

### Run Counter Per Robot

Cross-run tallies belong on the handler class — `ctx.local` is wiped between runs:

```ruby
class MetricsHook < RobotLab::Hook
  self.namespace = :metrics

  class << self
    def counts = @counts ||= Hash.new(0)

    def before_run(ctx)
      counts[ctx.robot.name] += 1
    end
  end
end

RobotLab.on(MetricsHook)

# later
MetricsHook.counts   # => { "classifier" => 12, "responder" => 12 }
```

---

## Application Use Cases

Hooks are the primary extension point in RobotLab. Below are concrete patterns that production applications commonly build on top of them. The `:compaction` family is particularly important for long-term memory extensions: it provides the earliest possible signal that conversation history is about to be lost, giving extensions the opportunity to promote valuable content before it is compressed away.

### Observability and Distributed Tracing

Instrument every LLM call with a trace ID and structured log entry for ingestion into OpenTelemetry, Datadog, or a custom logging pipeline:

```ruby
class ObservabilityHook < RobotLab::Hook
  self.namespace = :trace

  def self.before_run(ctx)
    ctx.local.trace_id   = SecureRandom.hex(8)
    ctx.local.started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.after_run(ctx)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - ctx.local.started_at) * 1000).round(1)
    Logger.info(
      event:      "robot.run.completed",
      trace_id:   ctx.local.trace_id,
      robot:      ctx.robot.name,
      elapsed_ms: elapsed_ms,
      reply:      ctx.response&.reply.to_s[0, 120]
    )
  end

  def self.on_error(ctx)
    Logger.error(
      event:    "robot.run.failed",
      trace_id: ctx.local.trace_id,
      robot:    ctx.robot.name,
      error:    ctx.error.class.to_s,
      message:  ctx.error.message
    )
  end
end

RobotLab.on(ObservabilityHook)
```

### Cost Enforcement

Cap total spending across all robots in a session and raise before an expensive run would push you over budget:

A session total must live on the handler class — `ctx.local` is re-created per run and would reset the tally every time:

```ruby
class BudgetHook < RobotLab::Hook
  self.namespace = :budget

  COST_PER_INPUT_TOKEN  = 0.80 / 1_000_000
  COST_PER_OUTPUT_TOKEN = 4.00 / 1_000_000
  SESSION_BUDGET_USD    = 0.50

  class << self
    def total_cost = @total_cost ||= 0.0

    def before_run(_ctx)
      if total_cost >= SESSION_BUDGET_USD
        raise RobotLab::Error, "Session budget of $#{SESSION_BUDGET_USD} exceeded"
      end
    end

    def after_run(ctx)
      r = ctx.response
      @total_cost = total_cost +
                    r.input_tokens  * COST_PER_INPUT_TOKEN +
                    r.output_tokens * COST_PER_OUTPUT_TOKEN
    end
  end
end

RobotLab.on(BudgetHook)
```

For a single robot's own token/dollar ceiling (rather than a cross-robot session total), `token_budget:`/`cost_budget:` on `Robot.new` give you this natively — see [Budgets](observability.md#budgets-token-cost) — including a `RobotLab::BudgetExceeded` raised up front once a prior call already exhausted the budget, so the next call is refused before it spends anything.

### Tool Access Control

Allow only approved tools to execute for a given network, without hard-coding restrictions in the tool itself:

```ruby
class AccessControlHook < RobotLab::Hook
  self.namespace = :access_control

  ALLOWED_TOOLS = %w[web_search calculator].freeze

  def self.around_tool_call(ctx, &block)
    if ALLOWED_TOOLS.include?(ctx.tool_name)
      block.call
    else
      ctx.tool_result = "[blocked] Tool '#{ctx.tool_name}' is not permitted in this network."
    end
  end
end

network.on(AccessControlHook)
```

### Audit Logging for Compliance

Record every tool invocation with its arguments and result for security audits or regulatory compliance:

```ruby
class ComplianceAuditHook < RobotLab::Hook
  self.namespace = :audit

  def self.after_tool_call(ctx)
    AuditLog.append(
      robot:     ctx.robot&.name,
      tool:      ctx.tool_name,
      args:      ctx.tool_args,
      result:    ctx.tool_result.to_s[0, 500],
      timestamp: Time.now.utc.iso8601
    )
  end
end

RobotLab.on(ComplianceAuditHook)
```

### Retry with Exponential Backoff

Wrap `around_run` to retry on transient LLM failures without changing any robot code:

```ruby
class RetryHook < RobotLab::Hook
  self.namespace = :retry

  MAX_RETRIES  = 3
  BACKOFF_BASE = 0.5

  def self.around_run(ctx, &block)
    attempts = 0
    begin
      attempts += 1
      block.call
    rescue RobotLab::InferenceError
      raise if attempts >= MAX_RETRIES

      sleep(BACKOFF_BASE * (2**(attempts - 1)))
      retry
    end
  end
end

RobotLab.on(RetryHook)
```

### Test Doubles Without Network Calls

Inject canned LLM responses in tests by short-circuiting `around_llm_generation`. No VCR cassettes, no HTTP mocks:

```ruby
class TestDoubleHook < RobotLab::Hook
  self.namespace = :test_double

  CANNED_RESPONSES = {
    "classify this" => FakeResponse.new(content: "positive"),
    "summarize"     => FakeResponse.new(content: "short summary")
  }.freeze

  def self.around_llm_generation(ctx, &block)
    canned = CANNED_RESPONSES[ctx.request]
    canned ? canned : block.call
  end
end

# In test setup:
RobotLab.on(TestDoubleHook)
```

### Per-Network Latency Metrics

Collect timing data scoped to a specific network without touching global hooks:

```ruby
class NetworkMetricsHook < RobotLab::Hook
  self.namespace = :metrics

  def self.before_network_run(ctx)
    ctx.local.started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.after_network_run(ctx)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - ctx.local.started_at) * 1000).round(1)
    Metrics.histogram("network.run.duration_ms", elapsed_ms, tags: { network: ctx.network.name })
  end
end

network.on(NetworkMetricsHook)
```

### Sensitive Data Redaction

Scrub PII from requests before they are logged or sent to the LLM:

```ruby
class RedactionHook < RobotLab::Hook
  self.namespace = :redaction

  PII_PATTERN = /\b[A-Z]{2}\d{6,9}\b/  # example: passport numbers

  def self.before_run(ctx)
    ctx.request = ctx.request&.gsub(PII_PATTERN, "[REDACTED]")
  end
end

RobotLab.on(RedactionHook)
```

---

## Extension Registration

Hooks inject *behavior* ("do this on these events"). A separate, lighter
mechanism — **extension registration** — answers a different question: *"is
optional feature X loaded?"* This is how core lights up conditional behavior
without depending on, or probing for, the gem that provides it. The two
mechanisms are orthogonal but commonly used together: a gem registers itself
(discovery), then wires behavior in via a hook (injection).

### The API

```ruby
RobotLab.register_extension(:audit, RobotLab::Audit)  # gem announces itself
RobotLab.extension_loaded?(:audit)                     # => true/false — core's guard
RobotLab.extension(:audit)                             # => RobotLab::Audit
RobotLab.loaded_extensions                             # => [:audit, :ractor, ...]
```

It is deliberately tiny: a `Hash` and four methods. The registered value can be
the extension's primary module, or just a sentinel when the gem only needs a
presence flag:

```ruby
RobotLab.register_extension(:ractor, :ractor_extension_loaded)
```

### How an Extension Announces Itself

At the bottom of the gem's entry file, after everything it provides is
defined, guarded so the gem can also load standalone or against an older core:

```ruby
# robot_lab-audit/lib/robot_lab/audit.rb (tail)
if defined?(RobotLab) && RobotLab.respond_to?(:register_extension)
  RobotLab.register_extension(:audit, RobotLab::Audit)
end
```

The same one-liner appears verbatim in `robot_lab-document_store`,
`robot_lab-durable`, `robot_lab-discovery`, etc. Registration last, guarded
always.

### How Core Consumes It

Core guards optional behavior with `extension_loaded?` instead of scattered
`defined?` / `respond_to?` probes — one named question, asked in one style:

```ruby
# tool.rb — only use the Ractor pool when the gem is present
self.class.ractor_safe? && !self.class.name.nil? && RobotLab.extension_loaded?(:ractor)

# memory.rb — semantic features require the document_store gem
unless RobotLab.extension_loaded?(:document_store)
  …
end
```

When a guarded feature is *requested* without its extension, core raises a
helpful error naming the exact gem to add — not a cryptic `NoMethodError`:

```ruby
# network.rb — parallel_mode: :ractor needs the gem
def run_with_ractor_scheduler(run_context)
  unless RobotLab.extension_loaded?(:ractor)
    raise RobotLab::DependencyError,
          "parallel_mode: :ractor requires the robot_lab-ractor gem. " \
          "Add `gem 'robot_lab-ractor'` to your Gemfile."
  end
  …
end
```

### Version-Skew Tolerance

`robot_lab-a2a` ships a fallback so it works even against a core too old to
provide the registry API: if `register_extension` isn't defined, the gem
**defines it** (plus `extension_loaded?`/`extension`) over its own private
`@_extensions` hash, then registers itself:

```ruby
module RobotLab
  @_extensions = {} unless instance_variable_defined?(:@_extensions)

  class << self
    unless method_defined?(:register_extension) || respond_to?(:register_extension)
      def register_extension(name, mod) = @_extensions[name.to_sym] = mod
    end
    unless method_defined?(:extension_loaded?) || respond_to?(:extension_loaded?)
      def extension_loaded?(name) = @_extensions.key?(name.to_sym)
    end
    # … extension(name) likewise …
  end
end

RobotLab.register_extension(:a2a, RobotLab::A2A)
```

The gem never assumes the core's age; it provides the contract if it must.

### How It Composes with Hooks

- `register_extension(:audit, RobotLab::Audit)` — *"I exist"* (discovery).
- Inside `Audit.enable(db_path:)` → `RobotLab.on(Hook)` — *"do this on these
  events"* (behavior).

Two common shapes:

- **Auto-wire at load** — register the extension *and* `RobotLab.on(SomeHook)`
  at require time (always-on features).
- **Opt-in enable** — register the extension at load, but expose
  `enable!`/`enable(...)` that registers the hook on demand
  (`Audit.enable`, `Narrator.enable!`). Lets the user choose scope/config.

> [!TIP]
> Design decisions worth stealing: a named capability registry beats
> duck-typing; core never `require`s an extension — the extension `require`s
> core and announces itself; a sentinel value works when you only need a
> presence flag; and using a guarded feature without its gem should raise a
> helpful error naming the exact gem to add.

---

## See Also

- [examples/35_hooks.rb](https://github.com/MadBomber/robot_lab/blob/main/examples/35_hooks.rb) — full demo with xyzzy extension, perf timer, LLM response cache, and tracer hooks
- [examples/xyzzy.rb](https://github.com/MadBomber/robot_lab/blob/main/examples/xyzzy.rb) — single-file reference extension (`RobotLab::Xyzzy < RobotLab::Hook`) that registers for every hook family
- [Robot Execution](../architecture/robot-execution.md)
- [Observability & Safety](observability.md)
