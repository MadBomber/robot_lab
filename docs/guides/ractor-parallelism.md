# Ractor Parallelism

RobotLab supports true CPU parallelism via Ruby Ractors — isolated execution contexts that bypass the Global VM Lock (GVL). This guide explains how to put both CPU-bound tools and multi-robot pipelines on parallel hardware threads.

## Why Ractors?

Ruby's standard thread model is I/O-concurrent but CPU-serialized: the GVL means only one thread runs Ruby code at a time. For LLM workflows this is usually fine — robots spend most of their time waiting on the network. But some workloads benefit from real parallel execution:

- **CPU-intensive tools** — text processing, image analysis, embeddings, cryptography
- **Independent robot pipelines** — multiple robots working on unrelated subtasks simultaneously

Ractors bypass the GVL entirely. Each Ractor runs on its own OS thread with no shared mutable state, so multiple Ractors genuinely execute in parallel on multi-core hardware.

## Architecture Overview

RobotLab provides two parallel tracks:

```
┌─────────────────────────────────────────────────────┐
│                   Your Application                   │
├─────────────────────────────┬───────────────────────┤
│   Track 1: CPU-bound Tools  │  Track 2: Robots       │
│                             │                        │
│  Tool#ractor_safe           │  Network               │
│      ↓                      │  parallel_mode: :ractor│
│  RactorWorkerPool           │      ↓                 │
│  (N Ractor workers)         │  RactorNetworkScheduler│
│                             │  (N Ractor workers)    │
├─────────────────────────────┴───────────────────────┤
│           Shared Infrastructure                      │
│   RactorBoundary · RactorJob · RactorMemoryProxy     │
└─────────────────────────────────────────────────────┘
```

**Track 1** routes Ractor-safe tools through a global worker pool instead of calling them inline. The robot never notices — it still gets back a result string.

**Track 2** replaces the `SimpleFlow::Pipeline` executor for a network with a `RactorNetworkScheduler` that dispatches frozen robot specs to Ractor workers, respecting `depends_on` ordering.

Both tracks share the same frozen-data convention: all values crossing a Ractor boundary must be Ractor-shareable.

---

## Track 1: CPU-Bound Tools

### Declaring a Tool as Ractor-Safe

Add `ractor_safe true` to any `RubyLLM::Tool` or `RobotLab::Tool` subclass:

```ruby
class TranscribeAudio < RubyLLM::Tool
  ractor_safe true

  description "Transcribe an audio file to text"

  param :path,   type: :string, desc: "Absolute path to the audio file"
  param :format, type: :string, desc: "Audio format (wav, mp3, ogg)", required: false

  def execute(path:, format: "wav")
    # Pure computation — no shared mutable state, no IO closures
    AudioTranscriber.run(path, format: format)
  end
end
```

When a robot calls this tool, RobotLab automatically routes the call through the global `RactorWorkerPool` rather than executing it inline. The robot is unaffected — it receives the result string as normal.

`ractor_safe` is inherited. If you declare it on a base class, all subclasses are also treated as Ractor-safe:

```ruby
class BaseAudioTool < RubyLLM::Tool
  ractor_safe true
end

class TranscribeAudio < BaseAudioTool  # also ractor_safe
  # ...
end

class DetectLanguage < BaseAudioTool   # also ractor_safe
  # ...
end
```

### What Makes a Tool Ractor-Safe?

A tool is safe to run inside a Ractor when its `execute` method:

- Uses only **frozen or locally-created** objects
- Does **not** read or write class-level mutable state (class variables, module-level globals)
- Does **not** hold references to closures, Procs, or lambdas defined outside the Ractor
- Does **not** use non-Ractor-safe C extensions (most pure-Ruby code is fine)

```ruby
# Safe: all inputs arrive as frozen args; result is fresh
class HashContent < RubyLLM::Tool
  ractor_safe true
  description "SHA-256 hash of a string"
  param :text, type: :string, desc: "Text to hash"

  def execute(text:)
    require "digest"
    Digest::SHA256.hexdigest(text)
  end
end

# Not safe: reads and writes @@cache (shared mutable state)
class CachedLookup < RubyLLM::Tool
  @@cache = {}  # mutable class variable — NOT Ractor-safe

  def execute(key:)
    @@cache[key] ||= expensive_lookup(key)
  end
end
```

### Configuring the Worker Pool

The global pool is created lazily on first use. You can control its size through `RunConfig`:

```ruby
RobotLab.configure do |config|
  config.ractor_pool_size = 8  # default: Etc.nprocessors
end
```

