# `agentf` Gem Analysis

**Repository:** https://github.com/nealdeters/agentf
**Author:** Neal Deters
**Ruby:** 3.3.0+ | **Runtime deps:** `redis ~> 4.8`, `dotenv ~> 2.8`

---

## What It Is

A Ruby multi-agent workflow engine for software development. Orchestrates
role-specialized agents (Planner, Engineer, QA, Reviewer, Security) that share
Redis memory — but **never calls an LLM itself**. It runs as an MCP server over
stdio and lets the IDE's AI (Copilot, OpenCode) do the actual inference.
It is scaffolding, not an API wrapper.

Three surfaces:
- **CLI** (`agentf <subcommand>`) — memory management, code exploration, metrics, evals
- **MCP server** (`agentf mcp-server`) — 19 tools over stdio for IDE integrations
- **Ruby API** — `WorkflowEngine`, `Agents::*`, `RedisMemory` for programmatic use

---

## Architecture

| Layer | Files | Role |
|---|---|---|
| Entry point | `agentf.rb`, `bin/agentf` | Config singleton + CLI boot |
| CLI | `cli/router.rb`, `cli/memory.rb`, `cli/code.rb` | Subcommand dispatch |
| Agents | `agents/base.rb`, role subclasses | Role-based agent classes |
| Workflow | `workflow_engine.rb` | Orchestrator / sequencer |
| Memory | `memory.rb`, `memory/confirmation_handler.rb` | Redis-backed storage |
| Contracts | `workflow_contract.rb`, `agent_execution_contract.rb` | Constraint enforcement |
| Tools | `tools/`, `tools.rb` | Primitive capabilities |
| Commands | `commands/registry.rb`, `commands/*.rb` | Named command registry |
| MCP | `mcp/server.rb`, `mcp/stub.rb` | stdio MCP protocol server |
| Service | `service/providers.rb` | Provider adapters |
| Installer | `installer.rb` | Manifest generation and provider setup |

---

## Patterns Worth Stealing

### 1. Agents That Describe Themselves at the Class Level

All agent metadata — `description`, `deliverables`, `policy_boundaries`,
`when_to_use`, `commands` — are class methods, not instance state or external
YAML. Agents are self-documenting, introspectable at install time, and
verifiable without instantiating anything. The `Installer` reads these at
install time to generate markdown manifests.

### 2. Three-Mode Contract Enforcement (advisory / enforcing / off)

A contract object wraps agent execution with `before!`/`after!` validation.
Run workflows in `advisory` mode during development (log violations, don't
stop), flip to `enforcing` for production. TDD phase discipline (`"red"` vs
`"green"`) is enforced at the contract layer, not by convention.

### 3. Human-in-the-Loop Memory Writes

`ConfirmationHandler` wraps Redis writes so that when confirmation is needed,
instead of raising it returns `{ confirmation: true, payload: ..., instructions: ... }`.
The caller re-invokes with `confirmedWrite: "confirmed"`. Works identically
across CLI, MCP, and programmatic callers.

### 4. Deterministic Local Embeddings With No ML Dependency

`EmbeddingProvider` SHA256-hashes tokens, uses the hash to pick a dimension in
a 64-element float vector, then normalizes it. Zero API calls, zero latency,
fully reproducible. Crude but sufficient for semantic memory search in a
dev-tool context.

### 5. Black-Box Shell Script Evals

Each eval scenario is three files: `prompt.txt`, `scenario.yml`, and
`verify.sh`. The shell script asserts postconditions against real Redis state.
Simple, portable, no mocking — `agentf eval run all` just executes them.

### 6. Graceful Redis Capability Degradation

The memory layer detects at runtime whether Redis Stack's JSON/Search/Vector
modules are present and degrades silently. Full semantic search if available;
plain key-value otherwise. No config flag needed — baked into `RedisMemory`.

### 7. Ruby Generating Its Own TypeScript Integration

The installer generates TypeScript plugin files (`agentf-plugin.ts`,
`tsconfig.json`, `package.json`) from within Ruby for OpenCode integration.
A Ruby gem producing its own typed IDE plugin layer is unusual and practical.

