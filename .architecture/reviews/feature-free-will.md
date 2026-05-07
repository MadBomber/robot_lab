# Architecture Review: free_will Branch

**Date**: 2026-02-17
**Review Type**: Feature Branch Review (full codebase on `free_will`)
**Version**: 0.0.5
**Previous Review**: `overall-codebase.md` (2026-02-16)
**Reviewers**: Systems Architect, Concurrency Specialist, API Design Lead, Reliability Engineer, Testing Strategist, Pragmatic Enforcer

## Executive Summary

The `free_will` branch represents RobotLab v0.0.5 with significant improvements since the previous review. Three of the four "Critical Actions" from the 2026-02-16 review have been addressed: the bus processing guard is now in core, `dispatch_async` uses Async exclusively (no Thread leak), and Memory nil-value handling is fixed. The addition of `RunConfig` for hierarchical configuration is well-executed and fills a real need.

The remaining technical debt centers on dead code (streaming module, ghost `network:` parameter, unused RedisBackend) and documentation drift. The architecture is sound and appropriate for a v0.0.5 framework.

**Overall Assessment**: Adequate -- trending toward Strong

**Key Findings**:
- 3 of 4 critical actions from previous review are resolved
- `RunConfig` is a solid addition that unifies the configuration hierarchy
- `network:` parameter in `Robot#run` is vestigial dead code -- never populated from the pipeline
- Streaming module remains orphaned (95 lines, 22 event types, zero consumers)
- Test coverage is strong (27 files, 1,049+ assertions in robot_test alone) but no integration suite

**Critical Actions**:
- Remove the `network:` parameter from `Robot#run` and the `network&.network&.mcp` chain in MCPManagement
- Integrate or remove the streaming module before v0.1.0

---

## Delta from Previous Review (2026-02-16)

### Resolved

| Previous Finding | Status | How Resolved |
|---|---|---|
| Async re-entrancy in Robot#run (High) | **RESOLVED** | `BusMessaging#handle_incoming_delivery` now uses `@bus_processing` flag + `@bus_queue` to serialize deliveries |
| dispatch_async Thread leak (Medium) | **RESOLVED** | `Utils#dispatch_async` simplified to `Async { block.call }` -- no Thread.new fallback |
| Memory nil-value handling (Medium) | **RESOLVED** | `get_single` now uses `@backend.key?(key)` instead of nil check |
| No RunConfig for shared configuration | **RESOLVED** | `RunConfig` class added with field categories, merge semantics, and `apply_to(chat)` |

### Remaining

| Previous Finding | Status | Notes |
|---|---|---|
| Ghost NetworkRun references (Medium) | **OPEN** | `network:` param in Robot#run and `network&.network&.mcp` in MCPManagement |
| Streaming module orphaned (Medium) | **OPEN** | Still not wired into Robot#run or Network#run |
| Adapter directory mismatch (Low) | **OPEN** | test_helper references adapters SimpleCov group; no adapters/ dir exists |
| Eager loading at boot (Medium) | **OPEN** | `loader.eager_load` still unconditional |
| RedisBackend untested/unused (Low) | **OPEN** | 50 lines, no test coverage, auto-falls back to Hash |
| ToolManifest usage unclear (Low) | **OPEN** | Full collection API but not used in execution path |
| No integration tests (High) | **OPEN** | Rakefile `integration` task exists but no test/integration/ directory |
| MCP auto-reconnect (Low) | **OPEN** | `call_tool` still raises MCPError on disconnect with no retry |

### New Findings

See individual member reviews below.

---

## System Overview

### File Counts
| Area | Files | Lines (approx) |
|------|-------|-------|
| Core lib (`lib/robot_lab/`) | 36 | ~3,970 |
| Robot concerns (`lib/robot_lab/robot/`) | 3 | ~370 |
| MCP (`lib/robot_lab/mcp/`) | 6 | ~600 |
| Streaming (`lib/robot_lab/streaming/`) | 3 | ~200 |
| Tests (`test/`) | 27 | ~5,400 |
| Examples | 15 scripts | N/A |

