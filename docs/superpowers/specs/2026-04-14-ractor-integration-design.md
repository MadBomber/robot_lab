# Ractor Integration Design

**Date:** 2026-04-14
**Status:** Approved
**Gems:** `ractor_queue`, `ractor-wrapper`

## Goals

1. True CPU parallelism (GIL-bypassing) for CPU-bound tool execution
2. True CPU parallelism for parallel robot execution in Networks
3. Use `ractor_queue` as the queue backbone for both tracks
4. Use `ractor-wrapper` to expose shared `Memory` to Ractor workers
5. Deliver both tracks as independent, composable layers

## Non-Goals

- Making `ruby_llm` or the `async` gem Ractor-safe
- Replacing the existing `:async` concurrency model (it remains the default)
- Ractor-isolating `Robot` instances that are long-lived across multiple tasks

---

## Architecture Overview

Two parallel tracks share a frozen-message convention and `ractor_queue` as the communication backbone.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Thread/Fiber World                        │
│  Robot (ruby_llm, async)  ──▶  Tool.call()  ──▶  RobotResult  │
│           │                        │                             │
│     BusPoller                 ractor_safe?                       │
│    (ractor_queue)              │        │                        │
└────────────────────────────────│────────│────────────────────────┘
                                 │  yes   │  no
             ┌───────────────────┘        └──► Thread executor
             ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Ractor World                              │
│  RactorWorkerPool  ◀──ractor_queue──  frozen RactorJob          │
│  (N Ractor workers)                                              │
│         │                                                        │
│  RactorMemoryProxy  (ractor-wrapper around Memory)              │
│  ◀── get/set via Ractor messages ──▶                            │
└─────────────────────────────────────────────────────────────────┘
```

**Key constraint:** only frozen, `Ractor.shareable?` objects cross Ractor boundaries. A `RactorJob` is a `Data.define` struct (shareable by design) carrying a frozen payload and a per-job reply `ractor_queue`.

---

## Shared Infrastructure

### `RactorJob`

```ruby
RactorJob = Data.define(:id, :type, :payload, :reply_queue)
```

Single cross-boundary carrier for both tracks. `payload` must be frozen by the caller before submission. `reply_queue` is a `ractor_queue` instance (Ractor-safe).

### `RactorJobError`

```ruby
RactorJobError = Data.define(:message, :backtrace)
```

Frozen error representation for exceptions that occur inside a Ractor worker. Serialized at the Ractor boundary, re-raised on the thread side.

### `RobotSpec`

```ruby
RobotSpec = Data.define(:name, :template, :system_prompt, :config_hash)
```

Carries everything needed to reconstruct a `Robot` inside a Ractor. All fields must be frozen strings/hashes.

### `RactorBoundary`

A utility module with a `freeze_deep(obj)` method that recursively freezes nested `Hash`/`Array` structures before they cross a Ractor boundary. Similar in spirit to the existing `deep_dup` in `Utils`. Raises `RobotLab::RactorBoundaryError` (a subclass of `RobotLab::Error`) if a value cannot be made shareable (e.g., a live IO or Proc).

```ruby
module RactorBoundary
  def self.freeze_deep(obj)
    case obj
    when Hash  then obj.transform_values { freeze_deep(_1) }.freeze
    when Array then obj.map { freeze_deep(_1) }.freeze
    else            obj.frozen? ? obj : obj.dup.freeze
    end
  rescue TypeError => e
    raise RobotLab::RactorBoundaryError, "Cannot make value Ractor-shareable: #{e.message}"
  end
end
```

---

## Track 1: RactorWorkerPool (Tool CPU Parallelism)

### Tool opt-in

`RobotLab::Tool` gets a `ractor_safe` class macro (default `false`). Ractor-safe tools must be stateless — no captured mutable closures, no non-shareable constants.

```ruby
class EmbeddingTool < RobotLab::Tool
  ractor_safe true

  def execute(text:)
    # CPU-bound embedding work — runs inside a Ractor worker
  end
end
```

The framework raises `RobotLab::ConfigurationError` at class-definition time if a declared-safe tool captures unshareable state (detected via `Ractor.shareable?` check on the class object).

### `RactorWorkerPool`

A pool of N Ractor workers (configurable via `RunConfig#ractor_pool_size`, default `Etc.nprocessors`). Each worker runs:

```ruby
loop do
  job = work_queue.pop                    # blocks on ractor_queue
  result = dispatch(job)                  # instantiates tool class, calls execute
  job.reply_queue.push(result)            # frozen result back to caller
rescue => e
  job.reply_queue.push(RactorJobError.new(message: e.message, backtrace: e.backtrace))
end
```

The pool is lazily initialized on first use and shared across robots in a Network via the existing `RunConfig` hierarchy. It lives for the lifetime of the process (or the `RunConfig` that owns it). `RactorWorkerPool#shutdown` drains in-flight jobs, then closes the work `ractor_queue` so all workers exit their loops cleanly. `RunConfig` calls `shutdown` on `ObjectSpace` finalizer or explicit `RobotLab.shutdown` call.

If a worker Ractor crashes (unhandled exception kills the Ractor), the pool detects the dead Ractor via `Ractor#take` and spawns a replacement. The failed job's reply queue receives a `RactorJobError`.

### Submission path (inside `Robot#call_tool`)

1. Look up `tool_class` from `ToolManifest`
2. Check `tool_class.ractor_safe?`
3. **If yes:** `RactorBoundary.freeze_deep(args)`, build `RactorJob`, push to pool's work `ractor_queue`, block on reply queue
4. **If no:** run in current thread/fiber as today
5. On reply: if result is `RactorJobError`, re-raise as `RobotLab::ToolError` in the calling thread