### 8. Policies Stored in Code, Not Config

`policy_boundaries` returns `{ "always" => [...], "ask_first" => [...], "never" => [...] }`
directly from Ruby class methods. Changing a policy means changing Ruby, not
YAML — no config drift.

### 9. Workflow Profiles as Constants

Workflow compositions are defined as constants in `WorkflowEngine::PROFILES`
(e.g., `rails_standard`, `rails_37signals`), mapping task types to ordered
agent sequences. One canonical source of truth for workflow shapes.

---

## RobotLab Applicability Analysis

### Patterns That Don't Apply

**Pattern 7 — Ruby Generating Its Own TypeScript Integration**
agentf is an IDE tool targeting Copilot/OpenCode. RobotLab is a Ruby library with no IDE integration surface. Not relevant.

**Pattern 6 — Graceful Redis Capability Degradation**
Already handled. `Memory` already degrades `redis → hash` fallback at initialization. `DocumentStore` uses fastembed, not Redis Stack — separate concern covered below.

---

### Patterns Worth Implementing

---

#### Pattern 1 — Self-Describing Robots/Tools (HIGH VALUE)

This is the missing piece for `tool_manifest_plan.md`. Nothing auto-registers today because there is nowhere to register *to* and no class-level metadata to register. agentf's insight: put descriptors at the class level, not in instances.

```ruby
class MyTool < RobotLab::Tool
  self.description = "Fetch current weather for a location"
  self.tags        = [:network, :read_only]
end
```

At class-load time, Zeitwerk triggers auto-registration into `RobotLab.tool_registry`. The selector-robot pattern becomes viable without any explicit registration ceremony. Live callable instances stay per-robot; the global registry holds lightweight descriptors only (name + description). This is the v1 the `tool_manifest_plan.md` actually needs — and avoids the MCP auto-registration problem identified in that plan's review notes.

Robot subclasses get the same treatment:
```ruby
class SupportBot < RobotLab::Robot
  self.description  = "Handles tier-1 customer support"
  self.capabilities = [:search, :ticket_creation]
end
```

This also enables the `Installer`-style manifest generation: `RobotLab.tool_registry.summary` produces the compact name+description list the selector robot reasons over.

---

#### Patterns 2 + 8 — Contract Enforcement + Policy Boundaries (HIGH VALUE, medium effort)

RobotLab has a circuit breaker (`max_tool_rounds`) and an error hierarchy — but no *pre/post validation layer* on execution. As AIA drives RobotLab into production use, this gap is significant.

The three modes map cleanly to the dev→prod lifecycle:
- `advisory` — log violations, don't block (development default)
- `enforcing` — raise on violation (production default)
- `off` — no overhead (test default)

Policies declared at the Tool class level:
```ruby
class DeleteFileTool < RobotLab::Tool
  policy :ask_first   # always prompt user before executing
end

class FormatDriveTool < RobotLab::Tool
  policy :never       # contract blocks execution entirely in enforcing mode
end
```

The contract wraps `robot.run()` with `before!`/`after!` hooks — checks token budget, validates tool policies, enforces max cost. A `RunConfig` field (`contract: :advisory`) controls the mode and flows through the standard hierarchy. This pairs naturally with the existing `RunConfig` merge semantics and would be the first true safety/governance layer in RobotLab.

---

#### Pattern 9 — Workflow Profiles (LOW EFFORT, good discoverability)

Networks are currently built by hand each time. A `RobotLab::Profiles` module with named constants would reduce boilerplate and document canonical topologies:

```ruby
RobotLab::Profiles::CONSENSUS   # fan-out to N robots → reconciler
RobotLab::Profiles::PIPELINE    # sequential chain
RobotLab::Profiles::PARALLEL    # concurrent, no synthesis
RobotLab::Profiles::MCP_FAN_OUT # one robot per MCP server
```

Each profile is a lambda/factory that takes robots + optional router and returns a configured network. This also gives AIA's `RobotFactory` topologies a canonical home in the library itself rather than application-level code.

---