### Dependency Graph (Core)

```
RobotLab (module)
  +-- Config (MywayConfig::Base)
  |     +-- configures RubyLLM + PromptManager
  +-- RunConfig (standalone)
  |     +-- LLM/Tool/Callback/Infra fields
  |     +-- merge semantics, apply_to(chat)
  +-- Robot (RubyLLM::Agent)
  |     +-- TemplateRendering (module)
  |     +-- MCPManagement (module)
  |     +-- BusMessaging (module) [processing guard]
  +-- Network
  |     +-- SimpleFlow::Pipeline
  |     +-- Task (step wrapper, per-task RunConfig)
  |     +-- Memory (shared)
  +-- Memory
  |     +-- Waiter (ConditionVariable)
  |     +-- StateProxy (method_missing)
  |     +-- MemoryChange (notification)
  |     +-- RedisBackend (optional, unused)
  +-- MCP::Client
  |     +-- MCP::Server (config)
  |     +-- Transports (Stdio, WebSocket, SSE, StreamableHTTP)
  +-- Tool (RubyLLM::Tool)
  |     +-- AskUser (built-in)
  |     +-- ToolManifest (registry, possibly unused)
  +-- Message hierarchy
  |     +-- TextMessage, ToolCallMessage, ToolResultMessage
  |     +-- ToolMessage (internal)
  |     +-- UserMessage
  +-- RobotMessage (Data.define, bus envelope)
  +-- RobotResult (execution result)
  +-- Streaming::Events (orphaned)
  +-- Streaming::Context (orphaned)
  +-- Utils, Error, Errors, ToolConfig
```

---

## Individual Member Reviews

### Systems Architect - Principal Systems Architect

**Perspective**: Evaluates overall structure, module boundaries, and dependency flow

#### Key Observations
- RunConfig is a well-designed addition that cleanly addresses configuration hierarchy without over-engineering
- The Robot concern extraction (TemplateRendering, MCPManagement, BusMessaging) continues to be clean
- `robot_lab.rb` entry point is well-structured with factory methods

#### Strengths
1. **RunConfig merge semantics**: `more-specific wins` is intuitive; `from_front_matter` bridges template config elegantly
2. **Configuration chain is complete**: Global -> Network -> Task -> Robot -> Template -> Runtime, all via RunConfig
3. **BusMessaging processing guard**: The `@bus_processing` + `@bus_queue` pattern is simple and correct
4. **Factory pattern stability**: `RobotLab.build()` and `create_network()` haven't changed across versions -- good API stability

#### Concerns
1. **Dead `network:` parameter in Robot#run** (Impact: Medium)
   - Issue: `Robot#run` accepts `network:` but it's never populated. `Network#run` passes `network_memory:` and `network_config:` via run_params, but not `network:`. In `MCPManagement#resolve_mcp_hierarchy`, the chain `network&.network&.mcp` calls `.network` on whatever `network:` is -- but since it's always nil, this is dead code.
   - Evidence: `Task#call` builds `run_params` with `:network_memory` and `:network_config` keys. `Robot#extract_run_context` does NOT extract a `:network` key. So `network:` in `Robot#run` always receives nil.
   - Recommendation: Remove the `network:` parameter from `Robot#run`. Replace `network&.network&.mcp` with just `network_config&.mcp` in MCPManagement. This is the residue of the removed `NetworkRun` class.

2. **Eager loading remains unconditional** (Impact: Medium)
   - Issue: `loader.eager_load` at line 69 of `robot_lab.rb` forces all classes to load at require time, including streaming, MCP transports, and Redis backend regardless of whether they're needed.
   - Recommendation: Gate behind `if defined?(Rails) || ENV['ROBOT_LAB_EAGER_LOAD']`