### `RunConfig` additions

```ruby
ractor_pool_size: :auto   # :auto = Etc.nprocessors, or an Integer
```

---

## Track 2: RactorMemoryProxy + RactorNetworkScheduler (Robot Parallelism)

### `RactorMemoryProxy`

Wraps the existing `Memory` instance via `ractor-wrapper`. The wrapper Ractor acts as a method-dispatch server: it receives frozen messages and replies with frozen results.

Supported operations proxied across the Ractor boundary:

| Message | Reply |
|---------|-------|
| `[:get, key]` | frozen value or `nil` |
| `[:set, key, frozen_value]` | `:ok` |
| `[:keys]` | frozen array of keys |

Subscriptions (callbacks) are **not** proxied — closures are not Ractor-safe. Robots that need reactive subscriptions use the thread-side `Memory` directly. `RactorMemoryProxy` is for Ractor workers that need read/write access to shared state.

No changes to `Memory` itself.

### `RactorNetworkScheduler`

Replaces `SimpleFlow::Pipeline#call_parallel` for Networks with `parallel_mode: :ractor`. Distributes frozen task descriptions to worker Ractors, collects frozen results.

`depends_on` ordering is preserved: the scheduler reads the pipeline's existing dependency graph (from `SimpleFlow::Pipeline`) and uses it to determine which tasks are ready to dispatch. A task is submitted to the `ractor_queue` only once all its dependencies have resolved. This mirrors how `call_parallel` works today — the scheduler wraps the same topological resolution logic.

```
Scheduler  ──► ractor_queue (frozen RobotSpec + task payload)
                    │
                    ▼
              Worker Ractor
              (constructs fresh Robot from RobotSpec,
               runs task, freezes RobotResult,
               pushes to reply ractor_queue)
                    │
Scheduler  ◀── ractor_queue (frozen results)
```

Each worker Ractor constructs its own `Robot` instance from a `RobotSpec`. The LLM call happens inside the Ractor. This is safe because `ruby_llm` HTTP calls use no shared mutable state between instances — the Ractor constraint is about *shared* non-shareable objects, not fresh instances created inside a Ractor.

Results are collected via a reply `ractor_queue` and assembled into the pipeline's `SimpleFlow::Result` context on the thread side.

### `BusPoller` queue upgrade

`BusPoller#@robot_queues` changes from `Hash<String, Array>` to `Hash<String, ractor_queue>`. Delivery mechanics (mutex-guarded drain, `process_and_drain`) are unchanged — only the backing store is swapped. This makes `BusPoller` capable of receiving deliveries from Ractor workers.

### Network opt-in

```ruby
network = RobotLab.create_network(name: "analysis", parallel_mode: :ractor) do
  task :sentiment, sentiment_robot, depends_on: :none
  task :entities,  entity_robot,    depends_on: :none
  task :summarize, summary_robot,   depends_on: [:sentiment, :entities]
end
```

`parallel_mode: :async` remains the default and is unchanged.

---

## Error Handling

| Scenario | Mechanism |
|----------|-----------|
| Tool raises inside Ractor worker | Serialized as `RactorJobError`, re-raised as `RobotLab::ToolError` in calling thread |
| Robot raises inside `RactorNetworkScheduler` | Serialized as `RactorJobError`, surfaced as failed step in `SimpleFlow::Result` |
| Worker Ractor crashes (unhandled exception) | Pool detects dead Ractor, spawns replacement, failed job gets `RactorJobError` on reply queue |
| Non-shareable value submitted to pool | `RobotLab::RactorBoundaryError` raised before the Ractor boundary |

---

## Testing

- `RactorWorkerPool` is testable standalone — no Robot or Network required
- `RactorMemoryProxy` is testable standalone — wrap a `Memory`, call proxy methods from a test Ractor
- Tools that declare `ractor_safe true` should pass `assert_ractor_safe(tool_class)` — a test helper that spins up a single-worker pool and round-trips a frozen payload
- `RactorNetworkScheduler` tests use a minimal two-robot network with `parallel_mode: :ractor`
- All existing tests are unaffected — `:async` remains the default; no existing class is modified in a breaking way

---

## New Files

| File | Purpose |
|------|---------|
| `lib/robot_lab/ractor_job.rb` | `RactorJob`, `RactorJobError`, `RobotSpec` data classes |
| `lib/robot_lab/ractor_boundary.rb` | `RactorBoundary.freeze_deep` utility |
| `lib/robot_lab/ractor_worker_pool.rb` | `RactorWorkerPool` — N Ractor workers fed by `ractor_queue` |
| `lib/robot_lab/ractor_memory_proxy.rb` | `RactorMemoryProxy` — `ractor-wrapper` around `Memory` |
| `lib/robot_lab/ractor_network_scheduler.rb` | `RactorNetworkScheduler` — distributes robot tasks to Ractor workers |

## Modified Files

| File | Change |
|------|--------|
| `lib/robot_lab/tool.rb` | Add `ractor_safe` class macro |
| `lib/robot_lab/robot.rb` | Check `ractor_safe?` in `call_tool`, submit to pool if true |
| `lib/robot_lab/run_config.rb` | Add `ractor_pool_size:` field |
| `lib/robot_lab/bus_poller.rb` | Swap `Array` queues for `ractor_queue` instances |
| `lib/robot_lab/network.rb` | Add `parallel_mode:` option, delegate to `RactorNetworkScheduler` |
| `lib/robot_lab/error.rb` | Add `RobotLab::RactorBoundaryError` subclass |
| `lib/robot_lab.rb` | Require new files |

---

## Dependencies to Add

```ruby
gem "ractor_queue"
gem "ractor-wrapper"
```