Or per-robot / per-network via `RunConfig`:

```ruby
config = RobotLab::RunConfig.new(ractor_pool_size: 4)
robot  = RobotLab.build(name: "cruncher", config: config, ...)
```

Access the shared pool directly:

```ruby
pool = RobotLab.ractor_pool       # RactorWorkerPool instance
RobotLab.shutdown_ractor_pool     # graceful shutdown (poison-pill pattern)
```

---

## Track 2: Parallel Robot Networks

### Enabling Ractor Mode

Pass `parallel_mode: :ractor` when creating a network:

```ruby
network = RobotLab.create_network(name: "analysis", parallel_mode: :ractor) do
  task :fetch,     fetcher_robot,    depends_on: :none
  task :sentiment, sentiment_robot,  depends_on: [:fetch]
  task :entities,  entity_robot,     depends_on: [:fetch]
  task :summarize, summary_robot,    depends_on: [:sentiment, :entities]
end

result = network.run(message: "Analyze customer feedback")
```

When `parallel_mode: :ractor` is set, `Network#run` delegates to `RactorNetworkScheduler` instead of the default `SimpleFlow::Pipeline` executor. The default is `:async` (unchanged behavior).

### How It Works

The scheduler builds a `RobotSpec` — a frozen, Ractor-shareable description — for each robot in the network, then dispatches them in dependency order:

1. **Partition** tasks into waves: tasks whose dependencies are all resolved are dispatched together.
2. **Each wave** spawns one thread per task; each thread submits a `RactorJob` to the shared work queue and blocks on the per-job reply queue.
3. **Worker Ractors** pop jobs, construct a fresh `Robot` from the spec, call `robot.run(message)`, and push the frozen result string back.
4. **LLM calls** (ruby_llm) always happen in threads — Ractors hand off network I/O naturally since the thread is doing the blocking.

```
Wave 1:  [ fetch ]
           ↓ result passed to next wave
Wave 2:  [ sentiment | entities ]   ← run in parallel
           ↓ both results available
Wave 3:  [ summarize ]
```

The return value of `run` is a `Hash` mapping robot name strings to their result strings:

```ruby
results = network.run(message: "Analyze this")
# => { "fetch" => "...", "sentiment" => "positive", "entities" => "...", "summarize" => "..." }
```

### Dependency Ordering

Dependency semantics mirror those of `SimpleFlow::Pipeline`:

| `depends_on` value | Meaning |
|---|---|
| `:none` | Entry-point task; dispatched in the first wave |
| `:optional` | Runs in the first wave (not blocked by anything) |
| `["task_a", "task_b"]` | Waits until both `task_a` and `task_b` complete |

```ruby
RobotLab.create_network(name: "pipeline", parallel_mode: :ractor) do
  task :ingest,    ingester,  depends_on: :none
  task :classify,  classifier, depends_on: ["ingest"]
  task :summarize, summarizer, depends_on: ["ingest"]
  task :report,    reporter,  depends_on: ["classify", "summarize"]
end
```

---

## Shared Memory Across Ractors

Robots running in Ractor workers cannot share a standard `Memory` instance directly — it contains mutable Ruby objects. RobotLab solves this with `RactorMemoryProxy`, which wraps a `Memory` via `Ractor::Wrapper`.

You typically interact with the proxy from the thread side (before and after Ractor dispatch), not from inside workers. Workers receive the frozen result string; the scheduler stores it in `completed` for subsequent waves.

For cases where you need Ractor workers to write into shared memory at runtime, use the proxy's Ractor-shareable stub:

```ruby
memory = RobotLab::Memory.new
proxy  = RobotLab::RactorMemoryProxy.new(memory)

# Pass the stub (not the proxy) into Ractor.new
Ractor.new(proxy.stub) do |mem|
  mem.set(:status, "done")
  mem.get(:status)   # => "done"
end.value

memory.get(:status)  # => "done"

proxy.shutdown
```

Values written via `set` are automatically deep-frozen before crossing the boundary.

---

## The Frozen-Data Contract

Everything that crosses a Ractor boundary must be Ractor-shareable: frozen strings, frozen hashes, frozen arrays, `Data.define` structs, and integers/symbols/nil.

`RactorBoundary.freeze_deep` recursively freezes a nested Hash/Array structure and raises `RactorBoundaryError` if it encounters something that cannot be made shareable (like a `StringIO` or a `Proc`):