3. **Dual error files: `error.rb` + `errors.rb`** (Impact: Low)
   - Issue: `error.rb` defines the exception hierarchy (`Error`, `ConfigurationError`, etc.) while `errors.rb` defines the `Errors` utility module (`serialize`, `deserialize`, `capture`). The names are confusingly similar.
   - Recommendation: Rename `errors.rb` to something more descriptive like `error_serializer.rb` or merge into `error.rb`.

#### Pragmatic Analysis
| Item | Necessity | Complexity | Ratio | Recommendation |
|------|-----------|-----------|-------|---------------|
| Remove `network:` dead code | 8 | 1 | 0.1 | **Do now** |
| Conditional eager_load | 5 | 1 | 0.2 | **Do now** |
| Rename errors.rb | 3 | 1 | 0.3 | **Defer** |

#### Recommendations
1. **Remove `network:` parameter and ghost chain** (Priority: High, Effort: Small)
2. **Make eager_load conditional** (Priority: Medium, Effort: Small)

---

### Concurrency Specialist - Async & Concurrency Engineer

**Perspective**: Analyzes async patterns, race conditions, and message ordering guarantees

#### Key Observations
- The processing guard in BusMessaging is correctly implemented and addresses the critical re-entrancy bug
- `dispatch_async` is now Async-only, eliminating the Thread leak concern
- Memory's reactive infrastructure uses proper mutex discipline

#### Strengths
1. **Processing guard is correct**: `@bus_processing` flag set in `process_delivery` with `ensure` block for cleanup. Queue drained sequentially via `drain_bus_queue`. Error handling nacks the delivery and re-raises wrapped in BusError.
2. **dispatch_async is clean**: `Async { block.call }` -- simple, no Thread.new, no double-wrapping. Relies on Async's own task management.
3. **Waiter is thread-safe**: Uses Mutex + ConditionVariable with `@signaled` flag to prevent missed wakeups. Timeout calculation is correct.
4. **Memory nil-value fix is correct**: `@backend.key?(key)` distinguishes "not set" from "set to nil".

#### Concerns
1. **Async exception swallowing** (Impact: Medium)
   - Issue: `dispatch_async` uses `Async { block.call }`. Exceptions inside Async tasks are captured by the Async framework but not propagated to callers. Memory subscription callbacks that raise exceptions will be silently swallowed unless there's an active Async reactor with error handling.
   - Recommendation: Wrap the callback in a rescue block that logs or delegates to a configurable error handler:
     ```ruby
     def dispatch_async(&block)
       Async do
         block.call
       rescue => e
         RobotLab.config.logger&.error("Async dispatch error: #{e.message}")
       end
     end
     ```

2. **BusMessaging drain_bus_queue is non-reentrant but has edge case** (Impact: Low)
   - Issue: `drain_bus_queue` processes deliveries via `process_delivery`, which sets `@bus_processing = true` then `false` in ensure. If `drain_bus_queue` calls `process_delivery` and the handler enqueues more messages to `@bus_queue` (via a send_message that results in a delivery to self), these will be picked up by the same `drain_bus_queue` loop. This is correct behavior but could lead to unbounded queue growth if a handler always self-messages.
   - Recommendation: Document that self-messaging in handlers requires a termination condition. Consider a max drain depth.

3. **Memory subscription callbacks can deadlock via re-entry** (Impact: Low)
   - Issue: If a subscription callback calls `memory.set(key, value)`, it triggers `notify_subscribers_async` which acquires `@subscription_mutex`. Since `dispatch_async` runs in a separate Async task, this should be safe. However, if the callback is synchronous (e.g., inside a test without Async), it could deadlock.
   - Recommendation: This is safe in practice because `dispatch_async` always wraps in Async. Document that Memory's reactive features require an Async reactor.

#### Recommendations
1. **Add error logging to dispatch_async** (Priority: Medium, Effort: Small)
2. **Document self-messaging guard requirement** (Priority: Low, Effort: Small)

---

### API Design Lead - Developer Experience Architect

**Perspective**: Evaluates public API surface, developer experience, and Ruby idiomaticness

