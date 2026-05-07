# Architecture Review: Overall Codebase

**Date**: 2026-02-16
**Review Type**: Comprehensive Codebase Review
**Version**: 0.0.5 (branch: `free_will`)
**Reviewers**: Systems Architect, Concurrency Specialist, API Design Lead, Reliability Engineer, Testing Strategist, Pragmatic Enforcer

## Executive Summary

RobotLab is a well-structured Ruby framework for orchestrating multi-robot LLM workflows. At ~5,000 lines of source code with ~5,400 lines of tests, it demonstrates strong engineering discipline. The architecture cleanly separates concerns into Robot (agent), Network (orchestration), Memory (state), and MCP (external tools), with TypedBus providing async inter-robot messaging.

The codebase shows thoughtful design decisions: hierarchical configuration resolution, reactive memory with pub/sub semantics, and a clean delegation pattern to RubyLLM. However, there are areas where the architecture is stretched -- the streaming subsystem is declared but not wired into execution, the `NetworkRun` class referenced in CLAUDE.md appears to have been removed without updating docs, and some concurrency patterns could lead to subtle issues under load.

**Overall Assessment**: Adequate -- with targeted improvements, can reach Strong

**Key Findings**:
- Clean module decomposition with well-defined responsibilities per class
- Strong test coverage by line count (test:source ratio > 1:1)
- Concurrency model has known edge cases documented in MEMORY.md but not yet protected in core code
- Streaming events are fully defined but not integrated into Robot#run or Network#run
- Some dead abstractions (adapters directory referenced in test_helper but not in lib)

**Critical Actions**:
- Wire streaming context into Robot#run and Network#run, or remove the streaming module to avoid misleading API surface
- Add processing guards to Robot#run for async re-entrancy protection (documented in MEMORY.md but missing from core)
- Clarify Network execution model: `call_parallel` vs the documented sequential pipeline

---

## System Overview

### File Counts
| Area | Files | Lines |
|------|-------|-------|
| Core lib (`lib/`) | 38 | ~5,050 |
| Tests (`test/`) | 26 | ~5,425 |
| Examples | 15+ scripts | N/A |

### Dependency Graph (Core)

```
RobotLab (module)
  ├── Config (MywayConfig::Base)
  │     └── configures RubyLLM + PromptManager
  ├── Robot (RubyLLM::Agent)
  │     ├── TemplateRendering (module)
  │     ├── MCPManagement (module)
  │     └── BusMessaging (module)
  ├── Network
  │     ├── SimpleFlow::Pipeline
  │     ├── Task (step wrapper)
  │     └── Memory (shared)
  ├── Memory
  │     ├── Waiter (ConditionVariable)
  │     ├── StateProxy (method_missing)
  │     ├── MemoryChange (notification)
  │     └── RedisBackend (optional)
  ├── MCP::Client
  │     ├── MCP::Server (config)
  │     └── Transports (Stdio, WebSocket, SSE, StreamableHTTP)
  ├── Tool (RubyLLM::Tool)
  │     ├── AskUser (built-in)
  │     └── ToolManifest (registry)
  ├── Message hierarchy
  │     ├── TextMessage
  │     ├── ToolCallMessage
  │     ├── ToolResultMessage
  │     └── UserMessage
  ├── RobotMessage (Data.define, bus envelope)
  ├── RobotResult (execution result)
  ├── Streaming::Events (constants)
  ├── Streaming::Context (event publisher)
  └── Utils, Errors, ToolConfig
```

---

## Individual Member Reviews

### Systems Architect - Principal Systems Architect

**Perspective**: Evaluates overall structure, module boundaries, and dependency flow

#### Key Observations
- Clean Zeitwerk autoloading with appropriate inflector overrides and ignores
- Robot concern extraction into `TemplateRendering`, `MCPManagement`, and `BusMessaging` modules is well-executed
- The `robot_lab.rb` entry point serves dual duty: Zeitwerk setup and module-level factory methods

