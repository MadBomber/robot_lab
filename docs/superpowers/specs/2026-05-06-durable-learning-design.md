# Durable Learning for RobotLab

**Date**: 2026-05-06
**Status**: Draft

## Problem

Robots built with RobotLab have no memory between sessions and no mechanism for improving their judgment over time. Each run starts from zero. The newsletter reader robot is the motivating case: it should get better at deciding what content belongs in the Obsidian PKM vault without requiring the user to explain their preferences every time.

## Goals

- Robots accumulate knowledge within a session (explicit during operation, reflection at end)
- Knowledge persists across sessions and across projects
- Conservative bias: when uncertain and no relevant past learning exists, skip rather than guess
- Human-readable, auditable, directly editable storage
- General capability — not newsletter-specific

## Non-goals

- Automated curator/consolidation (YAGNI for now)
- Confidence decay over time (YAGNI for now)
- Fine-tuning or model-level learning (out of scope)

---

## Design

### `RobotLab::Durable::Entry`

A single knowledge record. Immutable value object (Ruby `Data.define`).

| Field        | Type    | Description                                                    |
|--------------|---------|----------------------------------------------------------------|
| `content`    | String  | The fact, pattern, or preference learned, in plain language    |
| `reasoning`  | String  | Why — captured from discussion or observation                  |
| `category`   | Symbol  | `:fact`, `:preference`, `:pattern`, `:correction`              |
| `domain`     | String  | Topic area ("Ruby tooling", "newsletter curation")             |
| `confidence` | Float   | 0.1 initial, increments by 0.1 each confirmed application, max 1.0 |
| `use_count`  | Integer | Times recalled and applied                                     |
| `created_at` | String  | ISO8601 timestamp                                              |
| `updated_at` | String  | ISO8601 timestamp                                              |

### `RobotLab::Durable::Store`

Reads and writes `Entry` records. Storage: Markdown files with YAML frontmatter in `lib/robot_lab/durable/`, one file per domain (e.g., `newsletter_curation.md`, `ruby_tooling.md`).

File format mirrors the Obsidian PKM convention — intentionally familiar:

```markdown
---
domain: newsletter curation
entries:
  - content: Skip LangChain content
    reasoning: User is Ruby-only and considers Python tooling irrelevant
    category: preference
    confidence: 0.4
    use_count: 3
    created_at: "2026-05-06T12:00:00Z"
    updated_at: "2026-05-06T14:30:00Z"
---
```

Key methods:
- `recall(query:, domain: nil, min_confidence: 0.0)` — returns relevant entries, sorted by confidence
- `record(entry)` — appends or updates an entry in the appropriate domain file
- `confirm(entry)` — increments `confidence` by 0.1 and `use_count` by 1, updates `updated_at`

Matching strategy: keyword overlap on `content` + `domain` fields. Semantic search via fastembed is a future enhancement.

### `RobotLab::Durable::Reflector`

A lightweight robot that runs at session end. Receives the session's `Memory` (messages, results, data) and the existing `Store`. Its job: identify observations from the session worth promoting to durable knowledge and call `store.record` for each.

Implemented as a `RobotLab.build` robot with a focused system prompt. Uses `RecordKnowledge` tool internally.

### `RobotLab::Durable::Learning` (mixin)

Included in a `Robot` to activate learning capability.

```ruby
robot = RobotLab.build(
  name: "newsletter_analyst",
  system_prompt: "...",
  local_tools: [FetchLatestNewsletter],
  learn: true,         # activates Durable::Learning
  learn_domain: "newsletter curation"
)
```

What the mixin does:
1. Adds `RecallKnowledge` and `RecordKnowledge` to the robot's tool list
2. Runs a `recall` pass on session start, injecting relevant entries as context
3. Registers an `on_session_end` hook that triggers `Durable::Reflector`

### `RecallKnowledge` tool

The robot calls this before acting on anything uncertain.

```
Input:  query (String), domain (String, optional)
Output: Array of matching Entry records as formatted context
```

### `RecordKnowledge` tool

The robot calls this during the session when it judges something worth keeping.

```
Input:  content, reasoning, category, domain
Output: confirmation the entry was written
```

---

## Learning Loop

```
Session start
  └─ Store.recall → inject relevant entries as context

During session
  └─ Robot discusses/decides
  └─ Robot calls RecordKnowledge (explicit, in-moment captures)
  └─ Robot calls RecallKnowledge before uncertain decisions
  └─ On confirmed application → Store.confirm (confidence++)

Session end
  └─ Reflector reviews session Memory
  └─ Promotes observations not yet explicitly recorded
  └─ Writes to Store
```

---

## Conservative Bias

When `recall_knowledge` returns no relevant entries AND the robot's confidence on a candidate decision is below 0.5, the robot skips the action and logs the reason. This is enforced through system prompt guidance, not framework code.

---

## Storage Location

`lib/robot_lab/durable/` — already exists as a placeholder. Domain files live here:

```
lib/robot_lab/durable/
  newsletter_curation.md
  ruby_tooling.md
  ...
```

---

## Newsletter Reader Integration

The newsletter robot uses `learn: true, learn_domain: "newsletter curation"`. Its workflow:

1. Fetch newsletter RSS
2. Follow links one level deep, extract article content
3. For each article: `RecallKnowledge` to check against past decisions
4. High-confidence match → act autonomously (include or skip)
5. No match or low confidence → skip and log
6. Discussion with user → `RecordKnowledge` captures reasoning
7. Session end → `Reflector` promotes any missed observations

Over time, the confidence on frequently-confirmed patterns rises, and the robot handles more autonomously with fewer discussions required.

---

## Files to Create

| File | Purpose |
|------|---------|
| `lib/robot_lab/durable/entry.rb` | `Entry` data class |
| `lib/robot_lab/durable/store.rb` | Read/write/confirm operations |
| `lib/robot_lab/durable/reflector.rb` | End-of-session reflection robot |
| `lib/robot_lab/durable/learning.rb` | `Learning` mixin for Robot |
| `lib/robot_lab/tools/recall_knowledge.rb` | `RecallKnowledge` tool |
| `lib/robot_lab/tools/record_knowledge.rb` | `RecordKnowledge` tool |
| `test/robot_lab/durable/entry_test.rb` | Unit tests |
| `test/robot_lab/durable/store_test.rb` | Unit tests |
| `examples/32_newsletter_reader.rb` | Updated with `learn: true` |