#### Key Observations
- RunConfig's dual construction patterns (keyword + block DSL) are elegant and Ruby-idiomatic
- The `with_*` chaining on Robot remains clean
- `reply` alias on RobotResult improves ergonomics

#### Strengths
1. **RunConfig construction is flexible**: `RunConfig.new(model: "x")` for simple cases, `RunConfig.new { |c| c.model("x") }` for DSL, `config.merge(other)` for composition
2. **Progressive disclosure maintained**: `RobotLab.build.run("Hello")` still works with zero configuration
3. **on_message arity detection**: 1-arg = auto-ack, 2-arg = manual -- clever, well-documented in BusMessaging comments
4. **Consistent serialization**: Every domain object has `to_h`, `to_json`, and most have `from_hash`

#### Concerns
1. **Robot#initialize still takes 20+ parameters** (Impact: Medium)
   - Issue: Despite RunConfig, the constructor still accepts `model:`, `temperature:`, `mcp:`, `tools:`, etc. as direct kwargs alongside `config:`. The constructor logic (lines 134-148) merges these into a RunConfig internally. This creates two valid construction patterns that produce the same result.
   - Recommendation: For v0.1.0, consider deprecating individual LLM kwargs in favor of `config:` only. This would simplify the constructor to ~8 parameters (name, template, system_prompt, context, description, local_tools, config, bus).

2. **Robot#run kwargs serve dual purpose** (Impact: Medium)
   - Issue: `**kwargs` in `Robot#run` are split between template re-rendering (`kwargs.except(:with)`) and ask options (`kwargs.slice(:with)`). This coupling means any new template parameter name could collide with future ask() options.
   - Recommendation: Use explicit named parameter: `run(message, context: {}, with: [])`. This makes the split visible in the API.

3. **`config:` name collision in Network#task** (Impact: Low)
   - Issue: `Network#task` accepts `config:` for per-task RunConfig. But `config` is also a common context hash key. If a user passes `task :billing, bot, config: some_run_config, context: { config: "billing" }`, the intent is clear but the parameter name overlap is confusing.
   - Recommendation: Acceptable for now. The types are distinct (RunConfig vs Hash value).

4. **spawn returns bare Robot without on_message** (Impact: Low)
   - Issue: `Robot#spawn` creates a new robot on the shared bus, but the spawned robot has no `on_message` handler by default. Messages sent to it will trigger `handle_message_via_llm` (default handler), which calls `run()` and replies. This is fine for simple cases but could be surprising.
   - Recommendation: Document that spawned robots default to LLM-pass-through messaging unless `on_message` is set.

#### Pragmatic Analysis
| Item | Necessity | Complexity | Ratio | Recommendation |
|------|-----------|-----------|-------|---------------|
| Deprecate individual LLM kwargs | 5 | 3 | 0.6 | **Defer to v0.1.0** |
| Explicit context: in run() | 6 | 2 | 0.3 | **Do short-term** |
| Document spawn behavior | 4 | 1 | 0.3 | **Do now** |

#### Recommendations
1. **Separate template context from ask options in Robot#run** (Priority: Medium, Effort: Small)
2. **Document spawn default messaging behavior** (Priority: Low, Effort: Small)

---

### Reliability Engineer - Error Handling & Resilience Specialist

**Perspective**: Assesses error handling, failure modes, and system resilience

#### Key Observations
- Error hierarchy unchanged and appropriate (6 error classes)
- MCP connection failures continue to degrade gracefully
- The `Errors.capture` utility provides clean error envelopes

#### Strengths
1. **BusMessaging error handling is correct**: `process_delivery` rescues all exceptions, nacks the delivery if pending, and re-raises as BusError with context
2. **RunConfig validates field names**: `set()` raises ArgumentError for unknown fields, preventing silent typos
3. **Memory#delete protects reserved keys**: Raises ArgumentError when attempting to delete `:data`, `:results`, etc.
4. **Template rendering defers gracefully**: Missing required parameters don't crash -- they defer rendering until `run()` when context is available

