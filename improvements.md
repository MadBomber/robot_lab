# RobotLab Improvement Ideas — Consolidated & Prioritized

Sources: [waterdrop_improvements.md](waterdrop_improvements.md), [hivemind_ai_improvements.md](hivemind_ai_improvements.md), [aia_improvements.md](aia_improvements.md), [rralph](https://github.com/pcboy/rralph)

---

## Tier 1 — High Impact, Low Effort (Do First)

### ~~1. Per-Robot Token/Cost Tracking~~ ✅ DONE (Phase 1 — PR #11)
**Source**: Hivemind AI

`result.input_tokens` / `result.output_tokens` per run; `robot.total_input_tokens` / `robot.total_output_tokens` cumulative; `robot.reset_token_totals` for batch accounting. Documented in `docs/guides/observability.md`. Demo: `examples/19_token_tracking.rb`.

### ~~2. Tool Loop Circuit Breaker~~ ✅ DONE (Phase 1 — PR #11)
**Source**: Hivemind AI

`max_tool_rounds: N` on any robot raises `RobotLab::ToolLoopError` after N tool calls. `robot.clear_messages` recovers from the dangling `tool_use` state. Documented in `docs/guides/observability.md`. Demo: `examples/20_circuit_breaker.rb`.

### ~~4. Learning Accumulation Loop~~ ✅ DONE (Phase 1 — PR #11)
**Source**: rralph

`robot.learn(text)` with bidirectional substring deduplication. Learnings auto-injected as `LEARNINGS FROM PREVIOUS RUNS:` prefix. Persisted to `memory[:learnings]`. Documented in `docs/guides/observability.md`. Demo: `examples/21_learning_loop.rb`.

### ~~3. Context Window Compression~~ ✅ DONE (Phase 2 — PR #12)
**Source**: AIA (Technique 4 — rated highest impact)

`robot.compress_history(recent_turns:, keep_threshold:, drop_threshold:, summarizer:)` scores old turns against the recent context using stemmed term-frequency cosine similarity (`String#word_hash`). High-relevance turns kept verbatim; medium-relevance turns summarized (optional lambda) or dropped; low-relevance dropped. System/tool messages always pinned. Summary messages preserve original role so user/assistant alternation is maintained. Demo: `examples/22_context_compression.rb`.

---

## Tier 2 — High Impact, Medium Effort

### ~~5. Debate Convergence Detection~~ ✅ DONE (Phase 2 — PR #12)
**Source**: AIA (Technique 1)

`RobotLab::Convergence.similarity(a, b)` — 0.0..1.0 cosine similarity using stemmed TF vectors (`word_hash`). `Convergence.detected?(a, b, threshold: 0.85)` — boolean gate. Uses TF (not TF-IDF) to avoid IDF collapse on 2-doc corpora. Demo: `examples/23_convergence.rb`.

### ~~6. Verification Fast-Path~~ ✅ DONE (Phase 2 — PR #12)
**Source**: AIA (Technique 2)

Documented as a router pattern in `examples/23_convergence.rb`: when verifier A and B scores exceed threshold, the router returns `nil` (halt), skipping the reconciler entirely. `Convergence.detected?` is the gate function.

### ~~7. Structured Delegation~~ ✅ DONE (Phase 3)
**Source**: Hivemind AI

`robot.delegate(to: other_robot, task: "...")` returns the delegatee's `RobotResult` annotated with `delegated_by` (delegator name), `duration` (wall-clock seconds), and token counts. All kwargs forwarded to `run()`. Demo: `examples/24_structured_delegation.rb`.

### ~~8. Memory Subscriber Notification Coalescing~~ ✅ DONE (Phase 3)
**Source**: WaterDrop

`notify_subscribers_async` now batches all callbacks for a given key change into a `@notification_queue` and drains it on a single Async fiber instead of spawning O(subscribers × key_changes) fibers. Race-safe: drainer reschedules itself if new items arrive during the final drain loop.

---

## Tier 3 — High Capability, Higher Effort

### ~~10. Chat History Search~~ ✅ DONE (Phase 4)
**Source**: AIA (Technique 3)

`robot.search_history(query, limit: 5)` — scores every message in `@chat.messages` against the query using stemmed TF cosine similarity (`String#word_hash`). Returns `HistoryResult` Data objects with `text`, `role`, `score`, `index`. Messages shorter than 20 chars are skipped. Raises `DependencyError` when the `classifier` gem is absent. Demo: `examples/25_history_search.rb`.

### ~~11. Embedding-Based Memory Search~~ ✅ DONE (Phase 4)
**Source**: Hivemind AI

`memory.store_document(key, text)` embeds text via `Fastembed::TextEmbedding` (BGE passage embedding) and stores it. `memory.search_documents(query, limit: 5)` embeds the query and returns top-N by cosine similarity. `RobotLab::DocumentStore` is the standalone backing class. Lazy model init — ONNX model downloaded on first use. No optional dependency: `fastembed` is already a core dep. Demo: `examples/26_document_store.rb`.

### 9. MCP Server Discovery Fallback (Semantic)
**Source**: AIA (Technique 5)

Build an LSI index from MCP server names + topic descriptions at startup. Use as a fallback when keyword-based server selection finds no match ("install imagemagick" semantically maps to the `brew` server).

- Fallback only — no conflict with existing routing
- Requires the `classifier` gem and a description field per MCP server config
- Most valuable in environments with many MCP servers

### 10. Chat History Search
**Source**: AIA (Technique 3)

Build an LSI index from accumulated conversation turns. Enable semantic search across history for context recall.

- Training-free via `classifier` gem
- Could be a `Memory` extension: `memory.search_history(query, limit: 5)`
- Useful for long-running robot sessions

### 11. Embedding-Based Memory Search
**Source**: Hivemind AI

Extend Memory from key-value into RAG territory. `memory.store_document(key, text)` embeds and stores; `memory.search(query, limit: 5)` does similarity search.

- RobotLab already depends on `fastembed` and `ruby_llm-semantic_cache`
- Backend: in-memory for small datasets, pgvector for production
- Biggest capability extension but also largest implementation

### ~~12. MCP Client Connection Multiplexing~~ ✅ DONE (Phase 5)
**Source**: WaterDrop

`MCP::ConnectionPoller` multiplexes `IO.select` across all stdio MCP transports. One thread monitors all registered stdout FDs; responses are dispatched to per-request `Thread::Queue` objects. `Client#initialize` accepts `poller:` to opt in; async transports (SSE/WebSocket/StreamableHTTP) are unaffected.

---

## Tier 4 — Specialized / Advanced

### ~~13. Pipe-Based Waiter Wake-up~~ ✅ DONE (Phase 5)
**Source**: WaterDrop

Replaced `Waiter`'s `ConditionVariable` with `IO.pipe` + `IO.select`. Each `Waiter` owns a private pipe; `signal` writes one byte per waiting thread (tracked via `@waiter_count`). Works cleanly with Async's fiber scheduler and has no mutex-contention under load.

### ~~14. Bus-Level Delivery Poller~~ ✅ DONE (Phase 5)
**Source**: WaterDrop

`BusPoller` centralizes per-robot delivery serialization. Each robot's TypedBus subscription delegates to `BusPoller#enqueue`; the poller processes immediately if the robot is idle or queues for drain-after-completion if busy. No background threads — delivery runs in the caller's Async fiber, preserving synchronous test semantics.

### ~~15. Poller Groups (Isolation Strategy)~~ ✅ DONE (Phase 5)
**Source**: WaterDrop

Named groups (`:default`, `:slow`, etc.) registered on `BusPoller` via `add_group`. `Network#task` accepts `poller_group:` keyword; each task's robot is assigned to the group via `robot.assign_bus_poller`. Groups are informational labels — Async natural yielding during LLM calls provides the actual isolation.

---

## Implementation Roadmap

```
Phase 1 (Quick wins — additive, no API breaks)  ✅ COMPLETE — PR #11 merged to develop
  #1 Token tracking                              ✅
  #2 Circuit breaker                             ✅
  #4 Learning accumulation loop                  ✅

Phase 2 (Text analysis toolkit — classifier gem integration)  ✅ COMPLETE — PR #12
  #3 Context window compression                              ✅
  #5 Debate convergence                                      ✅
  #6 Verification fast-path                                  ✅

Phase 3 (Inter-robot patterns)  ✅ COMPLETE
  #7 Structured delegation        ✅
  #8 Memory notification coalescing ✅

Phase 4 (Knowledge & retrieval)  ✅ COMPLETE
  #10 Chat history search          ✅
  #11 Embedding memory search      ✅
  #9 MCP discovery fallback        (deferred — needs multi-MCP-server environments)

Phase 5 (Infrastructure)  ✅ COMPLETE
  #12 MCP multiplexing     ✅
  #13 Pipe-based waiters   ✅
  #14 Bus delivery poller  ✅
  #15 Poller groups        ✅
```

## Notes

- **Phase 1** ✅ shipped — `feat(core): add token tracking, tool loop circuit breaker, and learning accumulation` (PR #11, 98.98% test coverage, 938 tests).
- **Phase 2** ✅ shipped — PR #12, 992 tests, 0 failures, 98.85% coverage. Key insight: use `String#word_hash` TF vectors (not TF-IDF) for direct text similarity — TF-IDF on small corpora collapses shared terms to zero via IDF, giving counter-intuitive results for on-topic comparisons.
- **Phase 2 gem**: use the original `classifier` gem (not the `classifier-reborn` fork — the original author has resumed active development). Optional dependency with `LoadError` guard → `RobotLab::DependencyError`.
- **Phase 3-4** items are capability extensions that make RobotLab more useful for real-world agent applications.
- **Phase 5** items are performance optimizations that only matter at scale. Profile first, optimize second.
- AIA's 5-KB Rule Engine and EDD infrastructure are application-level patterns built *on top of* RobotLab — they don't need library-level changes.
