# Support Classes

Method-level reference for the classes that back RobotLab's core behaviors but
that you rarely construct yourself. The features they implement are explained in
the guides; this page is the API surface, so nothing public is left undocumented.

| Class | Backs | Guide |
|-------|-------|-------|
| [`Task`](#robotlabtask) | Per-task config in a network pipeline | [Creating Networks](../guides/creating-networks.md) |
| [`Runnable`](#robotlabrunnable) | The shared `Robot`/`Network` interface | [Core Concepts](../architecture/core-concepts.md#runnable-protocol) |
| [`ToolConfig`](#robotlabtoolconfig) | `:none` / `:inherit` / array resolution | [Using Tools](../guides/using-tools.md) |
| [`ToolManifest`](#robotlabtoolmanifest) | Name-keyed tool collection | [Using Tools](../guides/using-tools.md) |
| [`Budget::Ledger`](#robotlabbudgetledger) | `token_budget` / `cost_budget` | [Budgets](../guides/observability.md#budgets-token-cost) |
| [`DoomLoopDetector`](#robotlabdoomloopdetector) | Always-on tool-loop detection | [Doom Loop Detection](../guides/observability.md#doom-loop-detection) |
| [`HistoryCompressor`](#robotlabhistorycompressor) | `compress_history` / `auto_compact` | [Context Compression](../guides/observability.md#context-window-compression) |
| [`Convergence`](#robotlabconvergence) | Agreement detection between two texts | [Convergence Detection](../guides/observability.md#convergence-detection) |
| [`TextAnalysis`](#robotlabtextanalysis) | TF/TF-IDF primitives under all of the above | — |
| [`DelegationFuture`](#robotlabdelegationfuture) | `delegate(async: true)` | [Structured Delegation](../guides/observability.md#structured-delegation) |
| [`RobotMessage`](#robotlabrobotmessage) | Bus message envelope | [Core Concepts](../architecture/core-concepts.md) |
| [`BusPoller`](#robotlabbuspoller) | Per-robot bus delivery serialization | [Creating Networks](../guides/creating-networks.md) |
| [`Waiter`](#robotlabwaiter) | `memory.get(wait:)` blocking reads | [Memory](../guides/memory.md) |
| [`Narrator`](#robotlabnarrator) | Live console narration | [Live Narration](../guides/observability.md#live-narration-robotlabnarrator) |
| [`Config`](#robotlabconfig) | `RobotLab.config` | [Configuration](../getting-started/configuration.md) |
| [`MCP::ServerDiscovery`](#robotlabmcpserverdiscovery) | `mcp_discovery: true` | [MCP Integration](../guides/mcp-integration.md) |
| [`MCP::ConnectionPoller`](#robotlabmcpconnectionpoller) | Multiplexed stdio MCP I/O | [Transports](mcp/transports.md) |
| [`Streaming::SequenceCounter`](#robotlabstreamingsequencecounter) | Event ordering (unused by core) | [Streaming](streaming/index.md) |

---

## RobotLab::Task

Wraps a `Robot` as a SimpleFlow pipeline step, carrying per-task context, MCP,
tools, memory, and config. `Network#task` builds one for you — you would only
construct one directly when driving a `SimpleFlow::Pipeline` yourself.

### Constructor

```ruby
RobotLab::Task.new(name:, robot:, context: {}, mcp: :none, tools: :none,
                   memory: nil, config: nil, network: nil)
```

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `Symbol` | **required** | Task name; symbolized |
| `robot` | `Robot` | **required** | The robot to execute |
| `context` | `Hash` | `{}` | Deep-merged over the run params (nested Hashes merge recursively; Arrays are replaced, not concatenated) |
| `mcp` | `Symbol`, `Array` | `:none` | Injected into `run_params[:mcp]` — only when not `:none` |
| `tools` | `Symbol`, `Array` | `:none` | Injected into `run_params[:tools]` — only when not `:none` |
| `memory` | `Memory`, `Hash`, `nil` | `nil` | Overrides the network's shared memory for this task |
| `config` | `RunConfig`, `nil` | `nil` | Merged **on top of** any inherited `network_config` |
| `network` | `Network`, `nil` | `nil` | Owning network; supplies `hooks` and default `memory` |

### name / robot

```ruby
task.name   # => Symbol
task.robot  # => Robot
```

### call

```ruby
task.call(result)  # => SimpleFlow::Result
```

The SimpleFlow step interface. Builds a `TaskHookContext`, runs the `:task` hook
family against `[RobotLab.hooks, network&.hooks]`, and inside it calls
`robot.call(enhanced_result)` with the task's configuration merged into
`run_params`.

!!! warning "The `:task` family never sees a robot's own registry"
    Registries are `[RobotLab.hooks, @network&.hooks]` — `robot.hooks` is not
    consulted. A `before_task`/`around_task`/`after_task`/`on_error` handler
    registered with `robot.on` will never fire; use `RobotLab.on` or `network.on`.

### to_h

```ruby
task.to_h
# => { name: :billing, robot: "billing_bot", context: {...}, mcp: :none, tools: :none }
```

`.compact`ed. `memory` appears as `true` when a task-specific memory was supplied
and is omitted otherwise; the memory object itself is never serialized. `config`
and `network` are not included at all.

---

## RobotLab::Runnable

The shared interface `Robot` and `Network` both implement, so callers can treat
either uniformly instead of branching on `is_a?(RobotLab::Network)`.

**Implementers must provide** `#run(message = nil, **opts)`, `#crew`, and
optionally override `#network?`. The rest derive.

| Method | Default implementation | `Robot` | `Network` |
|--------|------------------------|---------|-----------|
| `crew` | raises `NotImplementedError` | `[self]` | `robots.values` |
| `chief` | `crew.first` | the robot | first robot in pipeline order |
| `robot_count` | `crew.size` | `1` | number of robots |
| `network?` | `false` | `false` | `true` |
| `single?` | `!network?` | `true` | `false` |

```ruby
def summarize(runnable)
  runnable.run(prompt, mcp: :inherit, tools: :inherit)
  puts "#{runnable.robot_count} robot(s): #{runnable.crew.map(&:name).join(', ')}"
  puts "network!" if runnable.network?
end
```

!!! note "`crew` returns robot instances, not `network.robots` keys"
    `network.crew.map(&:name)` yields each **robot's** name, which differs from
    `network.robots.keys` (task names) unless you name each robot after its task.

---

## RobotLab::ToolConfig

Resolves the `:none` / `:inherit` / array values used at every level of the tools
and MCP hierarchy. Module functions.

### NONE_VALUES

```ruby
RobotLab::ToolConfig::NONE_VALUES  # => [nil, [], :none]
```

All three mean "nothing at this level".

### resolve

```ruby
RobotLab::ToolConfig.resolve(value, parent_value:)  # => Array
```

| `value` | Result |
|---------|--------|
| `:inherit` | `Array(parent_value)` |
| `nil`, `[]`, `:none` | `[]` |
| anything else | `Array(value)` |

### resolve_mcp / resolve_tools

```ruby
RobotLab::ToolConfig.resolve_mcp(value, parent_value:)    # => Array
RobotLab::ToolConfig.resolve_tools(value, parent_value:)  # => Array<String>
```

`resolve_mcp` is `resolve` verbatim (server configs stay as-is).
`resolve_tools` additionally maps every entry through `to_s`, which is why a
tools allowlist is matched against `tool.name.to_s` and a Symbol entry works
interchangeably with a String.

### none_value? / inherit_value?

```ruby
RobotLab::ToolConfig.none_value?(:none)      # => true
RobotLab::ToolConfig.none_value?([])         # => true
RobotLab::ToolConfig.inherit_value?(:inherit) # => true
```

`Robot#build_effective_config` uses `none_value?` to decide whether an
`mcp:`/`tools:` kwarg is worth storing on the `RunConfig` at all.

### filter_tools

```ruby
RobotLab::ToolConfig.filter_tools(tools, allowed_names: %w[order_lookup])
# => Array — the subset whose names match
```

!!! warning "An empty allowlist means *no* tools here"
    `filter_tools(tools, allowed_names: [])` returns `[]`, **not** all tools.
    `Robot#filtered_tools` short-circuits before reaching this method when the
    allowlist is empty (treating it as "no filter"), which is why `Robot#run`
    has to branch on the *raw* runtime value to honor an explicit `tools: :none`.
    See [Robot: run](core/robot.md#run).

Names are extracted with `tool.name.to_s` for objects, and used verbatim for
String/Symbol entries — so a class-attached tool matches `"RefundTool"` while an
instance-attached one matches its declared `"refund"`.

---

## RobotLab::ToolManifest

A name-keyed collection of tools, including `Enumerable`. Not used on the hot
path by `Robot` (which keeps plain Arrays), but available for applications
managing tool catalogs.

```ruby
manifest = RobotLab::ToolManifest.new([weather_tool, calculator_tool])
manifest[:get_weather]  # => Tool
manifest.names          # => ["get_weather", "calculate"]
```

Tools are keyed by `tool.name.to_s`, and every lookup coerces its argument with
`to_s` — so `manifest[:get_weather]` and `manifest["get_weather"]` are the same
entry.

| Method | Returns | Description |
|--------|---------|-------------|
| `ToolManifest.new(tools = [])` | `ToolManifest` | Each tool is added via `add` |
| `add(tool)` | `self` | Register a tool under its `name`. Aliased as `<<` |
| `[](name)` | `Tool`, `nil` | Lookup; `nil` when absent |
| `fetch(name)` | `Tool` | Lookup, but **raises `RobotLab::ToolNotFoundError`** listing the available names |
| `include?(name)` | `Boolean` | Whether that name is registered. Aliased as `has?` |
| `remove(name)` | `Tool`, `nil` | Delete and return the tool |
| `replace(tools)` | `self` | **Clears the manifest** and adds `tools` — replaces the whole collection, not one entry |
| `merge(other)` | `self` | Add every tool from a `ToolManifest`, an `Array`, or a single `Tool`. Mutates the receiver and returns it — it does **not** build a new manifest |
| `names` | `Array<String>` | Registered names |
| `values` | `Array<Tool>` | The tools themselves. Aliased as `all` and `to_a` |
| `each { \|tool\| }` | — | `Enumerable` entry point (yields tools, not pairs) |
| `size` | `Integer` | Number of tools. Aliased as `count` and `length` |
| `empty?` | `Boolean` | |
| `clear` | `self` | Remove everything |
| `to_h` | `Hash<String, Hash>` | Name => `tool.to_h` |
| `to_json` | `String` | Serializes `to_h` |
| `ToolManifest.from_hash(hash)` | `ToolManifest` | Rebuilds each entry with `Tool.create(name:, description:, parameters:, &handler)` |

!!! warning "`from_hash` is not the inverse of `to_h`"
    `to_h` emits `Tool#to_h` (`name`, `description`, `mcp`), while `from_hash`
    expects each value to carry `:parameters` and a `:handler` Proc. Round-tripping
    a manifest through `to_h` → `from_hash` yields tools with no parameters and a
    `nil` handler.

---

## RobotLab::Budget::Ledger

Thread-safe reserve/reconcile ledger tracking consumption against per-dimension
limits. `Robot` builds one automatically when `token_budget:` and/or
`cost_budget:` is configured, and exposes it as `robot.budget_ledger` (`nil`
otherwise).

The reserve-then-reconcile shape exists because an LLM call's size is unknowable
in advance: `reserve!` claims everything still available so an already-exhausted
budget is caught *before* spending, and `reconcile!` swaps that claim for the
actual usage once the response is back.

### Constructor

```ruby
ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 10_000, cost: 0.50 }, consumed: {})
```

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `limits` | `Hash{Symbol=>Numeric}` | `{}` | Per-dimension ceilings. A dimension **absent** here is unlimited |
| `consumed` | `Hash{Symbol=>Numeric}` | `{}` | Starting consumption, e.g. restored from a prior session |

`Robot` uses the dimensions `:tokens` and `:cost`, but the ledger is generic —
any Symbol works.

### limits / consumed

```ruby
ledger.limits    # => { tokens: 10_000, cost: 0.5 }
ledger.consumed  # => { tokens: 3_412, cost: 0.081 }
```

Actual consumption so far, per dimension. `consumed` is backed by a
`Hash.new(0)`, so an untouched dimension reads `0` rather than `nil`.

### reserve!

```ruby
ledger.reserve!(:tokens, 6_588)
```

Claim `amount` against the remaining budget.

**Raises `RobotLab::BudgetExceeded`** — `"budget exceeded for tokens: 10588 > 10000"`
— when `consumed + already_reserved + amount` would exceed the limit. A **no-op
that never raises** for a dimension with no configured limit.

### reconcile!

```ruby
ledger.reconcile!(:tokens, reserved_amount, actual_amount)
```

Release `reserved_amount` from the reservation pool and add `actual_amount` to
`consumed`. The actual may be larger or smaller than what was reserved. The
reservation pool is floored at zero, so an over-release cannot make it negative.

### release!

```ruby
ledger.release!(:tokens, amount)
```

Drop a reservation **without** recording consumption — for work that was reserved
and then skipped.

### remaining

```ruby
ledger.remaining(:tokens)  # => Numeric
ledger.remaining(:unmetered)  # => Float::INFINITY
```

`limit - consumed - reserved`, floored at `0`. Returns `Float::INFINITY` for a
dimension with no configured limit.

---

## RobotLab::DoomLoopDetector

Detects a model stuck calling the same tool — or the same *cycle* of tools — over
and over. `Robot#run` installs one on every call; see
[Doom Loop Detection](core/robot.md#doom-loop-detection).

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `DEFAULT_THRESHOLD` | `3` | Repetitions before a loop is declared |
| `MAX_PERIOD` | `10` | Longest cyclic pattern searched for |

### Constructor / sequence

```ruby
detector = RobotLab::DoomLoopDetector.new(threshold: 3)
detector.sequence  # => Array<String> — every tracked name, in order
```

### track

```ruby
detector.track("search")  # => the sequence array
```

Append a tool name (coerced with `to_s`). Call once per tool invocation.

### doom_loop?

```ruby
detector.doom_loop?  # => Boolean
```

`true` when either pattern is present in the tail of the sequence:

- **Consecutive** — the last `threshold` entries are all the same name (`A, A, A`).
- **Cyclic** — the last `threshold × period` entries are exactly `period`-length
  pattern repeated `threshold` times (`A,B,C, A,B,C, A,B,C`), for any period from
  2 up to `min(MAX_PERIOD, sequence.length / threshold)`.

Always `false` while fewer than `threshold` calls have been tracked.

### warning_message

```ruby
detector.warning_message  # => String
```

The self-correction text embedded in the tool result. `""` for an empty sequence.
Consecutive loops name the tool; cyclic loops render the pattern as
`"A → B → C"`. Both close with the same advice to try a fundamentally different
approach or ask for clarification.

### reset

```ruby
detector.reset  # => []
```

Clear the sequence. `Robot` calls this immediately after emitting a warning, so
the same loop is reported once rather than on every subsequent call.

!!! note "The detector never raises"
    It only appends a warning to the tool's result — a `String` result gets
    `"\n\n⚠️ <warning>"`, a `Hash` result gains a `:_doom_loop_warning` key. To
    make a loop *fatal*, use `max_tool_rounds:` and its `ToolLoopError`.

---

## RobotLab::HistoryCompressor

The algorithm behind [`robot.compress_history`](core/robot.md#compress_history)
and `auto_compact: :context_window`. Requires the optional `classifier` gem
(`~> 2.3`).

### Constructor

```ruby
RobotLab::HistoryCompressor.new(
  messages:, recent_turns:, keep_threshold:, drop_threshold:, summarizer:
)
```

All five are **required** keywords — the defaults you see documented
(`recent_turns: 3`, `keep_threshold: 0.6`, `drop_threshold: 0.2`,
`summarizer: nil`) live on `Robot#compress_history`, not here.

**Raises `ArgumentError`** when `keep_threshold <= drop_threshold`.

### call

```ruby
compressed = compressor.call  # => Array — the new message array
```

Returns the input **unchanged** — without requiring the `classifier` gem — in any
of these cases: no messages; nothing scorable; the scorable messages all fit
inside the recent window (`scorable.size <= recent_turns * 2`); or the recent
window yields no text long enough to build a reference vector.

Otherwise, it builds a mean term-frequency vector from the recent window and
scores each older message against it:

| Score | Action |
|-------|--------|
| `>= keep_threshold` | Kept verbatim |
| `drop_threshold ... keep_threshold` | Passed to `summarizer`; **dropped** when there is no summarizer, or the summary comes back blank |
| `< drop_threshold` | Dropped |
| text shorter than `MIN_SCORE_LENGTH` (20 chars) | Kept — too short to score reliably |

**Pinned messages are never scored or removed:** system messages, `:tool` and
`:tool_result` messages, and any assistant message with blank content (a tool-call
dispatcher — removing one would orphan its `tool_result`).

Scoring uses **stemmed term frequencies without IDF**. IDF on a topic-focused
corpus suppresses exactly the shared terms that signal relevance, so it would
invert the ranking.

### MIN_SCORE_LENGTH

```ruby
RobotLab::HistoryCompressor::MIN_SCORE_LENGTH  # => 20
```

### SUMMARY_STRUCT

A minimal `Struct(:role, :content, :tool_calls, :stop_reason)` that duck-types
enough of `RubyLLM::Message` to sit in a chat's message array: `text?` (always
`true`), `tool_use?` (always `false`), `system?`, `user?`, `assistant?`. A
summarized message keeps its **original role**, so user/assistant turn ordering
survives compression.

---

## RobotLab::Convergence

Whether two texts have converged on the same conclusion — for skipping a
reconciler call when two verifiers already agree. Requires the `classifier` gem.

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `DEFAULT_THRESHOLD` | `0.85` | Similarity at or above which texts are convergent |
| `MIN_TEXT_LENGTH` | `30` | Characters; shorter texts always score `0.0` |

### detected?

```ruby
RobotLab::Convergence.detected?(text_a, text_b, threshold: 0.85)  # => Boolean
```

**Raises `ArgumentError`** when `threshold` is outside `[0.0, 1.0]`, and
`RobotLab::DependencyError` when the `classifier` gem is missing.

### similarity

```ruby
RobotLab::Convergence.similarity(text_a, text_b)  # => Float in [0.0, 1.0]
```

Stemmed term-frequency cosine similarity. Returns `0.0` when **either** text is
shorter than `MIN_TEXT_LENGTH` after stripping — so two short but identical
strings score zero, not one.

---

## RobotLab::TextAnalysis

The shared TF/TF-IDF primitives that `Convergence`, `HistoryCompressor`,
`Robot#search_history`, and `MCP::ServerDiscovery` all sit on. Module functions.

| Method | Returns | Description |
|--------|---------|-------------|
| `require_classifier!` | — | Loads the `classifier` gem, converting `LoadError` into a `RobotLab::DependencyError` with install instructions. Call it before any other method |
| `load_classifier_gem` | — | The bare `require "classifier"`, extracted for testability |
| `fit(corpus)` | `Classifier::TFIDF` | Fit a TF-IDF model (`min_df: 1`) over an Array of document strings |
| `transform(model, text)` | `Hash{Symbol=>Float}` | L2-normalized sparse term vector; `{}` when no known terms |
| `cosine_similarity(vec_a, vec_b)` | `Float` in `[0.0, 1.0]` | Dot product (vectors are already normalized), clamped at `1.0`; `0.0` if either is empty |
| `dot(vec_a, vec_b)` | `Float` | Dot product over shared keys only |
| `l2_normalize(vec)` | `Hash{Symbol=>Float}` | Normalize a sparse vector; `{}` when the magnitude is zero |
| `tf_cosine_similarity(text_a, text_b)` | `Float` in `[0.0, 1.0]` | Stemmed term-frequency cosine between two texts — no reference corpus needed, which is why it, not TF-IDF, is used for 2-text comparison |

Only `tf_cosine_similarity` calls `require_classifier!` for you; the others assume
the gem is already loaded.

---

## RobotLab::DelegationFuture

The promise returned by `robot.delegate(to:, task:, async: true)`. See
[Robot: delegate](core/robot.md#delegate).

### Attributes

```ruby
future.robot_name    # => "analyst"  — the delegatee
future.delegated_by  # => "manager"  — the delegator
```

### resolved?

```ruby
future.resolved?  # => Boolean
```

`true` once the task finished, **whether it succeeded or raised**. Use it to poll
without blocking.

### value / wait

```ruby
result = future.value               # blocks indefinitely
result = future.value(timeout: 30)  # blocks up to 30s
result = future.wait                # alias for value
```

Returns the delegatee's `RobotResult`, with `duration` and `delegated_by` already
set by `delegate`.

**Raises `RobotLab::DelegationFuture::DelegationTimeout`** (`"Delegation to 'X'
timed out after Ns"`) when `timeout:` expires, and **re-raises** whatever the
delegated task raised. The error is re-raised on every subsequent `value` call —
the future stays in its failed state.

### resolve! / reject!

```ruby
future.resolve!(robot_result)
future.reject!(exception)
```

Called by `Robot#delegate` from the worker thread to settle the future; both
broadcast to every blocked `value`. You would only call these when building a
custom delegation path — settling a future twice silently overwrites the first
outcome.

---

## RobotLab::RobotMessage

Immutable `Data` envelope for TypedBus inter-robot messaging.

### build

```ruby
msg = RobotLab::RobotMessage.build(id: 1, from: "alice", content: "Hello")
reply = RobotLab::RobotMessage.build(id: 2, from: "bob", content: "Hi",
                                     in_reply_to: "alice:1")
```

Prefer `build` over `new` — it defaults `in_reply_to` to `nil`, which
`Data.define` does not do for you.

| Member | Type | Description |
|--------|------|-------------|
| `id` | `Integer` | The **sender's** per-robot counter, not globally unique |
| `from` | `String` | Sender's robot name, which is also its channel name |
| `content` | `String`, `Hash` | The payload |
| `in_reply_to` | `String`, `nil` | The `key` of the message being answered |

### key / reply?

```ruby
msg.key      # => "alice:1"  — "#{from}:#{id}"
msg.reply?   # => !in_reply_to.nil?
```

`key` is the composite identity used for reply correlation: pass it as
`in_reply_to:` when answering, and the sender's `outbox[key]` entry flips to
`status: :replied`. `reply?` is what lets `respond_to_tasks` ignore replies and
avoid an infinite ping-pong between two robots.

---

## RobotLab::BusPoller

Serializes bus deliveries per robot. A `Network` creates one and shares it across
its tasks; a robot with a bus but no network auto-creates a private one.

!!! warning "Despite the name, there is no poller thread"
    `start` and `stop` are **no-ops**, `running?` is hard-coded `true`, and
    `enqueue` processes and drains **inline in the caller's own execution
    context** (Async fiber or OS thread). All the class owns is a mutex and a
    per-robot queue. Deliveries make no progress on their own while the calling
    fiber is parked.

### QUEUE_CAPACITY

```ruby
RobotLab::BusPoller::QUEUE_CAPACITY  # => 512
```

Capacity of each robot's `RactorQueue` of pending deliveries.

### enqueue

```ruby
poller.enqueue(robot:, delivery:, group: :default)  # => void
```

If the robot is idle, marks it busy and processes the delivery immediately, then
drains anything that queued up behind it. If the robot is already processing, the
delivery is pushed onto its queue instead.

Errors are contained: a `BusError` (or any `StandardError`) from a handler
releases the robot's busy flag and is logged at `warn` rather than propagating to
the publisher.

### add_group / groups

```ruby
poller.add_group(:slow)  # idempotent
poller.groups            # => [:default, :slow]
```

Poller groups are **informational labels only** — they create no separate queues
or threads. `Network#task`'s `poller_group:` registers the name here so slow
robots are identifiable in logs and monitoring.

### start / stop / running?

```ruby
poller.start     # => self  (no-op)
poller.stop      # => self  (no-op; accepts and ignores any args)
poller.running?  # => true  (always)
```

Retained for API symmetry with the earlier threaded design.

---

## RobotLab::Waiter

The blocking primitive behind `memory.get(key, wait:)`. Built on an `IO.pipe`
pair rather than a `ConditionVariable`, because `IO#wait_readable` yields
correctly to the Async fiber scheduler while `ConditionVariable#wait` can block
the whole event loop.

| Method | Returns | Description |
|--------|---------|-------------|
| `Waiter.new` | `Waiter` | Allocates the pipe pair |
| `wait(timeout: nil)` | value, or `:timeout` | Blocks until signaled. `nil` timeout waits forever. Returns immediately when already signaled. A closed pipe (`IOError`) also yields `:timeout` |
| `signal(value)` | — | Stores `value` and wakes every waiter, writing one byte per blocked thread (minimum one, to cover a thread that passed the signaled check but has not yet entered the wait) |
| `signaled?` | `Boolean` | Whether `signal` has been called |
| `close` | — | Releases both file descriptors. Call after `wait` returns |

Multiple threads may wait on one instance. `Memory#wait_for_key` handles the
create/wait/close lifecycle and converts a `:timeout` return into
`RobotLab::AwaitTimeout`.

---

## RobotLab::Narrator

The one `RobotLab::Hook` subclass shipped in core: a human-facing console feed of
what a robot is doing, complementing the persistent record kept by
`robot_lab-audit`. See
[Live Narration](../guides/observability.md#live-narration-robotlabnarrator).

### enable!

```ruby
RobotLab::Narrator.enable!                  # narrate to $stderr
RobotLab::Narrator.enable!(output: $stdout)
# => the Narrator class, so it chains
```

Sets the output and registers the narrator **globally** via `RobotLab.on(self)`.
For finer scope, skip `enable!` and register it like any other hook:
`robot.on(RobotLab::Narrator)` or `network.on(RobotLab::Narrator)` — but set
`Narrator.output` yourself first if you do not want `$stderr`.

### output / output=

```ruby
RobotLab::Narrator.output = $stdout
RobotLab::Narrator.output  # => IO, defaulting to $stderr
```

Narration is written with `IO#puts`, not `Kernel#warn` — `warn` is silenced when
`$VERBOSE` is `nil`, which is common under `bundle exec`.

### MAX

```ruby
RobotLab::Narrator::MAX  # => 80
```

Characters before a narrated line is clipped with an ellipsis.

### Hook methods

| Hook | Output |
|------|--------|
| `before_llm_generation(ctx)` | `  · <robot>: thinking…` |
| `before_tool_call(ctx)` | `  · → <tool_name> <first_arg>="<clipped value>"` |
| `after_tool_call(ctx)` | `  ·   ✗ <clipped error message>` — **only when the call raised** |

All three rescue `StandardError` and return `nil`, so narration can never break a
run.

---

## RobotLab::Config

`RobotLab.config` — a `MywayConfig::Base` subclass. For the settings themselves,
file locations, and precedence rules, see
[Configuration](../getting-started/configuration.md).

| Method | Returns | Description |
|--------|---------|-------------|
| `logger` | `Logger` | The configured logger. Defaults to `Rails.logger` under Rails, else `Logger.new($stdout, level: Logger::INFO)` |
| `logger=` | — | Runtime-only; not read from any config file |
| `development?` / `test?` / `production?` | `Boolean` | Current-environment predicates, from `MywayConfig::Base` |
| `after_load` | `void` | Applies the `ruby_llm:` section to RubyLLM and points `prompt_manager` at the resolved template path. `RobotLab.config` calls it once on first construction |
| `apply_ruby_llm_config!` | `void` | Just the RubyLLM half of `after_load` — provider API keys and endpoints, OpenAI org/project options, default models, connection/retry settings, and logging options. Call it after mutating `config.ruby_llm` at runtime to push the change into RubyLLM |

```ruby
RobotLab.configure { |c| c.ruby_llm.request_timeout = 300 }
RobotLab.config.apply_ruby_llm_config!   # <- otherwise RubyLLM keeps the old value
```

API keys fall back to the standard provider environment variables
(`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `AWS_ACCESS_KEY_ID`, …) when the
corresponding config key is unset, so the `ROBOT_LAB_RUBY_LLM__` prefix is
optional for credentials.

---

## RobotLab::MCP::ServerDiscovery

Narrows a configured MCP server list to the ones relevant to the current message,
so a robot with many servers connects only what it needs. Activated with
`mcp_discovery: true` — see [MCP Integration](../guides/mcp-integration.md).

### DEFAULT_THRESHOLD

```ruby
RobotLab::MCP::ServerDiscovery::DEFAULT_THRESHOLD  # => 0.05
```

Deliberately low: server descriptions are a sentence long, so cosine scores are
small even for a clearly on-topic query.

### select

```ruby
RobotLab::MCP::ServerDiscovery.select(query, from: servers, threshold: 0.05)
# => Array<Hash, MCP::Server>
```

**Returns `from` unchanged** — connecting everything — whenever discovery cannot
make a confident call: an empty list, a blank query, no server carrying a
`description`, no server scoring at or above `threshold`, or the `classifier` gem
not being installed (`DependencyError` is rescued, not propagated). Discovery can
therefore only ever *narrow* a run, never break one.

### score / topic_text / description_for / any_descriptions?

```ruby
ServerDiscovery.score(query, server)      # => Float — tf cosine vs. topic_text
ServerDiscovery.topic_text(server)        # => "github GitHub repos, issues, ..."
ServerDiscovery.description_for(server)   # => String ("" when absent)
ServerDiscovery.any_descriptions?(servers) # => Boolean
```

All four accept either a config `Hash` (`server[:name]`, `server[:description]`)
or an `MCP::Server` instance. `topic_text` is `"<name> <description>"` — the name
participates in matching, so a well-named server scores even with a thin
description.

---

## RobotLab::MCP::ConnectionPoller

Multiplexes I/O across multiple **stdio** MCP transports with a single
`IO.select` loop, instead of each client blocking independently behind its own
`Timeout.timeout`. Async-based transports (SSE, WebSocket, StreamableHTTP) are
unaffected — they already yield to the fiber scheduler. See
[Transports](mcp/transports.md).

Unlike [`BusPoller`](#robotlabbuspoller), this one **does** own a background
thread.

### POLL_INTERVAL

```ruby
RobotLab::MCP::ConnectionPoller::POLL_INTERVAL  # => 0.1  (seconds)
```

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `start` | `self` | Spawn the multiplexing thread (named `RobotLab::MCP::ConnectionPoller`). Idempotent |
| `stop(timeout: 5)` | `self` | Stop the thread and cancel every pending request with an `MCPError`. Idempotent |
| `running?` | `Boolean` | Whether the thread is live |
| `register(client)` | — | Add the client's `transport.stdout` to the select set. **Silently ignores a non-stdio client** |
| `unregister(client)` | — | Remove it; likewise a no-op for non-stdio clients |
| `send_request(client, message, timeout:)` | response | Write `message.to_json` to the client's stdin and block on that client's queue for the matching response. `timeout:` is required |

```ruby
poller = RobotLab::MCP::ConnectionPoller.new.start
client = RobotLab::MCP::Client.new(server_config, poller: poller)
client.connect
# ...
poller.stop
```

---

## RobotLab::Streaming::SequenceCounter

Thread-safe monotonic counter for event ordering.

| Method | Returns | Description |
|--------|---------|-------------|
| `SequenceCounter.new(start: 0)` | `SequenceCounter` | |
| `next` | `Integer` | Increment and return the new value |
| `current` | `Integer` | Read without incrementing |
| `reset(value = 0)` | `Integer` | Set the counter |

!!! warning "Nothing in the framework uses this"
    Its only consumer is `Streaming::Context`, which core itself never
    constructs. See [Streaming](streaming/index.md) for what actually streams.

---

## See Also

- [Core Classes](core/index.md) — `Robot`, `Network`, `Memory`, `Tool`, `RobotResult`
- [Hooks API](hooks.md) — the extension seam these classes are wired into
- [Skills API](skills.md) — `AgentSkill`, `Capabilities`, `ScriptTool` (confinement lives in the optional `robot_lab-sandbox` gem)
- [Errors](errors.md) — including `Errors.retryable?` and `Errors.retryable_classes`
