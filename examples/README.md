# RobotLab Examples

Working demonstrations of RobotLab features, from single-robot basics to multi-robot orchestration and message bus communication.

## Prerequisites

- Ruby >= 3.2
- `bundle install` (from the project root)
- An LLM API key (e.g., `ANTHROPIC_API_KEY`)

## Running Examples

```bash
# Run a specific example by number
bundle exec rake examples:run[1]

# Run all examples
bundle exec rake examples:all

# Run directly
bundle exec ruby examples/01_simple_robot.rb
```

## Directory Structure

```
examples/
  01_simple_robot.rb          # Basic robot with template
  02_tools.rb                 # Robot with custom tools
  03_network.rb               # Multi-robot network with routing
  04_mcp.rb                   # MCP server integration (GitHub)
  05_streaming.rb             # Real-time streaming events
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
  19_token_tracking.rb        # Per-robot token & cost tracking
  20_circuit_breaker.rb       # Tool loop circuit breaker with max_tool_rounds
  21_learning_loop.rb         # Learning accumulation across runs with robot.learn
  22_context_compression.rb   # Context window compression with HistoryCompressor
  23_convergence.rb           # Debate convergence detection and reconciler fast-path
  24_structured_delegation.rb # Structured delegation with duration and token tracking
  25_history_search.rb        # Semantic search over a robot's conversation history
  26_document_store.rb        # Embedding-based document store (RAG) via fastembed
  18_rails/                   # Minimal Rails 8 demo app (full integration)
    app/robots/chat_robot.rb  #   Robot factory with system prompt + TimeTool
    app/tools/time_tool.rb    #   Custom RobotLab::Tool subclass
    app/jobs/robot_run_job.rb #   Background job with Turbo Stream callbacks
    app/controllers/          #   Chat controller (index + create)
    app/views/                #   Layout with CDN importmap, chat view with streaming
    app/models/               #   RobotLabThread, RobotLabResult
    config/                   #   Minimal Rails 8 config (async adapters, no asset pipeline)
    db/migrate/               #   Migration from generator template
  prompts/                    # Prompt templates (.md with YAML front matter)
```

## Examples

### 01 — Simple Robot

Create and run a basic robot using a prompt template. Sends a single message and displays the response.

**Requires:** LLM API key

### 02 — Tools

Give a robot custom tools (`Calculator`, `FortuneCookie`) defined as `RubyLLM::Tool` subclasses. The LLM decides when to call each tool based on the user's request.

**Requires:** LLM API key

### 03 — Multi-Robot Network

Build a customer support network with a classifier robot that routes requests to billing, technical, or general specialists. Uses SimpleFlow's optional task activation for conditional routing.

**Requires:** LLM API key

### 04 — MCP Integration

Connect to the GitHub MCP server via stdio transport. Part 1 demonstrates direct `MCP::Client` usage (listing tools, calling `search_repositories`). Part 2 wraps the MCP server inside a robot for natural-language queries.

**Requires:** LLM API key, `GITHUB_PERSONAL_ACCESS_TOKEN`, `github-mcp-server` installed

### 05 — Streaming

Real-time streaming of robot responses using `RobotLab::Streaming::Context`. Simulates text deltas with timing to demonstrate the streaming event model, then shows the code pattern for streaming with a robot or network.

**Requires:** None (simulated events, no LLM calls)

### 06 — Prompt Templates

Full e-commerce support system using prompt_manager templates with YAML front matter. A triage robot classifies customer requests and routes to order, product, or escalation specialists. Demonstrates build-time context (company info, policies) and run-time context (customer data, order history).

**Requires:** LLM API key

### 07 — Network Memory

Reactive shared memory with concurrent robots. Multiple analysis robots (sentiment, entity extraction, keywords) run in parallel and write to shared memory. A synthesizer robot waits for all results using blocking reads, then produces a combined analysis. Demonstrates subscriptions, notifications, and network broadcast.

**Requires:** LLM API key

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

**Requires:** LLM API key

### 13 — Spawning Robots

Dynamic specialist creation at runtime. A dispatcher robot receives questions, asks its LLM what kind of specialist is needed, then uses `spawn` to create one on the fly. The bus is created lazily on the first spawn — no explicit bus setup required. Spawned specialists are reused across questions of the same type.

Demonstrates: `spawn` for dynamic robot creation, lazy bus creation, `on_message` for reply handling, LLM-driven delegation.

**Requires:** LLM API key

### 14 — The Rusty Circuit (Open Mic Night)

A comedy club where three robots interact through a shared message bus. A comedian performs stand-up armed with self-modification tools (style reinvention, energy adjustment, coaching). A heckler reacts from the audience — heckling weak material, telling counter-jokes with the comic as the punch line, showing grudging respect, or staying silent when a bit doesn't warrant a response. A talent scout observes silently, spawning specialist analysts and refining evaluation criteria before delivering a final verdict.

Terminal output is color-formatted: comic bits in cyan (left-aligned), heckler reactions in yellow (right-indented), tool annotations dimmed. Scout notes go to `scout_notes.md` instead of STDOUT. The final verdict appears in green on both STDOUT and the scout file.