```ruby
safe = RobotLab::RactorBoundary.freeze_deep({ key: "value", tags: ["a", "b"] })
# => { key: "value", tags: ["a", "b"] } (all frozen)

RobotLab::RactorBoundary.freeze_deep(StringIO.new)
# => raises RobotLab::RactorBoundaryError
```

You generally do not need to call this directly — `RactorWorkerPool#submit` and `RactorMemoryProxy#set` call it for you. But it is public if you build tooling on top.

---

## Error Handling

### Tool Errors

If a Ractor-safe tool raises inside a worker, the worker catches the error, wraps it in a `RactorJobError`, and sends it back through the reply queue. The pool unwraps it and re-raises as `RobotLab::ToolError`:

```ruby
begin
  pool.submit("MyTool", { input: "bad data" })
rescue RobotLab::ToolError => e
  puts e.message  # "Tool 'MyTool' failed in Ractor: ..."
end
```

### Robot Pipeline Errors

The scheduler raises `RobotLab::Error` if a robot fails inside a Ractor worker:

```ruby
begin
  network.run(message: "go")
rescue RobotLab::Error => e
  puts e.message  # "Robot 'summarize' failed in Ractor: ..."
end
```

### Boundary Errors

Passing unshareable data raises `RobotLab::RactorBoundaryError` before any Ractor is involved:

```ruby
begin
  pool.submit("MyTool", { io: StringIO.new })
rescue RobotLab::RactorBoundaryError => e
  puts e.message  # "Cannot make value Ractor-shareable: ..."
end
```

---

## Configuration Reference

| Parameter | Where | Default | Description |
|---|---|---|---|
| `ractor_pool_size` | `RunConfig` / global config | `Etc.nprocessors` | Worker count for `RactorWorkerPool` |
| `parallel_mode` | `Network.new` | `:async` | `:async` (SimpleFlow) or `:ractor` (RactorNetworkScheduler) |

---

## Best Practices

### 1. Profile Before Reaching for Ractors

Ractors add overhead: freezing data, queue coordination, thread synchronization. For fast tools or networks with few tasks, standard threads are often faster. Measure first.

### 2. Keep Tool State Stateless

The safest Ractor-safe tool is a pure function:

```ruby
class NormalizeText < RubyLLM::Tool
  ractor_safe true
  description "Unicode-normalize and strip a string"
  param :text, type: :string, desc: "Input text"

  def execute(text:)
    text.unicode_normalize(:nfkc).strip
  end
end
```

### 3. Freeze Tool Return Values

Tool results travel back through the reply queue — freeze them proactively to avoid the overhead of `Ractor.make_shareable`:

```ruby
def execute(id:)
  { id: id, name: "result" }.freeze
end
```

### 4. Parallel Mode Doesn't Share Robot Instances

Each Ractor worker constructs a **fresh Robot** from the frozen spec. Side-effects on the original robot objects (callbacks, in-memory state) are not visible inside workers. Use `Memory` (via `RactorMemoryProxy`) for shared state.

### 5. LLM Calls Stay in Threads

`ruby_llm` is not Ractor-safe. Workers spawn a Thread internally for each LLM call and block the Ractor fiber on the thread result. This is transparent — you don't need to do anything — but it means robot-mode Ractors are I/O-concurrent, not purely CPU-parallel.

### 6. Shut Down the Pool Cleanly

Always shut down the global pool before exiting, especially in scripts:

```ruby
at_exit { RobotLab.shutdown_ractor_pool }
```

---

## Constraints and Limitations

- **No closures across boundaries.** Procs and lambdas cannot cross Ractor boundaries. Callbacks (`on_tool_call`, `on_tool_result`) registered on the outer robot are not available inside workers.
- **No mutable class-level state.** Class variables and module globals accessed from `execute` must be frozen.
- **`parallel_mode: :ractor` returns a plain Hash**, not a `SimpleFlow::Result`. If downstream code depends on `result.context` or `result.value`, use `:async` mode.
- **Memory subscriptions don't transfer.** Subscriptions registered on the outer `Memory` before a Ractor dispatch are not triggered by writes made via `RactorMemoryProxy#set` inside workers during the run.
- **Ruby version.** Ractors require Ruby 3.0+. `Ractor#value` / `Ractor#join` are the supported APIs from Ruby 4.0 onwards (`Ractor#take` was removed).

---

## Next Steps

- [Using Tools](using-tools.md) — Tool definitions and configuration
- [Creating Networks](creating-networks.md) — Network orchestration patterns
- [Memory System](memory.md) — Shared data between robots
- [API Reference: Network](../api/core/network.md) — Complete Network API