#### Pattern 5 — Eval Framework (MEDIUM EFFORT, high long-term value)

RobotLab has 22 example scripts but **zero assertions**. They are demos, not evals. agentf's `prompt.txt + scenario.yml + verify.sh` per scenario is the right shape.

For RobotLab the natural form:
- `evals/scenarios/convergence_basic/` — prompt, expected behavior description, `verify.rb` script
- `rake eval:run[convergence_basic]` replays against a VCR cassette and asserts postconditions
- `rake eval:run:all` becomes a regression suite for agent behavior

This connects directly to AIA's EDD (Eval-Driven Development) vision and would give confidence before a 1.0 release. The existing VCR/WebMock infrastructure is the right foundation.

---

#### Pattern 4 — Deterministic Embedding Fallback (LOW EFFORT)

`DocumentStore` hard-requires fastembed — no fallback. On first use it downloads an ONNX model, which is slow and requires a working network. `word_hash` (stemmed TF vectors) already exists in the codebase and is used by `compress_history`, `search_history`, and `Convergence`.

A simple degradation path: when fastembed raises `LoadError` or the model is unavailable, `DocumentStore` falls back to `word_hash` cosine similarity with a logged warning. Zero new infrastructure — just wiring what already exists into `DocumentStore#embed`.

---

#### Pattern 3 — HITL Confirmation Protocol (LOW VALUE given AskUser)

The agentf pattern — return `{ confirmation: true, payload: }` instead of raising, re-invoke with `confirmedWrite: "confirmed"` — is elegant for memory writes that need approval. However, RobotLab already has `AskUser` for the primary HITL use case. This pattern only becomes interesting if RobotLab needs programmatic HITL that doesn't require a terminal (e.g., web apps pausing for user approval via HTTP callback). Not urgent.

---

### Priority Ranking

| Priority | Pattern | Effort | Connects To |
|---|---|---|---|
| 1 | Self-describing tools/robots (class-level metadata) | Medium | `tool_manifest_plan.md` — makes ToolManifest v1 actionable |
| 2 | Contract enforcement + Policy boundaries | Medium | Production safety gap; RunConfig integration |
| 3 | Eval framework | Medium | Long-term regression confidence; AIA EDD |
| 4 | Workflow profiles | Low | AIA's RobotFactory; discoverability |
| 5 | DocumentStore word_hash fallback | Low | Dev ergonomics; no ONNX download needed |

**Natural weekly pairing:** Pattern 1 (self-describing classes → ToolManifest v1) + Pattern 9 (workflow profiles) form a coherent "discoverability and composability" theme. Patterns 2+8 are the right *next* architectural investment but scope to a separate week.

---

## Comparison to Other Agent Frameworks

| Aspect | `agentf` | LangChain (Python) | CrewAI (Python) |
|---|---|---|---|
| Language | Ruby | Python | Python |
| LLM calls | None (delegates to IDE) | Direct | Direct |
| Agent communication | Shared Redis memory | In-process state | Sequential/hierarchical |
| Memory | Episodic + semantic (Redis Stack) | Various vector stores | Basic |
| IDE integration | MCP server (Copilot, OpenCode) | None native | None native |
| Contract enforcement | 3-mode advisory/enforcing/off | None | None |
| Self-describing agents | Class-method metadata | No | Role strings in YAML |
| Eval framework | Black-box shell scripts | Unit tests | Unit tests |
| TDD enforcement | Built-in (red/green contracts) | None | None |

Within Ruby there is essentially no direct equivalent. `ruby-openai` and
`omniai` handle LLM API calls but have no orchestration. `agentf` is novel in
the Ruby ecosystem for combining Redis-backed episodic memory, role-specialized
agent classes, contract enforcement, and an MCP stdio server in one gem.

---

## The Big Takeaway

The most instructive thing about `agentf` is its **division of responsibility**:
the gem owns memory, sequencing, policies, and tool-exposure via MCP — the
IDE's AI owns inference. That separation means no API keys, no HTTP calls to
LLM providers, and no model coupling. If building AI-assisted tooling in Ruby,
that architecture is worth emulating.