Demonstrates: Robot subclasses, self-modification via tool side effects, dynamic spawning (`spawn`), shared `:room` channel + personal channels, processing guards for async serialization, `[SILENCE]` opt-out pattern, style reinvention via user-prompt injection.

**Requires:** LLM API key

### 19 — Token & Cost Tracking

Track token usage across runs using `result.input_tokens` / `result.output_tokens` for per-run counts and `robot.total_input_tokens` / `robot.total_output_tokens` for running totals. Demonstrates `reset_token_totals` to start a fresh batch and includes a simple cost estimate using per-provider pricing constants.

**Requires:** LLM API key

### 20 — Tool Loop Circuit Breaker

Guards against runaway tool call loops using `max_tool_rounds:`. A step processor tool is designed to always return "more steps remain", which would loop indefinitely without a guard. The circuit breaker fires after the configured limit and raises `RobotLab::ToolLoopError`. Shows how to rescue the error gracefully and confirms the robot is fully reusable after a breaker trip.

**Requires:** LLM API key

### 21 — Learning Accumulation Loop

Builds up cross-run observations with `robot.learn(text)`. A code reviewer accumulates one key insight after each review. On subsequent runs, learnings are automatically prepended to the user message as a "LEARNINGS FROM PREVIOUS RUNS:" block. Demonstrates bidirectional substring deduplication (broader learnings replace narrower ones), the `robot.learnings` accessor, and how learnings survive a robot rebuild via the shared `Memory` object.

**Requires:** LLM API key

### 22 — Context Window Compression

Demonstrates `robot.compress_history()` for reducing token usage in long conversations. Old turns are scored against the recent context using stemmed term-frequency cosine similarity (via the `classifier` gem). High-relevance turns are kept verbatim; irrelevant turns are dropped; medium-relevance turns can optionally be summarized by a second robot. Shows both drop-mode and summarizer-lambda patterns, plus the LLM summarizer integration recipe.

**Requires:** `gem 'classifier', '~> 2.3'` in your Gemfile (no LLM calls in the demo itself)

### 24 — Structured Delegation

A manager robot delegates sub-tasks to a summarizer and an analyst. Each `delegate()` call returns a `RobotResult` annotated with `delegated_by`, `duration`, and token counts. Includes a comparison table of when to use delegation vs. bus messaging vs. pipelines.

**Requires:** LLM API key

### 23 — Debate Convergence Detection

Demonstrates `RobotLab::Convergence` for detecting when two independent agents have reached the same conclusion. Scores pairs of texts from identical → semantically similar → partially related → unrelated, showing how the similarity metric varies. Includes the router fast-path pattern: when two verifier robots agree above a threshold, the expensive reconciler LLM call is skipped entirely.

**Requires:** `gem 'classifier', '~> 2.3'` in your Gemfile (no LLM calls in the demo itself)

### 24 — Structured Delegation

Demonstrates `robot.delegate(to:, task:)` for synchronous and asynchronous inter-robot delegation. The manager robot delegates document analysis to a summarizer and an analyst. Shows synchronous (sequential, blocking) and asynchronous (parallel fan-out, `DelegationFuture`) modes with wall-time comparison.

**Requires:** LLM API key

### 25 — Chat History Search

Demonstrates `robot.search_history(query, limit:)` — semantic search over accumulated conversation turns using stemmed TF cosine similarity. No LLM calls: messages are injected directly. Shows relevance ranking, role preservation, short-message filtering, and the `DependencyError` guard.

**Requires:** `gem 'classifier', '~> 2.3'` in your Gemfile (no LLM calls)

### 26 — Embedding-Based Document Store

Demonstrates `memory.store_document(key, text)` and `memory.search_documents(query, limit:)` — a lightweight RAG store using `fastembed` (BAAI/bge-small-en-v1.5). Documents are embedded once; queries are compared by cosine similarity at search time. Includes the `RobotLab::DocumentStore` standalone API and a RAG pattern sketch showing how to pass retrieved context to a robot.

**Requires:** `fastembed` gem (already a core dependency); downloads the ~23 MB ONNX model on first run (cached in `~/.cache/fastembed/`)

### 18 — Rails Integration Demo

A minimal, hand-built Rails 8 app that exercises every piece of RobotLab's Rails integration end-to-end. No `rails new` — every file is hand-crafted for minimum size.

**What it demonstrates:**
- **ChatRobot** with a custom `TimeTool` (`app/robots/`, `app/tools/`)
- **RobotRunJob** — background execution via `ActiveJob` async adapter
- **Turbo Stream token streaming** — real-time content chunks broadcast to the browser over ActionCable
- **Persistence** — `RobotLabThread` + `RobotLabResult` with conversation history
- **Auto-scrolling chat** — MutationObserver keeps the view pinned to the latest streaming content

**No Redis, no Solid Queue, no asset pipeline.** Uses `:async` adapters for both ActiveJob and ActionCable. Turbo JS loaded via importmap from CDN (`@hotwired/turbo-rails`).

```bash
cd examples/18_rails
bin/setup              # bundle install + db:create + db:migrate
bin/dev                # starts Puma on http://localhost:3000
```

**Requires:** LLM API key, Ruby 3.2+

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
