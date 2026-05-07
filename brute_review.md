# Review: `brute` Ruby Gem

**Source:** https://github.com/general-intelligence-systems/brute
**License:** MIT
**Status:** Very early stage, not yet on RubyGems, 0 stars
**Reviewed:** 2026-05-05

---

## What It Is

`brute` is a production-grade **coding agent framework** for Ruby. It enables LLM-powered automation of coding tasks — autonomous agents that can read/write files, run shell commands, fetch URLs, and self-manage their context over long multi-step sessions.

Built on `llm.rb` (~> 4.11), **not** `ruby_llm`. These are distinct, incompatible gems.

---

## Runtime Dependencies

- `llm.rb (~> 4.11)` — core LLM abstraction (distinct from `ruby_llm`)
- `async (~> 2.0)` — concurrent tool execution
- `diff-lcs (>= 1.5)` — unified diffs for file patching
- `scampi` — small utility gem
- Ruby >= 3.2

---

## Core Architecture

| Class | Purpose |
|---|---|
| `Brute::Agent` | Thin config struct: `provider`, `model`, `tools`, `system_prompt` |
| `Brute::Pipeline` | Rack-style middleware chain; built with `use`/`run` DSL |
| `Brute::Loop::AgentTurn` | The main agentic loop (up to 100 iterations) |
| `Brute::Store::Session` | JSON-file-based session persistence in `~/.brute/sessions/UUID/` |
| `Brute::Store::SnapshotStore` | Copy-on-write file snapshots enabling undo |
| `Brute::Store::TodoStore` | Persistent todo list for task tracking |
| `Brute::Skill` | Markdown+YAML skill loader from `.brute/skills/` or `~/.config/brute/skills/` |
| `Brute::SystemPrompt` | Provider-aware system prompt builder with composable prompt modules |
| `Brute::Providers` | Environment-variable-based provider auto-detection |

### Middleware Pipeline (ordered)

`OTel → Tracing → Retry → SessionPersistence → MessageTracking → TokenTracking → CompactionCheck → ToolErrorTracking → DoomLoopDetection → ReasoningNormalizer → ToolUseGuard → LLMCall`

Each middleware wraps the next, Rack-style. Fully extensible by inheriting from `Brute::Middleware::Base`.

---

## Built-in Tools (12 total)

| Tool | Purpose |
|---|---|
| `FSRead` | Read file contents |
| `FSWrite` | Write files |
| `FSPatch` | Exact-string patch (old_string → new_string, with snapshot before write) |
| `FSRemove` | Delete files |
| `FSSearch` | Search the filesystem |
| `FSUndo` | Revert a file to its pre-patch snapshot |
| `Shell` | Execute shell commands |
| `NetFetch` | HTTP fetch |
| `TodoRead` | Read the todo list |
| `TodoWrite` | Write/update the todo list |
| `Delegate` | Delegate subtasks to sub-agents |
| `Question` | Ask the user a question (runs synchronously, not in parallel) |

Tool execution strategy: `Question` runs sequentially on the current fiber; all other tools run in parallel via `Brute::Queue::ParallelQueue`. File mutations go through a separate `FileMutationQueue` to prevent conflicts.

---

## Notable Features

### 1. Doom Loop Detection

Analyzes tool call signatures at the tail of the message history. Detects both:
- Consecutive identical calls (`A,A,A`)
- Cycling multi-step patterns (`A,B,C,A,B,C`)

Default threshold: 3 repetitions. On detection, injects a warning prompt into context asking the LLM to try a fundamentally different approach.

**Source:** `lib/brute/loop/doom_loop.rb` — pure Ruby, no external deps, easily extracted.

### 2. Context Compaction

Triggers when: messages > 200 OR estimated tokens > 100,000. Keeps the 6 most recent messages, summarizes the rest via an LLM call into 4 sections:
- Goal
- Progress
- Current State
- Next Steps

Default summary model: `claude-sonnet-4-20250514`.

### 3. Session Persistence

Sessions stored as JSON files in `~/.brute/sessions/UUID/` with:
- Individual `msg_NNNN.json` files per message
- `context.json`
- `session.meta.json`

Resumable by ID. `Session.list` returns sessions sorted newest-first.

### 4. Skills System