#### Strengths
1. **Hierarchical config resolution**: The `ToolConfig` module elegantly handles `:none`, `:inherit`, and explicit values across four levels (global > network > robot > runtime)
2. **Single-responsibility classes**: Memory, StateProxy, Waiter, MemoryChange each have a clear purpose
3. **Clean factory pattern**: `RobotLab.build()` and `RobotLab.create_network()` provide discoverable entry points
4. **Zeitwerk hygiene**: Proper ignores for Rails integration, generators, and Robot concern modules

#### Concerns
1. **Ghost references** (Impact: Medium)
   - Issue: `NetworkRun` is referenced in CLAUDE.md, Robot#run signature, and MCPManagement (`network&.network&.mcp`) but the class doesn't exist in lib/. The `network:` parameter in `Robot#run` expects a `NetworkRun` but receives nil in practice because Network delegates to Task which delegates to Robot#call, not Robot#run directly.
   - Recommendation: Audit `network:` parameter usage in Robot#run -- it appears vestigial. If NetworkRun was removed, clean up the parameter and the `network&.network` calls in MCPManagement.

2. **Adapter directory mismatch** (Impact: Low)
   - Issue: `test_helper.rb` references `'lib/robot_lab/adapters'` in SimpleCov groups, but no `adapters/` directory exists in the current codebase.
   - Recommendation: Remove the stale SimpleCov group or restore the adapters directory if adapters are planned.

3. **Eager loading at boot** (Impact: Medium)
   - Issue: `loader.eager_load` (line 69 of robot_lab.rb) forces all classes to load at require time. For a gem, lazy loading is typically preferred -- eager loading is a Rails convention for avoiding autoloading in multi-threaded environments.
   - Recommendation: Move `eager_load` behind a conditional (`if defined?(Rails)`) or remove it entirely, since Zeitwerk's lazy autoloading handles thread-safety correctly.