#### Concerns
1. **Async exceptions still silently swallowed** (Impact: Medium)
   - Issue: As noted by Concurrency Specialist -- `dispatch_async` wraps in Async but doesn't catch/log errors. This affects Memory subscription callbacks and Network broadcast handlers.
   - Recommendation: Add `rescue => e` with configurable error handler. Default to `RobotLab.config.logger.error`.

2. **MCP Client reconnection still absent** (Impact: Medium)
   - Issue: `MCP::Client#call_tool` raises `MCPError` if not connected. No auto-reconnect. Long-running robots using MCP tools will fail permanently if the MCP server restarts.
   - Recommendation: Add a `reconnect` option to `call_tool`: try once, on MCPError attempt `connect` then retry. Single retry, no exponential backoff needed for v0.0.x.

3. **Config.mcp / Config.tools may not exist** (Impact: Low)
   - Issue: `MCPManagement#resolve_mcp_hierarchy` falls back to `RobotLab.config.mcp`. If the MywayConfig defaults.yml doesn't define `mcp:`, this could raise NoMethodError. Same for `tools`.
   - Evidence: Would need to check `lib/robot_lab/config/defaults.yml` to verify.
   - Recommendation: Use `RobotLab.config.respond_to?(:mcp) ? RobotLab.config.mcp : nil` or add defaults.

4. **Memory#clone doesn't deep-copy complex values** (Impact: Low)
   - Issue: Per the CHANGELOG, `clone` now "results and messages are referenced directly instead of duplicated." This means cloned memory shares mutable objects with the original. If a robot modifies a result's debug fields (`prompt`, `history`, `raw`), the original memory is affected.
   - Recommendation: Acceptable tradeoff for performance. Document that clone shares result/message references.

#### Recommendations
1. **Add configurable async error handler** (Priority: Medium, Effort: Small)
2. **Add single-retry MCP reconnection** (Priority: Low, Effort: Small)
3. **Verify Config defaults for mcp/tools** (Priority: Medium, Effort: Small)

---

### Testing Strategist - Quality Assurance Architect

**Perspective**: Reviews test architecture, coverage gaps, and testing patterns

#### Key Observations
- Test suite is comprehensive: 27 files, 1,049+ assertions in robot_test.rb alone
- RunConfig has a dedicated 39-test/380-assertion suite
- Memory tests cover reactive features including concurrent access
- Bus messaging tests verify the processing guard

#### Strengths
1. **RunConfig tests are excellent**: 39 tests covering construction, merge, apply_to, front_matter, serialization
2. **Memory reactive tests**: Concurrent read/write with 10 threads x 100 ops, subscription notification, blocking wait
3. **Robot bus tests**: Processing guard verification, queue draining, error-during-drain handling
4. **Test helpers are well-designed**: `build_robot`, `build_network`, `build_config`, `wait_until` with customizable timeout

#### Concerns
1. **No integration test directory** (Impact: High)
   - Issue: `Rakefile` defines an `integration` task pointing to `test/integration/**/*_test.rb` but the directory doesn't exist. End-to-end workflows (Robot -> Network -> Memory -> Bus) are only tested in examples, not in the test suite.
   - Recommendation: Create `test/integration/` with:
     - `network_pipeline_test.rb`: Task -> Robot -> Memory flow
     - `bus_round_trip_test.rb`: send_message -> on_message -> send_reply
     - `mcp_tool_discovery_test.rb`: Client -> list_tools -> call_tool (with MockTransport)