Markdown files with YAML frontmatter (`name`, `description`, body content). Discovery order:
1. `.brute/skills/` (project-local, higher priority)
2. `~/.config/brute/skills/` (global)

Formatted as XML and injected into the system prompt. Local-overrides-global pattern is clean.

### 5. Provider-Aware System Prompts

`lib/brute/prompts/text/*/` has provider-specific variants of prompt sections (identity, doing_tasks, tool_usage, tone_and_style) for Anthropic, OpenAI, Google, and a default. Composable: each section is a separate Ruby module.

### 6. Multi-Provider Support (9 providers)

Anthropic, OpenAI, Google, DeepSeek, Ollama, XAI, OpenCode Zen, OpenCode Go, Shell. Environment-variable-based auto-detection via `Brute::Providers.detect`.

### 7. OpenTelemetry Integration

Optional `opentelemetry-sdk` support with span/token/tool-call tracking middleware built in.

### 8. File Undo / Snapshot Store

`FSPatch` takes a copy-on-write snapshot before writing; `FSUndo` reverts to the pre-patch state. Snapshots live in `Brute::Store::SnapshotStore`.

### 9. Todo Store

Persistent todo list tracked across agent turns in `Brute::Store::TodoStore`. Useful for long-running multi-step workflows.

---

## Basic Usage Pattern

```ruby
agent = Brute::Agent.new(
  provider: Brute::Providers.detect,
  model: "claude-sonnet-4-20250514",
  tools: Brute::Tools::ALL,
  system_prompt: "You are a helpful coding assistant."
)

session = Brute::Store::Session.new
pipeline = Brute::Pipeline.new { run Brute::Middleware::LLMCall.new }

step = Brute::Loop::AgentTurn.perform(
  agent: agent,
  session: session,
  pipeline: pipeline,
  input: "Read app.rb and fix any bugs"
)

puts step.state == :completed ? step.result.content : step.error
```

---

## Applicability to Your Projects

| Project | Relevance | Key Ideas |
|---|---|---|
| **RobotLab** | High (patterns) | Doom loop detection, context compaction, middleware checklist, skills discovery |
| **AIA** | High (patterns) | Session persistence, provider auto-detection, doom loop detection |
| **Direct dependency** | Not recommended | Conflicts with `ruby_llm` via `llm.rb` dependency |

### RobotLab — Moderate/High Relevance (Patterns Only)

`brute` uses `llm.rb` while RobotLab is built on `ruby_llm`. They are not compatible at the dependency level. However, specific concepts are worth borrowing:

- **Doom Loop Detection** — RobotLab robots that call tools in loops could benefit from this exact pattern. The algorithm is straightforward to port to `lib/robot_lab/loop/` or as middleware in the pipeline.
- **Context Compaction** — RobotLab's `Memory` system could integrate a compaction step triggered by token count, summarizing older messages and preserving a recency window.
- **Skills System** — `brute`'s local-overrides-global discovery is a clean enhancement to RobotLab's existing template/prompt system.
- **File Undo / Snapshot Store** — Relevant if RobotLab robots are given file-editing tools.
- **Middleware Checklist** — The ordered middleware pipeline is a useful reference for production hardening: retry, token tracking, doom loop detection, compaction check are all cross-cutting concerns RobotLab's `SimpleFlow::Pipeline` doesn't currently address.
- **Todo Store** — Persistent todo tracking across agent turns is useful for long-running RobotLab workflows.

### AIA — High Relevance (Patterns Only)

- Session persistence with UUID-based JSON storage is directly applicable
- Provider auto-detection via environment variables is clean and battle-tested
- The `Question` tool pattern (synchronous, blocking) mirrors AIA's interactive mode
- Doom loop detection and context compaction are both relevant for long CLI sessions

---

## Recommendation

**Do not add as a gem dependency** — `llm.rb` conflicts with `ruby_llm` and the gem is pre-release/source-only.

**Port these two algorithms to RobotLab:**
1. **Doom loop detector** (`lib/brute/loop/doom_loop.rb`) — pure Ruby, no external deps, directly extractable
2. **Compaction threshold logic** — >200 messages or >100k tokens → summarize keeping last 6 — fits naturally into `Memory` or `Network` layer

The middleware pipeline checklist is also a useful reference for what production hardening looks like in a mature agent framework.