4. **Streaming module is orphaned** (Impact: Medium)
   - Issue: `Streaming::Events` and `Streaming::Context` define a rich event vocabulary (22 event types, lifecycle/delta/HITL categories) but nothing in Robot#run or Network#run publishes these events. The streaming subsystem exists as infrastructure without integration.
   - Recommendation: Either wire streaming into the execution path (Robot#run emits `RUN_STARTED`/`TEXT_DELTA`/etc.) or clearly mark it as "planned" with appropriate documentation.

#### Recommendations
1. **Audit and remove NetworkRun references** (Priority: High, Effort: Small)
2. **Make eager_load conditional** (Priority: Medium, Effort: Small)
3. **Integrate or defer streaming** (Priority: Medium, Effort: Large)

---

### Concurrency Specialist - Async & Concurrency Engineer

**Perspective**: Analyzes async patterns, race conditions, and message ordering guarantees

#### Key Observations
- Two concurrency models coexist: thread-based (Memory waiters) and fiber-based (Async for bus messaging)
- `dispatch_async` in Utils correctly checks `Async::Task.current?` before choosing execution strategy
- MEMORY.md documents the critical async re-entrancy bug but the fix is NOT implemented in core Robot class

#### Strengths
1. **Waiter implementation is correct**: Uses Mutex + ConditionVariable with proper signaled flag to avoid missed wakeups. Timeout calculation uses monotonic-safe arithmetic.
2. **Bus publish safety**: `publish_to_bus` correctly avoids double-wrapping in Async by checking `Async::Task.current?`
3. **Memory thread-safety**: All Memory read/write operations are protected by `@mutex`

#### Concerns
1. **Async re-entrancy in Robot#run** (Impact: High)
   - Issue: When a robot's `run()` yields during HTTP I/O (via RubyLLM), the Async scheduler can switch to another fiber that delivers a bus message to the same robot. This calls `handle_message_via_llm` which calls `run()` again, inserting user messages between `tool_use`/`tool_result` pairs in `@chat`, corrupting Anthropic API ordering. This is documented in MEMORY.md but the processing guard is NOT in `Robot#run` or `BusMessaging#handle_incoming_delivery`.
   - Recommendation: Add a `@processing` guard and `@queue` to Robot, serializing `run()` calls. The pattern from `examples/14_rusty_circuit/scout.rb` should be promoted to core.

2. **dispatch_async Thread leak** (Impact: Medium)
   - Issue: In `Utils#dispatch_async`, when NOT inside Async, it spawns a bare `Thread.new`. These threads are fire-and-forget with no join, no pool, and no lifecycle management. Under heavy subscription activity in Memory, this could create unbounded threads.
   - Recommendation: Use a thread pool (e.g., `Concurrent::FixedThreadPool` from concurrent-ruby) or require Async for reactive features.

3. **Memory#set + notify is not atomic** (Impact: Medium)
   - Issue: `Memory#set` stores the value inside `@mutex.synchronize`, then releases the mutex before calling `wake_waiters` and `notify_subscribers_async`. Between the mutex release and the notification, another thread could read the old value from a different subscriber callback.
   - Recommendation: This is acceptable for eventual consistency but should be documented as such.

4. **Mutex ordering risk** (Impact: Low)
   - Issue: Memory uses `@mutex`, `@subscription_mutex`, and `@waiter_mutex`. The locking order is generally consistent (main > subscription > waiter), but `notify_subscribers_async` acquires `@subscription_mutex` after releasing `@mutex`. If a subscriber callback re-enters Memory (calls `set` or `get`), this could deadlock.
   - Recommendation: Document the locking contract. Consider using a single mutex or ensure subscribers always dispatch asynchronously (which they do via `dispatch_async`, mitigating this in practice).

#### Recommendations
1. **Promote processing guard from example to core** (Priority: High, Effort: Small)
2. **Replace bare Thread.new with a pool** (Priority: Medium, Effort: Small)
3. **Document concurrency contract for Memory** (Priority: Medium, Effort: Small)

---

### API Design Lead - Developer Experience Architect

**Perspective**: Evaluates public API surface, developer experience, and Ruby idiomaticness

#### Key Observations
- Builder/factory pattern (`RobotLab.build`) is clean and discoverable
- `with_*` chaining on Robot delegates to chat and returns `self` -- idiomatic Ruby
- Template system with YAML front matter is elegant for prompt engineering workflows
- `on_message` block arity detection (1 arg = auto-ack, 2 args = manual) is clever and well-documented

#### Strengths
1. **Progressive disclosure**: Simple use (`RobotLab.build.run("Hello")`) to complex (`Robot.new` with 20+ params)
2. **Consistent to_h/to_json**: Every domain object serializes cleanly
3. **Smart defaults**: `name: "robot"`, `enable_cache: true`, `mcp: :none`
4. **RobotMessage as Data.define**: Immutable value object with composite `key` -- excellent

#### Concerns
1. **Constructor parameter overload** (Impact: Medium)
   - Issue: `Robot#initialize` takes 20 keyword parameters. While each has a sensible default, the signature is intimidating and hard to scan. Some parameters are only relevant in specific contexts (e.g., `mcp_servers` is legacy, `bus` only for multi-robot).
   - Recommendation: Consider a builder pattern or configuration object for advanced parameters. The `with_*` chaining pattern already exists -- lean into it: `RobotLab.build(name: "bot").with_bus(bus).with_template(:helper)`.

2. **Dual system prompt path** (Impact: Low)
   - Issue: `system_prompt:` in constructor AND template body both set instructions via `@chat.with_instructions`. If both are provided, the system prompt is appended after the template -- but this isn't documented.
   - Recommendation: Document the interaction explicitly: "template body renders first, then system_prompt is appended."

3. **`run` method overloading** (Impact: Medium)
   - Issue: `Robot#run` accepts a `message`, plus `network:`, `network_memory:`, `memory:`, `mcp:`, `tools:`, and `**kwargs`. The `kwargs` serve double duty: they're passed to template re-rendering AND to `ask()` (via `kwargs.slice(:with)`). This coupling is confusing.
   - Recommendation: Split template context from ask options more explicitly, e.g., `run(message, context: {}, with: [])`.

4. **`send_message` vs `send_reply` naming** (Impact: Low)
   - Issue: `send_message` creates a new message; `send_reply` creates a reply. Both return `RobotMessage`. The naming is clear, but neither is "send" in the IO sense -- they publish to a bus channel. `publish_message` / `publish_reply` would be more accurate.
   - Recommendation: Keep current names for API stability but document that "send" means "publish to bus channel."

#### Recommendations
1. **Document template + system_prompt interaction** (Priority: Medium, Effort: Small)
2. **Consider builder pattern for Robot construction** (Priority: Low, Effort: Medium)
3. **Clarify kwargs routing in Robot#run** (Priority: Medium, Effort: Small)

---

### Reliability Engineer - Error Handling & Resilience Specialist

**Perspective**: Assesses error handling, failure modes, and system resilience

#### Key Observations
- Error hierarchy is clean: `Error < StandardError` with 5 specific subclasses
- `Errors` module provides serialization/deserialization and `capture` wrapper
- MCP connection failures are logged-and-continued, not raised -- good for optional integrations

#### Strengths
1. **Graceful MCP degradation**: `MCP::Client#connect` catches exceptions and sets `@connected = false`, allowing the robot to function without MCP tools
2. **Error hierarchy covers all domains**: Config, Tool, Inference, MCP, Bus
3. **Waiter timeout produces clear exception**: `AwaitTimeout` with message including key name and timeout value
4. **Errors.capture utility**: Clean pattern for wrapping blocks in `{ data: result }` / `{ error: serialized }` envelopes

#### Concerns
1. **Silent thread errors in dispatch_async** (Impact: High)
   - Issue: `Utils#dispatch_async` wraps Thread failures in `warn "RobotLab async dispatch error: #{e.message}"` but the error is otherwise swallowed. Memory subscription callbacks that fail will silently drop. The same is true for Async tasks which swallow exceptions.
   - Recommendation: Add an error callback (`on_async_error`) to Memory or provide a global error handler via config.

2. **No retry logic for LLM calls** (Impact: Medium)
   - Issue: `Robot#run` delegates to `RubyLLM::Agent#ask` with no retry wrapper. LLM APIs frequently return 429 (rate limit) or 503 (overloaded). While RubyLLM may have internal retry logic (configurable via `max_retries`), RobotLab doesn't add its own layer for network-level retries or circuit breaking.
   - Recommendation: This is acceptable if RubyLLM handles retries internally (which it does via `max_retries` in config). Document that retry behavior is delegated to RubyLLM's configuration.

3. **MCP Client reconnection** (Impact: Medium)
   - Issue: If an MCP server goes down mid-conversation, `call_tool` raises `MCPError` ("Not connected"). There's no automatic reconnection attempt.
   - Recommendation: Add a `reconnect` method or auto-reconnect on `MCPError` in `call_tool`. For v0.0.5 this is acceptable -- flag for v0.1.0.

4. **Memory.set with nil value** (Impact: Low)
   - Issue: Setting a key to `nil` via `memory.set(:key, nil)` stores nil. But `get_single` treats nil as "not yet available" and enters the wait path. This means you can't intentionally store nil and have waiters receive it.
   - Recommendation: Use a sentinel value or `key?` check instead of `value.nil?` in the wait path.

#### Recommendations
1. **Add configurable async error handler** (Priority: High, Effort: Small)
2. **Document retry delegation to RubyLLM** (Priority: Medium, Effort: Small)
3. **Fix nil-value handling in Memory wait path** (Priority: Medium, Effort: Small)
4. **Add MCP auto-reconnect** (Priority: Low, Effort: Medium)

---

### Testing Strategist - Quality Assurance Architect

**Perspective**: Reviews test architecture, coverage gaps, and testing patterns

#### Key Observations
- Test:source ratio is >1:1 (5,425 test lines vs 5,050 source lines)
- Test helper provides `build_robot`, `build_network`, `build_tool` factories
- `wait_until` helper for async testing with monotonic clock
- Tests use real RubyLLM with dummy API key -- unit tests don't make real API calls

#### Strengths
1. **Good test file correspondence**: Every source file in `lib/robot_lab/` has a matching `_test.rb`
2. **MCP transport tests**: All four transports (stdio, websocket, SSE, HTTP) have dedicated test files
3. **SimpleCov with groups**: Coverage is organized by component area
4. **No VCR/WebMock dependency in test_helper**: Tests are written to be unit-testable without network mocking

#### Concerns
1. **No integration tests visible** (Impact: Medium)
   - Issue: The Rakefile mentions `integration` task but no integration test directory or files are visible. The bus messaging, network pipeline execution, and MCP tool calling would benefit from integration tests.
   - Recommendation: Add integration tests for key workflows: Robot -> Network -> Memory flow, Bus messaging round-trip, MCP tool discovery -> execution.

2. **Streaming module untested** (Impact: Medium)
   - Issue: There is a `streaming_test.rb` but the streaming subsystem is not integrated into execution. Unclear what the test covers since streaming is not wired in.
   - Recommendation: Either test the streaming API contract in isolation or defer until integration.

3. **No test for concurrent Memory access** (Impact: Medium)
   - Issue: Memory's reactive features (subscribe, wait, pattern matching) involve concurrency. Tests should verify thread-safety of subscribe + set, multiple waiters on same key, and timeout behavior.
   - Recommendation: Add multi-threaded Memory stress tests.

4. **Robot test may require network** (Impact: Low)
   - Issue: `robot_test.rb` creates real Robot instances which call `RubyLLM::Agent#initialize` and set up a persistent chat. If RubyLLM's agent init makes network calls (model validation, etc.), tests could be flaky.
   - Recommendation: Verify that Robot construction is fully offline with the test API key. If not, stub RubyLLM initialization.

#### Recommendations
1. **Add integration test suite** (Priority: High, Effort: Medium)
2. **Add concurrent Memory tests** (Priority: Medium, Effort: Small)
3. **Verify Robot construction is offline-safe** (Priority: Medium, Effort: Small)

---

### Pragmatic Enforcer - YAGNI & Simplicity Advocate

**Perspective**: Challenges unnecessary complexity and advocates for simplest viable solutions

#### Key Observations
- At v0.0.5, the framework has an appropriate scope for what it does
- Some infrastructure is built ahead of need (streaming, Redis backend, adapters references)
- The core Robot -> Network -> Memory flow is solid and well-tested

#### Pragmatic Analysis

| Feature | Necessity (0-10) | Complexity (0-10) | Ratio | Recommendation |
|---------|-----------------|-------------------|-------|----------------|
| Robot core | 10 | 4 | 0.4 | **Implement** |
| Network/Pipeline | 9 | 5 | 0.6 | **Implement** |
| Memory (reactive) | 8 | 6 | 0.8 | **Implement** |
| Bus messaging | 7 | 5 | 0.7 | **Implement** |
| MCP integration | 7 | 6 | 0.9 | **Implement** |
| Tool hierarchy | 6 | 3 | 0.5 | **Implement** |
| Streaming events | 4 | 4 | 1.0 | **Defer** -- not wired in |
| Redis backend | 3 | 3 | 1.0 | **Defer** -- no users yet |
| ToolManifest | 3 | 2 | 0.7 | **Simplify** -- used? |
| Adapters (absent) | 2 | 0 | 0.0 | **Remove references** |
| UserMessage | 4 | 2 | 0.5 | **Keep** -- small cost |

#### Concerns
1. **Streaming infrastructure without consumers** (Pragmatic Score: 1.0)
   - Issue: 95 lines of code (Events + Context + SequenceCounter) defining 22 event types that nothing publishes. This is pure speculative infrastructure.
   - Recommendation: Remove or move to a branch. Reintroduce when streaming is actually needed. Cost of waiting: near zero (the design is clean and can be re-created quickly).

2. **RedisBackend built but unused** (Pragmatic Score: 1.0)
   - Issue: RedisBackend is 50 lines that implement a key-value interface on Redis. But no tests exercise it, no examples use it, and the auto-detection path silently falls back to Hash. It's dead weight that creates maintenance burden.
   - Recommendation: Remove from core. Add as an optional extension gem or bring back when a use case materializes.

3. **ToolManifest may be over-built** (Pragmatic Score: 0.7)
   - Issue: ToolManifest provides Enumerable, merge, replace, fetch-with-error, has?, count, length, clear, from_hash -- a full collection API. But it's unclear if anything uses it in the execution path (Robot uses `@local_tools + @mcp_tools` arrays directly).
   - Recommendation: Check if ToolManifest is used. If only for external API, simplify to a thin lookup wrapper.

4. **Message type system is well-sized** (Pragmatic Score: 0.5)
   - The Message/TextMessage/ToolCallMessage/ToolResultMessage hierarchy is exactly as complex as it needs to be. Good balance.

#### Recommendations
1. **Remove or defer streaming module** (Priority: Medium, Effort: Small)
2. **Remove RedisBackend** (Priority: Low, Effort: Small)
3. **Audit ToolManifest usage** (Priority: Low, Effort: Small)

---

## Collaborative Discussion

### Consensus Points

All reviewers agree on:
1. **Core architecture is sound**: Robot, Network, Memory separation of concerns is clean and appropriate
2. **Async re-entrancy is the highest-risk issue**: The documented-but-not-implemented processing guard needs to be in core, not just examples
3. **Test coverage is strong by ratio** but lacks integration and concurrency testing
4. **Streaming infrastructure is premature**: Should be deferred or removed

### Points of Debate

- **Systems Architect** wants eager_load removed; **Reliability Engineer** notes it prevents autoloading race conditions in multi-threaded environments. **Consensus**: Make it conditional on Rails.
- **API Design Lead** suggests builder pattern for Robot; **Pragmatic Enforcer** counters that the existing `with_*` chaining is already a builder pattern and adding another layer would be over-engineering. **Consensus**: Document `with_*` chaining as the recommended construction pattern.
- **Concurrency Specialist** wants a thread pool; **Pragmatic Enforcer** notes this adds a concurrent-ruby dependency. **Consensus**: Require Async for reactive features (it's already a dependency), removing the Thread.new fallback.

---

## Consolidated Findings

### Strengths
1. **Clean module decomposition**: Each class has one responsibility; concerns are extracted into modules
2. **Excellent serialization**: Every domain object implements `to_h`, `to_json`, `from_hash` consistently
3. **Progressive complexity**: Simple `build.run` for basic use; full Network+Memory+Bus for complex orchestration
4. **Test discipline**: >1:1 test-to-source ratio with per-class test coverage
5. **Configuration elegance**: 4-level hierarchical resolution with `:inherit`/`:none` semantics

### Areas for Improvement
1. **Async safety**: Processing guard in Robot, thread pool in Utils, nil-value handling in Memory
2. **Dead code**: Streaming module, RedisBackend, adapters references, possible NetworkRun ghosts
3. **Documentation drift**: CLAUDE.md references classes/patterns that don't match current code
4. **Integration testing**: No end-to-end tests for Robot-Network-Memory-Bus workflow

### Technical Debt

**High Priority**:
- Async re-entrancy in Robot#run: Can corrupt LLM API message ordering. Resolution: Add processing guard. Effort: Small.

**Medium Priority**:
- Streaming module is orphaned: Adds 95 lines of unmaintained infrastructure. Resolution: Remove or integrate. Effort: Small-Medium.
- Thread leak in dispatch_async: Can create unbounded threads. Resolution: Use Async everywhere. Effort: Small.
- Memory nil-value ambiguity: Can't distinguish "not set" from "set to nil". Resolution: Use sentinel. Effort: Small.

**Low Priority**:
- RedisBackend untested and unused: 50 lines of dead weight. Resolution: Remove. Effort: Small.
- ToolManifest possibly unused: Full collection API that may not be called. Resolution: Audit. Effort: Small.

### Risks

**Technical Risks**:
- **LLM API ordering corruption**: Likelihood: Medium (requires async + bus), Impact: High, Mitigation: Processing guard
- **Thread exhaustion**: Likelihood: Low (requires many subscriptions), Impact: Medium, Mitigation: Thread pool or Async-only
- **RubyLLM breaking changes**: Likelihood: Medium (< 1.0 dependency), Impact: High, Mitigation: Pin version more tightly

---

## Recommendations

### Immediate (0-2 weeks)
1. **Add processing guard to Robot#run**: Promote the `@processing` + `@queue` pattern from `examples/14_rusty_circuit/scout.rb` into `Robot` or `BusMessaging`. This prevents the async re-entrancy bug that corrupts Anthropic API message ordering.
   - Success Criteria: Bus message delivery during an active `run()` queues instead of interleaving
2. **Clean up ghost references**: Remove `NetworkRun` references from Robot#run params and MCPManagement. Update CLAUDE.md to match current code.
   - Success Criteria: No references to classes that don't exist
3. **Fix Memory nil-value handling**: Use `@backend.key?(key)` instead of `value.nil?` in `get_single` wait path.
   - Success Criteria: `memory.set(:key, nil)` wakes waiters

### Short-term (2-8 weeks)
1. **Remove or gate streaming module**: Move `Streaming::Events`, `Streaming::Context`, and `Streaming::SequenceCounter` behind a feature flag or remove entirely until streaming is integrated.
   - Success Criteria: No orphaned infrastructure code
2. **Replace Thread.new fallback in dispatch_async**: Require callers to be inside Async for reactive features, or use a bounded thread pool.
   - Success Criteria: No unbounded thread creation
3. **Add integration tests**: Test Robot-Network-Memory pipeline, Bus messaging round-trip, and concurrent Memory access.
   - Success Criteria: CI runs integration suite without hanging
4. **Add configurable error handler**: `RobotLab.configure { |c| c.on_async_error = ->(e) { ... } }` for async dispatch errors.
   - Success Criteria: Errors in subscription callbacks are reportable

### Long-term (2-6 months)
1. **Integrate streaming into execution**: Wire `Streaming::Context` into `Robot#run` and `Network#run` to emit lifecycle and delta events. This enables real-time UIs and debugging tools.
   - Success Criteria: `robot.run("Hello") { |event| ... }` yields streaming events
2. **Add MCP auto-reconnect**: Implement connection health checks and automatic reconnection in MCP::Client.
   - Success Criteria: Transient MCP server restarts don't break long-running robot sessions
3. **Formalize Network execution model**: Document whether Network runs robots sequentially, in parallel, or via the dependency graph in SimpleFlow. Clarify `call_parallel` vs `call` semantics.
   - Success Criteria: Users can predict execution order from Network definition

---

## Success Metrics
1. **Zero async re-entrancy bugs**: Current: documented but unprotected -> Target: guard in core (2 weeks)
2. **Dead code ratio**: Current: ~145 lines of orphaned streaming/Redis -> Target: 0 lines (4 weeks)
3. **Integration test count**: Current: 0 -> Target: 5+ workflows covered (6 weeks)
4. **Doc accuracy**: Current: CLAUDE.md references missing classes -> Target: 100% accurate (2 weeks)

---

## Follow-up
**Next Review**: After v0.1.0 release or 3 months, whichever comes first
**Tracking**: Create issues for Immediate and Short-term recommendations

## Related Documentation
- `CLAUDE.md`: Project instructions (needs update for removed classes)
- `MEMORY.md`: Documents async re-entrancy bug and workarounds
- `examples/14_rusty_circuit/`: Reference implementation for processing guard pattern
- `examples/15_memory_network_and_bus/`: Reference for network + bus workflow