2. **Streaming module tests are isolated** (Impact: Medium)
   - Issue: `streaming_test.rb` tests Event constants and Context in isolation. Since streaming is not wired into execution, these tests only verify the data structures exist, not that they work.
   - Recommendation: Either remove streaming tests (they'll be recreated when streaming is integrated) or clearly mark them as "infrastructure only."

3. **Network#run not tested end-to-end** (Impact: Medium)
   - Issue: `network_test.rb` tests initialization, task management, visualization, and serialization. But there's no test that calls `network.run()` and verifies the result flows through the pipeline. The pipeline execution is delegated to SimpleFlow which is tested externally, but the RobotLab-specific wiring (memory injection, config passing) is untested.
   - Recommendation: Add a test that creates a 2-robot network, runs it, and verifies both robots received shared memory and the final result contains both robots' output.

4. **MCP transport tests need real-world validation** (Impact: Low)
   - Issue: MCP tests use MockTransport. While this verifies the client API, it doesn't test actual transport behavior (stdio process spawning, WebSocket handshake, SSE reconnection).
   - Recommendation: Add a lightweight integration test with a simple stdio MCP server (e.g., a Ruby script that responds to `tools/list`). Low effort, high value.

#### Pragmatic Analysis
| Item | Necessity | Complexity | Ratio | Recommendation |
|------|-----------|-----------|-------|---------------|
| Integration test suite | 8 | 4 | 0.5 | **Do short-term** |
| Network#run end-to-end test | 7 | 2 | 0.3 | **Do now** |
| MCP stdio integration test | 5 | 3 | 0.6 | **Do short-term** |
| Clean up streaming tests | 3 | 1 | 0.3 | **Defer** |

#### Recommendations
1. **Create integration test directory with 3 core workflows** (Priority: High, Effort: Medium)
2. **Add Network#run pipeline test** (Priority: High, Effort: Small)

---

### Pragmatic Enforcer - YAGNI & Simplicity Advocate

**Perspective**: Challenges unnecessary complexity and advocates for simplest viable solutions

#### Key Observations
- RunConfig is a justified addition -- it solves a real configuration hierarchy problem with appropriate complexity
- The processing guard in BusMessaging is simple and correct -- not over-engineered
- Streaming module remains the largest piece of speculative infrastructure

#### Pragmatic Scorecard

| Feature | Necessity (0-10) | Complexity (0-10) | Ratio | Recommendation |
|---------|-----------------|-------------------|-------|----------------|
| Robot core + with_* chaining | 10 | 4 | 0.4 | **Keep** |
| Network/Pipeline | 9 | 5 | 0.6 | **Keep** |
| RunConfig | 8 | 3 | 0.4 | **Keep** -- justified, well-sized |
| Memory (reactive) | 8 | 6 | 0.8 | **Keep** |
| Bus messaging + guard | 7 | 4 | 0.6 | **Keep** |
| MCP integration | 7 | 6 | 0.9 | **Keep** |
| Tool hierarchy (ToolConfig) | 6 | 3 | 0.5 | **Keep** |
| Streaming events | 4 | 4 | 1.0 | **Remove** -- still orphaned |
| Redis backend | 3 | 3 | 1.0 | **Remove** -- still unused |
| ToolManifest | 3 | 2 | 0.7 | **Audit** -- still unclear |
| `network:` dead parameter | 0 | 1 | inf | **Remove** -- pure dead code |

#### Concerns
1. **Streaming infrastructure: still 95 lines with zero consumers** (Pragmatic Score: 1.0)
   - Issue: Same as previous review. `Streaming::Events` (95 lines, 22 event types), `Streaming::Context` (145 lines), and `Streaming::SequenceCounter` -- none connected to Robot#run or Network#run. Cost of recreating when needed: near zero.
   - Recommendation: Move to a feature branch. Remove from main/free_will.

2. **RedisBackend: still 50 lines with no tests** (Pragmatic Score: 1.0)
   - Issue: `RedisBackend` (lines 807-857 of memory.rb) implements a full key-value interface on Redis. No tests exercise it. The auto-detection path silently falls back to Hash. No examples use it.
   - Recommendation: Extract to a separate file and gate behind `require 'robot_lab/memory/redis_backend'`. Don't load by default.

3. **ToolManifest: 217 lines, used nowhere in execution** (Pragmatic Score: 0.7)
   - Issue: `ToolManifest` provides Enumerable, merge, replace, fetch, from_hash -- a full collection API. Robot uses `@local_tools + @mcp_tools` arrays directly. `ToolConfig.filter_tools` operates on arrays. ToolManifest appears to be a public API surface that nothing internal consumes.
   - Recommendation: Keep if intended as a user-facing registry API. Remove if not. Audit with `grep -r ToolManifest` to verify.

4. **RunConfig is well-sized** (Pragmatic Score: 0.4)
   - RunConfig is 184 lines with clear field categories, merge semantics, and serialization. It solves a real problem (configuration hierarchy) without over-engineering. Good pragmatic balance.

#### Recommendations
1. **Remove streaming module** (Priority: Medium, Effort: Small)
2. **Extract RedisBackend to optional require** (Priority: Low, Effort: Small)
3. **Audit ToolManifest usage** (Priority: Low, Effort: Small)
4. **Remove dead `network:` parameter** (Priority: High, Effort: Small)

---

## Collaborative Discussion

### Consensus Points

All reviewers agree on:
1. **Core architecture is sound and improving**: RunConfig was a well-judged addition; bus processing guard resolves the highest-risk issue from the previous review
2. **`network:` parameter is dead code**: Must be removed -- it creates confusion and references a non-existent class
3. **Streaming module should be removed or integrated**: Two consecutive reviews flagging it as orphaned is sufficient signal
4. **Integration tests are overdue**: The framework is complex enough that unit tests alone can't verify the wiring between components

### Points of Discussion

- **Systems Architect** and **Pragmatic Enforcer** agree on removing the `network:` parameter. **Reliability Engineer** notes this should be done carefully since it's a breaking API change (callers passing `network:` would get an error). **Consensus**: It's a pre-1.0 gem; break the API now. No known callers pass `network:`.
- **API Design Lead** suggests splitting Robot#run kwargs into explicit `context:` and `with:`. **Pragmatic Enforcer** asks if any users are actually confused by the current behavior. **Consensus**: Add `context:` as a named parameter; keep `**kwargs` for backward compat until v0.1.0.
- **Testing Strategist** wants 3 integration tests. **Pragmatic Enforcer** suggests starting with 1 (Network#run pipeline) since that's the most complex untested path. **Consensus**: Start with Network#run, add bus round-trip, defer MCP integration test.

---

## Consolidated Findings

### Strengths
1. **Configuration hierarchy is complete**: RunConfig flows cleanly through Global -> Network -> Task -> Robot -> Template -> Runtime
2. **Bus messaging is safe**: Processing guard prevents the critical async re-entrancy bug
3. **Memory reactive API is well-designed**: set/get/subscribe/wait with proper thread-safety
4. **Test coverage is strong**: >1:1 test-to-source ratio with per-class coverage
5. **API ergonomics**: Progressive disclosure from `build.run("Hello")` to full Network+Bus orchestration

### Areas for Improvement
1. **Dead code cleanup**: `network:` parameter, streaming module, RedisBackend, adapter references
2. **Integration testing**: No end-to-end test for the Robot-Network-Memory pipeline
3. **Error observability**: Async dispatch errors are silently swallowed
4. **Documentation accuracy**: CLAUDE.md still references `NetworkRun` in places

### Technical Debt

**High Priority**:
- `network:` dead parameter in Robot#run: Creates confusion and dead code chains. Resolution: Remove parameter and ghost references in MCPManagement. Effort: Small.

**Medium Priority**:
- Streaming module orphaned: 95+ lines of infrastructure with zero consumers. Resolution: Remove or move to branch. Effort: Small.
- No integration tests: Complex multi-component wiring is untested. Resolution: Add Network#run pipeline test. Effort: Small-Medium.
- Async error swallowing: Subscription/broadcast callbacks fail silently. Resolution: Add rescue + log in dispatch_async. Effort: Small.

**Low Priority**:
- RedisBackend untested/unused: 50 lines loaded by default. Resolution: Gate behind optional require. Effort: Small.
- ToolManifest possibly unused: 217 lines with full collection API. Resolution: Audit usage. Effort: Small.
- Eager load unconditional: Forces all classes at boot. Resolution: Conditional on Rails. Effort: Small.

### Risks

**Technical Risks**:
- **Async error blindness**: Likelihood: Medium (any subscription callback that raises), Impact: Medium (silent data loss), Mitigation: Error logging in dispatch_async
- **RubyLLM breaking changes**: Likelihood: Medium (dependency is ~> 1.12, pre-stable), Impact: High (Robot inherits from Agent), Mitigation: Pin more tightly or add adapter layer
- **MCP server disconnection**: Likelihood: Low-Medium (long-running sessions), Impact: Medium (tool calls fail permanently), Mitigation: Single-retry reconnect

---

## Recommendations

### Immediate (0-2 weeks)
1. **Remove `network:` dead parameter**: Remove from Robot#run signature. Replace `network&.network&.mcp` with `network_config&.mcp` in MCPManagement. Update CLAUDE.md.
   - Owner: Core
   - Success Criteria: No references to `NetworkRun` or `network.network` in codebase
2. **Add error logging to dispatch_async**: Wrap callback in rescue, log to `RobotLab.config.logger.error`.
   - Success Criteria: Exceptions in subscription callbacks appear in logs
3. **Add Network#run pipeline test**: Create test that runs a 2-robot network and verifies shared memory, config passing, and result propagation.
   - Success Criteria: `bundle exec rake test` exercises the full pipeline path

### Short-term (2-8 weeks)
1. **Remove streaming module**: Move `Streaming::Events`, `Streaming::Context`, `Streaming::SequenceCounter` to a branch. Remove test file.
   - Success Criteria: No orphaned infrastructure code
2. **Create integration test directory**: Add `test/integration/` with:
   - `network_pipeline_test.rb`
   - `bus_round_trip_test.rb`
   - Success Criteria: `rake integration` runs 2+ workflow tests
3. **Extract RedisBackend**: Move to `lib/robot_lab/memory/redis_backend.rb` with optional require. Don't eager-load.
   - Success Criteria: `require 'robot_lab'` doesn't load Redis code
4. **Make eager_load conditional**: Gate behind `defined?(Rails)` or env var.
   - Success Criteria: Gem loads faster in non-Rails contexts

### Long-term (2-6 months)
1. **Integrate streaming into execution**: Wire `Streaming::Context` into `Robot#run` to emit lifecycle and delta events via block callback.
   - Success Criteria: `robot.run("Hello") { |event| ... }` yields streaming events
2. **Simplify Robot constructor**: For v0.1.0, move individual LLM kwargs to config-only. Reduce constructor to ~8 parameters.
   - Success Criteria: `Robot.new(name:, config:, template:, ...)` is the primary pattern
3. **Add MCP auto-reconnect**: Single retry on MCPError in `call_tool`.
   - Success Criteria: Transient MCP server restarts don't break robot sessions

---

## Success Metrics
1. **Dead code lines removed**: Current: ~360 (streaming + RedisBackend + dead params) -> Target: 0 (4 weeks)
2. **Integration test count**: Current: 0 -> Target: 3+ (6 weeks)
3. **Async error visibility**: Current: silently swallowed -> Target: logged (1 week)
4. **Doc accuracy**: Current: CLAUDE.md references NetworkRun -> Target: 100% accurate (1 week)

---

## Follow-up
**Next Review**: After v0.1.0 release or before major feature addition
**Tracking**: Address Immediate items before merging free_will to main

## Related Documentation
- `CLAUDE.md`: Project instructions (needs NetworkRun cleanup)
- `MEMORY.md`: Documents async re-entrancy fix (now in core -- update to reflect)
- `CHANGELOG.md`: v0.0.5 changes accurately describe RunConfig and fixes
- Previous review: `.architecture/reviews/overall-codebase.md` (2026-02-16)
