# RobotLab Examples

Working demonstrations of RobotLab features, from single-robot basics to multi-robot orchestration and message bus communication.

## Prerequisites

- Ruby >= 3.2
- `bundle install` (from the project root)
- [Ollama](https://ollama.com) running locally with the demo model pulled:

  ```bash
  ollama serve
  ollama pull qwen3.6
  ```

Every example runs against a **local** model — no API keys, no egress, no
per-token cost. The model, provider and endpoint are set in one place,
`examples/common.rb`:

```ruby
LLM = {
  default: LlmConfig.new(provider: "ollama", model: "qwen3.6:latest"),
  small:   LlmConfig.new(provider: "ollama", model: "qwen2.5:7b"),
  large:   LlmConfig.new(provider: "ollama", model: "llama3.3:latest")
}
```

Robots pick it up with the `llm_opts` helper:

```ruby
robot = RobotLab.build(name: "helper", **llm_opts)        # default model
cheap = RobotLab.build(name: "helper", **llm_opts(:small)) # smaller model
```

`provider:` is not optional here. Ollama models are absent from RubyLLM's
model registry, so passing `model:` alone raises `RubyLLM::ModelNotFoundError`
— supplying `provider:` is what makes RubyLLM skip the registry lookup. Note
also that `RunConfig` has no `provider` field, so provider and model travel
together on the robot even when other settings come from a shared `RunConfig`.

`common.rb` also raises `request_timeout` to 900s. A 20B+ model on consumer
hardware routinely takes longer than robot_lab's 120s default on a long
answer, which otherwise surfaces mid-example as `Net::ReadTimeout`. Override
with `LLM_REQUEST_TIMEOUT`.

## Runtime: pick your model with `LLM_PROFILE`

Every example is a *sequence* of LLM calls, so wall-clock is dominated by
`calls × seconds-per-call`. On `qwen3.6:latest` expect roughly **60-70s per
call**. That is fine for the single-robot examples and painful for the
multi-robot ones:

| Example | LLM calls | `qwen3.6:latest` | `LLM_PROFILE=small` |
|---------|-----------|------------------|---------------------|
| 01, 02, 19, 20 | 1-6 | seconds to ~5 min | fast |
| 03, 06, 07, 24, 27, 31 | 4-8 | ~5-10 min | ~2 min |
| 13, 14, 15 | ~20-30 | **30-40 min** | ~5-10 min |
| 16 | unbounded (600s cap) | usually hits the cap | often completes |

`LLM_PROFILE` switches the model for any example without editing it:

```bash
LLM_PROFILE=small bundle exec ruby examples/14_rusty_circuit/open_mic.rb
```

Valid values are the keys of `LLM` in `common.rb`: `default`, `small`, `large`.

**Long silences are not hangs.** In example 14 the scout writes its notes to
`output/scout_notes.md` rather than STDOUT, and a scout turn is 1-4 sequential
calls — minutes of blank terminal. The `· Scout …` lines exist so you can tell
progress from a stall. Example 16 is the same idea at larger scale: writers
coordinate through shared memory, and much of the work shows up in
`output/room.log` rather than on screen.

## Running Examples

```bash
# Run a specific example by number
bundle exec rake examples:run[1]

# Run all examples
bundle exec rake examples:all

# Run directly
bundle exec ruby examples/01_simple_robot.rb
```

## Tools require `tools: :inherit` at run time

This trips up everyone once. `Robot#run` defaults to `tools: :none`, which
means *"send zero tools this turn"* — the robot still holds them in
`local_tools`, but the provider never sees them and the model answers from
memory instead of calling anything:

```ruby
robot = RobotLab.build(name: "bot", **llm_opts, local_tools: [Calculator])

robot.run("What is 15 * 7?")                  # Calculator is NEVER offered
robot.run("What is 15 * 7?", tools: :inherit) # Calculator is offered
```

The same applies to MCP (`mcp: :inherit`), to network tasks
(`task :name, robot, tools: :inherit`), and to anything that forwards keywords
into `run` — including `RobotLab::RailsIntegration::Job`. Examples 02, 04, 06,
14, 15, 16, 20, 33 and the Rails app all pass it explicitly.

## Directory Structure

```
examples/
  common.rb                   # Shared LLM config (Ollama), llm_opts, output helpers
  xyzzy.rb                    # Single-file hook extension used by 35
  01_simple_robot.rb          # Basic robot with template
  02_tools.rb                 # Robot with custom tools
  03_network.rb               # Multi-robot network with routing
  04_mcp.rb                   # MCP server integration (GitHub)
  05_streaming.rb             # Real-time streaming callbacks
  06_prompt_templates.rb      # Template-based e-commerce support
  07_network_memory.rb        # Shared memory with concurrent robots
  08_llm_config.rb            # Configuration hierarchy demo
  09_chaining.rb              # with_* method chaining & reconfiguration
  10_memory.rb                # Advanced Memory API operations
  11_network_introspection.rb # Network visualization & inspection
  12_message_bus.rb           # Bidirectional robot communication
  13_spawn.rb                 # Dynamic specialist robot spawning
  14_rusty_circuit/           # Multi-robot open mic with self-modification
    open_mic.rb               #   Main entrypoint — wires up the show
    comic.rb                  #   Comedian with self-modification tools
    heckler.rb                #   Audience heckler (can stay silent or counter-joke)
    scout.rb                  #   Talent scout with analyst spawning
    display.rb                #   Terminal formatting (color, wrapping, file output)
    prompts/                  #   Templates for comic, heckler, and scout
  15_memory_network_and_bus/  # Network + memory + bus + spawn in one pipeline
    editorial_pipeline.rb     #   Main entrypoint — three writers, editor, chief
  16_writers_room/            # Self-organizing group: no orchestration at all
    writers_room.rb           #   Main entrypoint — book and screenplay modes
  17_skills.rb                # Composable skills, flat and recursive
  18_rails/                   # Minimal Rails 8 demo app (full integration)
    app/robots/chat_robot.rb  #   Robot factory with system prompt + TimeTool
    app/tools/time_tool.rb    #   Custom RobotLab::Tool subclass
    app/jobs/robot_run_job.rb #   Background job with Turbo Stream callbacks
    app/controllers/          #   Chat controller (index + create)
    app/views/                #   Layout with CDN importmap, chat view with streaming
    app/models/               #   RobotLabThread, RobotLabResult
    config/                   #   Minimal Rails 8 config (async adapters, no asset pipeline)
    db/migrate/               #   Migration from generator template
  19_token_tracking.rb        # Per-robot token & cost tracking
  20_circuit_breaker.rb       # Tool loop circuit breaker with max_tool_rounds
  21_learning_loop.rb         # Learning accumulation across runs with robot.learn
  22_context_compression.rb   # Context window compression with HistoryCompressor
  23_convergence.rb           # Debate convergence detection and reconciler fast-path
  24_structured_delegation.rb # Structured delegation with duration and token tracking
  25_history_search.rb        # Semantic search over a robot's conversation history
  26_document_store.rb        # Embedding-based document store (RAG) via fastembed
  27_incident_response/       # BusPoller, reactive memory, poller groups
    incident_response.rb      #   Main entrypoint — wires up the war room
  28_mcp_discovery.rb         # Semantic MCP server selection before connecting
  29_ractor_tools.rb          # Ractor-safe tools: worker pool, freeze_deep, parallel batch
  30_ractor_network.rb        # Ractor network scheduler: dependency waves, parallel_mode
  31_launch_assessment.rb     # 6 parallel analysts, max_concurrent_robots: 4 semaphore cap
  32_newsletter_reader.rb     # Utility script (no RobotLab) — RSS to Markdown
  33_stock_generator.rb       # Companion publisher for 33_stock_predictor (Redis)
  33_stock_predictor.rb       # Durable cross-session learning via robot_lab-durable
  34_agentskills.rb           # AgentSkills.io folder-format skills, matched per run
  35_hooks.rb                 # Hook architecture demo using xyzzy.rb
  prompts/                    # Prompt templates (.md with YAML front matter)
```

## Examples

### 01 — Simple Robot

Create and run a basic robot using a prompt template. Sends a single message and displays the response.

**Requires:** Ollama

### 02 — Tools

Give a robot custom tools (`Calculator`, `FortuneCookie`) defined as `RubyLLM::Tool` subclasses. The LLM decides when to call each tool based on the user's request.

**Requires:** Ollama

### 03 — Multi-Robot Network

Build a customer support network with a classifier robot that routes requests to billing, technical, or general specialists. Uses SimpleFlow's optional task activation for conditional routing.

**Requires:** Ollama

### 04 — MCP Integration

Connect to the GitHub MCP server via stdio transport. Part 1 demonstrates direct `MCP::Client` usage (listing tools, calling `search_repositories`). Part 2 wraps the MCP server inside a robot for natural-language queries.

**Requires:** Ollama, `GITHUB_PERSONAL_ACCESS_TOKEN`, `github-mcp-server` installed

### 05 — Streaming

Real-time streaming of robot responses through four routes: the stored `on_content:` callback wired at build time, a per-call block passed to `run()`, both together (stored fires first, then the block), and `on_content` arriving through a `RunConfig`.

**Requires:** Ollama (makes four live calls)

### 06 — Prompt Templates

Full e-commerce support system using prompt_manager templates with YAML front matter. A triage robot classifies customer requests and routes to order, product, or escalation specialists. Demonstrates build-time context (company info, policies) and run-time context (customer data, order history).

**Requires:** Ollama

### 07 — Network Memory

Reactive shared memory with concurrent robots. Multiple analysis robots (sentiment, entity extraction, keywords) run in parallel and write to shared memory. A synthesizer robot waits for all results using blocking reads, then produces a combined analysis. Demonstrates subscriptions, notifications, and network broadcast.

**Requires:** Ollama

### 08 — LLM Configuration

Walks through the full configuration hierarchy without making LLM calls:

1. Bundled defaults
2. Environment-specific overrides
3. XDG user config
4. Project config
5. Environment variables
6. Template front matter
7. Constructor parameters
8. `with_*` method chaining
9. Run-time context

**Requires:** None (no LLM calls)

### 09 — Chaining & Reconfiguration

Demonstrates the Robot API surface for runtime configuration: `with_*` method chaining, `update()` for reconfiguration, `to_h` introspection, config diffs between steps, and how constructor params override template front matter.

**Requires:** None (no LLM calls)

### 10 — Advanced Memory

Comprehensive Memory API demo: `StateProxy` for method-style access, key and pattern subscriptions, `MemoryChange` objects, key enumeration, serialization round-trips, clone for isolated copies, delete with reserved key protection, and clear vs reset.

**Requires:** None (no LLM calls)

### 11 — Network Introspection

Network visualization and inspection tools: `to_mermaid()` for diagram export, `to_dot()` for Graphviz, `execution_plan()` for text output, `visualize()` for ASCII pipelines, robot access by name, dynamic `add_robot()`, `to_h()` introspection, task-specific config, and `broadcast()`.

**Requires:** None (no LLM calls)

### 12 — Message Bus

Bidirectional robot communication via TypedBus. A comedy critic (Alice) tasks a comedian (Bob) to tell robot jokes. Alice evaluates each joke with her LLM; if it's not funny, she sends Bob back for another attempt. Bob's temperature ramps from 0.2 to 1.0 across retries for increasing creativity. The loop continues until Alice approves or `MAX_ATTEMPTS` is reached.

Demonstrates: Robot subclasses, prompt templates, auto-ack `on_message`, `reply()` convenience, temperature ramping, convergence patterns.

**Requires:** Ollama

### 13 — Spawning Robots

Dynamic specialist creation at runtime. A dispatcher robot receives questions, asks its LLM what kind of specialist is needed, then uses `spawn` to create one on the fly. The bus is created lazily on the first spawn — no explicit bus setup required. Spawned specialists are reused across questions of the same type.

Demonstrates: `spawn` for dynamic robot creation, lazy bus creation, `on_message` for reply handling, LLM-driven delegation.

**Requires:** Ollama

### 14 — The Rusty Circuit (Open Mic Night)

A comedy club where three robots interact through a shared message bus. A comedian performs stand-up armed with self-modification tools (style reinvention, energy adjustment, coaching). A heckler reacts from the audience — heckling weak material, telling counter-jokes with the comic as the punch line, showing grudging respect, or staying silent when a bit doesn't warrant a response. A talent scout observes silently, spawning specialist analysts and refining evaluation criteria before delivering a final verdict.

Terminal output is color-formatted: comic bits in cyan (left-aligned), heckler reactions in yellow (right-indented), tool annotations dimmed. Scout notes go to `scout_notes.md` instead of STDOUT. The final verdict appears in green on both STDOUT and the scout file.

Demonstrates: Robot subclasses, self-modification via tool side effects, dynamic spawning (`spawn`), shared `:room` channel + personal channels, `enqueue_delivery` for serializing async deliveries, `[SILENCE]` opt-out pattern, style reinvention via user-prompt injection.

**Requires:** Ollama. The most expensive example in the suite — ~30 LLM calls, 30+ minutes on `qwen3.6`. Use `LLM_PROFILE=small` to watch it in under ten.

### 15 — Memory, Network, Bus & Spawn Together

An editorial pipeline where three writers advocate for macOS, Windows, and Linux/BSD as a home AI research lab platform. The network runs the writers in parallel and hands their drafts to an editor through shared memory; the Linux writer spawns three distro specialists mid-pipeline; an editor-in-chief outside the pipeline reviews the combined article over the bus and can demand revisions.

Demonstrates: all four coordination mechanisms in one program, plus the direct `shared_memory` reference pattern that parallel pipeline steps need (`extract_run_context` deletes from a shared hash, so only the first parallel step would otherwise see `network_memory`).

**Requires:** Ollama

### 16 — The Writers' Room (Self-Organizing Group)

A team of identical writer robots produces a 10-chapter novella with no orchestration, no pipeline, and no assigned roles. Each writer subscribes to a `:room` broadcast channel and a personal channel, and has tools to read/write shared memory, broadcast, DM, spawn more writers, and mark the work complete. The script seeds the room with an assignment and waits.

`--screenplay-from output/memory.json` re-runs the room in screenplay mode, adapting a finished book into a 4-act TV movie pilot at scene granularity.

Demonstrates: emergent coordination, `clear_messages(keep_system: true)` as a per-message conversation reset, dynamic team growth, memory as the single source of truth.

**Requires:** Ollama (long-running — `--timeout` defaults to 600s)

### 17 — Composable Skills

Skills are ordinary templates whose bodies are prepended to the main template. An SRE incident responder is composed from `runbook_protocol` and `structured_output` (flat skills) plus `sre_compliance`, which recursively expands to `pii_redactor` and `audit_trail`. The assembled system prompt is printed line-by-line so the depth-first expansion order is visible, and a skill-less robot is built alongside it for size comparison.

**Requires:** Ollama

### 19 — Token & Cost Tracking

Track token usage across runs using `result.input_tokens` / `result.output_tokens` for per-run counts and `robot.total_input_tokens` / `robot.total_output_tokens` for running totals. Demonstrates `reset_token_totals` to start a fresh batch. Local inference is free, so cost is reported as `$0.00000 (local)`; set `RATE_INPUT_CPM` / `RATE_OUTPUT_CPM` to price the same traffic against a hosted provider.

**Requires:** Ollama

### 20 — Tool Loop Circuit Breaker

Guards against runaway tool call loops using `max_tool_rounds:`. A step processor tool is designed to always return "more steps remain", which would loop indefinitely without a guard. The circuit breaker fires after the configured limit and raises `RobotLab::ToolLoopError`. Shows how to rescue the error gracefully and confirms the robot is fully reusable after a breaker trip.

**Requires:** Ollama

### 21 — Learning Accumulation Loop

Builds up cross-run observations with `robot.learn(text)`. A code reviewer accumulates one key insight after each review. On subsequent runs, learnings are automatically prepended to the user message as a "LEARNINGS FROM PREVIOUS RUNS:" block. Demonstrates bidirectional substring deduplication (broader learnings replace narrower ones), the `robot.learnings` accessor, and how learnings survive a robot rebuild via the shared `Memory` object.

**Requires:** Ollama

### 22 — Context Window Compression

Demonstrates `robot.compress_history()` for reducing token usage in long conversations. Old turns are scored against the recent context using stemmed term-frequency cosine similarity (via the `classifier` gem). High-relevance turns are kept verbatim; irrelevant turns are dropped; medium-relevance turns can optionally be summarized by a second robot. Shows both drop-mode and summarizer-lambda patterns, plus the LLM summarizer integration recipe.

**Requires:** `gem 'classifier', '~> 2.3'` in your Gemfile (no LLM calls in the demo itself)

### 23 — Debate Convergence Detection

Demonstrates `RobotLab::Convergence` for detecting when two independent agents have reached the same conclusion. Scores pairs of texts from identical → semantically similar → partially related → unrelated, showing how the similarity metric varies. Includes the fast-path pattern: a gate robot compares two verifiers' replies and only activates the expensive reconciler — via SimpleFlow optional-task activation — when they disagree.

**Requires:** `gem 'classifier', '~> 2.3'` in your Gemfile (no LLM calls in the demo itself)

### 24 — Structured Delegation

Demonstrates `robot.delegate(to:, task:)` for synchronous and asynchronous inter-robot delegation. The manager robot delegates document analysis to a summarizer and an analyst. Shows synchronous (sequential, blocking) and asynchronous (parallel fan-out, `DelegationFuture`) modes with wall-time comparison. Each result carries `delegated_by`, `duration`, and token counts.

**Requires:** Ollama

### 25 — Chat History Search

Demonstrates `robot.search_history(query, limit:)` — semantic search over accumulated conversation turns using stemmed TF cosine similarity. No LLM calls: messages are injected directly. Shows relevance ranking, role preservation, short-message filtering, and the `DependencyError` guard.

**Requires:** `gem 'classifier', '~> 2.3'` in your Gemfile (no LLM calls)

### 26 — Embedding-Based Document Store

Demonstrates `memory.store_document(key, text)` and `memory.search_documents(query, limit:)` — a lightweight RAG store using `fastembed` (BAAI/bge-small-en-v1.5). Documents are embedded once; queries are compared by cosine similarity at search time. Includes the `RobotLab::DocumentStore` standalone API and a RAG pattern sketch showing how to pass retrieved context to a robot.

**Requires:** `robot_lab-document_store` gem (`gem "robot_lab-document_store"` in your Gemfile); downloads the ~23 MB ONNX model on first run (cached in `~/.cache/fastembed/`)

### 27 — Production Incident War Room

Three SRE scout robots investigate a payment-service outage in parallel — database layer, network layer, and application layer. Each scout stores its findings in shared reactive memory and broadcasts a status update to a war-room coordinator via TypedBus.

Demonstrates all four Phase 5 infrastructure improvements together:

| Feature | How it shows up |
|---------|----------------|
| **IO.pipe Waiter** (#13) | Commander blocks on `memory.get(:db_finding, :net_finding, :app_finding, wait: 60)`; wakes the instant the last scout writes its key |
| **BusPoller** (#14) | All three scouts send bus messages to the war room; BusPoller serializes delivery so war_room processes them one at a time, in arrival order, with no dropped messages |
| **Poller Groups** (#15) | Scout tasks labeled `poller_group: :investigation`; commander task labeled `poller_group: :command`; group list printed before the run |
| **Reactive Memory** | `memory.subscribe` callbacks fire in real-time as each scout writes, while the blocking waiter runs independently |

**Run:**
```bash
bundle exec ruby examples/27_incident_response/incident_response.rb
# or
bundle exec rake examples:run[27]
```

**Requires:** Ollama

### 28 — MCP Server Discovery

When a robot has many MCP servers configured, connecting to all of them upfront is wasteful. `mcp_discovery: true` enables semantic server selection: before the first connection, `MCP::ServerDiscovery` scores each server's `name + description` against the user query using TF cosine similarity and connects only the relevant subset.

Demonstrates: `MCP::ServerDiscovery.select(query, from:, threshold:)`, the `description:` field on MCP server configs, `mcp_discovery: true` on Robot, and all four fallback cases (no descriptions, blank query, classifier unavailable, no match above threshold).

**Requires:** None (no LLM calls — exercises the discovery module directly)

### 29 — Ractor-Safe CPU Tools

Demonstrates Track 1 of RobotLab's Ractor parallelism: CPU-bound tool classes that
bypass the GVL by routing through a pool of Ractor workers.

| Section | What it shows |
|---------|--------------|
| `ractor_safe?` flags | `WordStatsTool`, `ReadabilityTool`, `HeavyDigestTool` inherit `ractor_safe true` from `TextTool`; `RequestCounterTool` (mutable class variable) does not |
| `RactorBoundary.freeze_deep` | Deep-freezes nested hashes/arrays; raises `RactorBoundaryError` on `StringIO` |
| Single pool submit | Direct `RobotLab.ractor_pool.submit(class_name, args)` calls |
| `ToolError` propagation | `nil.scan(...)` inside a Ractor worker → `NoMethodError` → `RobotLab::ToolError` |
| Parallel batch | 6 threads each submitting a `HeavyDigestTool` job (5 000 SHA-256 rounds) simultaneously vs sequentially; speedup visible on multi-core hardware |

**Requires:** None (no LLM calls)

### 30 — Ractor Network Scheduler

Demonstrates Track 2 of RobotLab's Ractor parallelism: running a multi-robot
pipeline under `parallel_mode: :ractor`, which dispatches independent tasks in
true parallel waves and respects `depends_on` ordering.

Pipeline topology (4 robots):
```
headline_finder  ──┐
background_brief ──┼──► report_writer
fact_checker     ──┘
```
Wave 1 (headline_finder + background_brief + fact_checker) runs in parallel;
Wave 2 (report_writer) runs after all three complete.

**Part 1** — `SimulatedScheduler` (overrides `execute_spec` with `sleep`) shows
wave ordering and timing without any API calls.  Expected: ~1.3 s parallel vs 2.2 s sequential.

**Part 2** — Walks through `Network.new(parallel_mode: :ractor)` configuration
and the `pipeline.step_dependencies` dependency graph inspection.

**Part 3** — Live LLM run (enabled automatically when `ANTHROPIC_API_KEY` is set).

**Requires:** None for Parts 1 & 2. `RUN_LIVE=1` plus Ollama for Part 3 (expected to fail — ruby_llm is not Ractor-safe yet).

### 31 — Product Launch Assessment (Concurrency Cap)

Six specialist robots evaluate a product launch simultaneously: market, competitive, technical, risk, financial, and legal analysts. `RunConfig.new(max_concurrent_robots: 4)` caps the `Async::Semaphore` at 4 in-flight LLM calls — robots 5 and 6 queue until a slot opens. A `LaunchDirector` reads all six findings from shared reactive memory and issues a GO / NO-GO recommendation. Start timestamps in the output make the semaphore behavior visible.

Demonstrates: `max_concurrent_robots:` on `RunConfig`, `Async::Semaphore` back-pressure via `simple_flow`, six parallel `depends_on: :none` tasks, shared memory writes and blocking reads.

**Requires:** Ollama

### 32 — Newsletter Reader

A plain utility script that fetches unprocessed issues from Ruby newsletter RSS feeds and saves them as Markdown. **It uses no part of RobotLab** — it lives here as a content feeder for other experiments, not as a capability demo. Set `CLIPPINGS_DIR` to choose the output folder.

**Requires:** `html2markdown` on `PATH`

### 33 — Durable Cross-Session Learning

`33_stock_generator.rb` publishes synthetic XYZZY prices to a Redis channel using geometric Brownian motion. `33_stock_predictor.rb` consumes them, predicts each window's high/low with an SMA + EMA ensemble, and after every window asks a tuner robot to adjust the predictor's parameters.

The tuner uses `robot_lab-durable`. Note the API: `learn:` / `learn_domain:` are **not** constructor parameters (`Robot#initialize` takes a fixed keyword list with no `**rest`, so passing them raises `ArgumentError`). Call `robot.setup_durable_learning(domain:)` after `build`, which seeds `robot.learnings` from `~/.robot_lab/durable/<domain>.yml` and appends the `RecallKnowledge` / `RecordKnowledge` tools. Core `Robot#run` does not invoke the reflector, so the caller drives `robot.run_reflector` to promote learnings back to the store.

Run the two scripts in separate terminals.

**Requires:** Ollama, Redis on localhost:6379, `robot_lab-durable`

### 34 — AgentSkills.io Integration

Skills declared as `skills: [:code_reviewer]` are resolved from `~/.prompts/skills/<name>/SKILL.md` and matched per-run by embedding similarity — a code-review question activates the skill, an unrelated question does not. Run the two queries and compare.

**Requires:** Ollama, `robot_lab-document_store` gem, a `SKILL.md` at `~/.prompts/skills/code_reviewer/`

### 35 — Hooks Architecture

Loads `xyzzy.rb`, a single-file `RobotLab::Hook` subclass that registers for every hook and logs each callback with the context it receives. Demonstrates robot run, LLM generation, tool call, network run, task, and error hooks. Stubs `robot.chat.ask` for the deterministic sections; the LLM-generation section makes four real calls to show `around_llm_generation` serving two of them from a cache.

`RobotLab::Hook` has no logger accessor — handlers own their output. `xyzzy.rb` freezes its log destination from `XYZZY_LOG_PATH` at load time, so the env var must be set before the `require`.

**Requires:** Ollama (four calls in the LLM-loop section)

### 18 — Rails Integration Demo

A minimal, hand-built Rails 8 app that exercises every piece of RobotLab's Rails integration end-to-end. No `rails new` — every file is hand-crafted for minimum size.

**What it demonstrates:**
- **ChatRobot** with a custom `TimeTool` (`app/robots/`, `app/tools/`)
- **RobotRunJob** — background execution via `ActiveJob` async adapter
- **Turbo Stream token streaming** — real-time content chunks broadcast to the browser over ActionCable
- **Persistence** — `RobotLabThread` + `RobotLabResult` with conversation history
- **Auto-scrolling chat** — MutationObserver keeps the view pinned to the latest streaming content

**No Redis, no Solid Queue, no asset pipeline.** Uses `:async` adapters for both ActiveJob and ActionCable. Turbo JS loaded via importmap from CDN (`@hotwired/turbo-rails`).

**Two API details worth copying:** the job's superclass is `RobotLab::RailsIntegration::Job` (there is no `RobotLab::Job` alias), and the controller enqueues with `tools: :inherit` so that keyword reaches `robot.run` — otherwise `TimeTool` is never offered and the model guesses the time.

```bash
cd examples/18_rails
bin/setup              # bundle install + db:create + db:migrate
bin/dev                # starts Puma on http://localhost:3000
```

**Requires:** Ollama, Ruby 3.2+

## Prompt Templates

Templates live in `examples/prompts/` as `.md` files with YAML front matter. Each template defines a robot's personality and behavior:

```markdown
---
description: Simple helpful assistant
temperature: 0.7
parameters:
  company_name: null
---
You are a helpful assistant for <%= company_name %>.
```

Front matter keys like `model`, `temperature`, `top_p`, `max_tokens` are applied to the robot's chat automatically. Parameters with `null` values are required and must be provided via `context:` at build time.

### Template Inventory

| Template | Used By | Description |
|----------|---------|-------------|
| `helper.md` | 01 | Simple helpful assistant |
| `assistant.md` | 02 | Assistant with tool access |
| `classifier.md` | 03 | Request classifier (billing/technical/general) |
| `billing.md` | 03 | Billing specialist |
| `technical.md` | 03 | Technical support specialist |
| `general.md` | 03 | General support |
| `github_assistant.md` | 04 | GitHub-aware assistant |
| `triage.md` | 06 | E-commerce request triage |
| `order_support.md` | 06 | Order inquiry specialist |
| `product_support.md` | 06 | Product questions specialist |
| `escalation.md` | 06 | Complex issue handler |
| `sentiment_analyzer.md` | 07 | Sentiment analysis |
| `entity_extractor.md` | 07 | Entity extraction |
| `keyword_extractor.md` | 07 | Keyword extraction |
| `synthesizer.md` | 07 | Multi-source synthesis |
| `llm_config_demo.md` | 08 | Configuration demo |
| `configurable.md` | 09 | Configurable template with front matter |
| `comedian.md` | 12 | Robot joke teller |
| `comedy_critic.md` | 12 | Joke evaluator (FUNNY/NOT_FUNNY) |
| `dispatcher.md` | 13 | Specialist role dispatcher |
| `open_mic_comic.md` | 14 | Observational comedian with self-modification |
| `open_mic_heckler.md` | 14 | Tough audience heckler (can stay silent or counter-joke) |
| `open_mic_scout.md` | 14 | Talent scout with analyst recruitment |
| `os_advocate.md` | 15 | Operating-system advocacy writer |
| `os_editor.md` | 15 | Synthesizes the three advocacy drafts |
| `os_chief.md` | 15 | Editor-in-chief (APPROVED / REVISE) |
| `writer.md` | 16 | Self-organizing novella writer |
| `screenplay_writer.md` | 16 | Self-organizing screenplay writer |
| `incident_responder.md` | 17 | SRE on-call analyst (main template) |
| `runbook_protocol.md` | 17 | Flat skill: 5-step incident protocol |
| `structured_output.md` | 17 | Flat skill: JSON response format |
| `sre_compliance.md` | 17 | Recursive skill: bundles the two leaves below |
| `pii_redactor.md` | 17 | Leaf skill: redact PII |
| `audit_trail.md` | 17 | Leaf skill: audit metadata |

Templates matching `*_test.md` are fixtures for the test suite, not examples.

Templates for 14, 15 and 16 live in those examples' own `prompts/` directories; each entrypoint sets `ROBOT_LAB_TEMPLATE_PATH` before requiring `common.rb`.
