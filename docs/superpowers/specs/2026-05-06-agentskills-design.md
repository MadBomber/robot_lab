# AgentSkills.io Support — Design Spec

**Date:** 2026-05-06
**Status:** Approved

## Overview

Add support for the [AgentSkills.io](https://agentskills.io) open standard to RobotLab's existing skills system. Skills are currently single `.md` prompt_manager template files referenced by symbol ID. This spec extends `skills:` to also recognize the AgentSkills folder format (`~/.prompts/skills/<name>/SKILL.md`) with bundled scripts auto-exposed as tools and runtime embedding-based matching for progressive disclosure.

## Goals

- Unified `skills:` API — no new constructor params; format detected automatically
- AgentSkills folder skills use runtime embedding similarity to decide injection per `run()` call
- Scripts in `scripts/` auto-wrapped as `RobotLab::Tool` subclasses
- Zero breakage to existing PM template skills behavior
- Graceful degradation when embeddings fail or no skills match

## Non-Goals

- Automatic catalog-wide skill discovery without explicit `skills:` listing
- Fetching remote skills from registries
- Skills referencing `references/` or `assets/` sub-folders (deferred)
- Modifying the AgentSkills.io specification

---

## Discovery Path

AgentSkill folders are resolved from a single fixed root: `~/.prompts/skills/`. Given `skills: [:check_style]`, the loader checks `~/.prompts/skills/check_style/SKILL.md`. If that file exists, it is an AgentSkill. If not, the existing PM template resolution applies.

This root is not configurable in v1.

---

## New Classes

### `RobotLab::AgentSkill`

Plain Ruby value object. Constructed by the catalog or the expand_skills loader.

```
AgentSkill
  name:         String       # from SKILL.md front matter
  description:  String       # from SKILL.md front matter — used for embedding
  path:         Pathname     # directory path
  instructions: String       # lazy: SKILL.md body — everything after the closing ---
  scripts:      Array<Pathname>  # lazy: glob of scripts/*
```

- `instructions` and `scripts` are loaded on first access (lazy).
- Raises `RobotLab::ConfigurationError` on construction if `SKILL.md` is missing `name` or `description`.
- `description_vector` — memoized fastembed **passage** embedding of `description` (`DocumentStore#passage_vector`), computed on first match attempt.

### `RobotLab::AgentSkillCatalog`

Module-level singleton (`RobotLab::AgentSkillCatalog`). Scans `~/.prompts/skills/` at process start (lazy, on first access). Caches `AgentSkill` objects keyed by name symbol.

Responsibilities:
- `find(id)` — return `AgentSkill` for a given symbol, or `nil`
- `all` — return all discovered skills
- Internal: compute and cache description vectors using the `DocumentStore` fastembed infrastructure

### `RobotLab::AgentSkillMatching`

Module included in `Robot`. Contains the `run()` override and the similarity logic.

### `RobotLab::ScriptTool`

Factory method `ScriptTool.from_path(path)` returns an anonymous `RobotLab::Tool` subclass. The tool:
- Name: script filename without extension, underscored (e.g. `check_style`)
- Description: first comment line of the script, or `"Run #{name}"`
- Execution: shells out via `Open3.capture2e`, returns stdout+stderr as the tool result
- Raises `RobotLab::ToolNotFoundError` if the script is not executable

---

## Modified Code

### `Robot::TemplateRendering#expand_skills`

Before resolving a skill ID as a PM template, check `AgentSkillCatalog.find(skill_id)`:

```
expand_skills([:runbook_protocol, :check_style], visited)
  :runbook_protocol → catalog.find → nil → PM template (existing path)
  :check_style      → catalog.find → AgentSkill<check_style>
                       → store in @pending_agent_skills
                       → do NOT add to @expanded_skills
```

`@expanded_skills` continues to hold only PM-format skill IDs, preserving all existing behavior.

### `Robot` constructor

Add `@pending_agent_skills = []` alongside `@expanded_skills = nil`.

### `Robot::AgentSkillMatching#run`

Prepended to `Robot` to intercept `run()`:

```ruby
def run(message, **kwargs)
  activated = match_agent_skills(message)
  inject_agent_skills(activated)
  super
ensure
  restore_after_agent_skills(activated)
end
```

**`match_agent_skills(message)`**
1. Return `[]` if `@pending_agent_skills` is empty
2. Embed `message` as a **query** vector (`DocumentStore#query_vector`) — distinct from the passage embedding used for skill descriptions
3. For each pending AgentSkill, compute cosine similarity between message query-vector and `skill.description_vector` (passage-vector)
4. Return skills where similarity >= `SIMILARITY_THRESHOLD` (default: `0.70`)

**`inject_agent_skills(skills)`**
1. Prepend each skill's `instructions` to the chat's system prompt (using `with_instructions`)
2. Instantiate `ScriptTool` for each script in each skill's `scripts/`; add to `@local_tools`

**`restore_after_agent_skills(skills)`**
1. Remove injected script tools from `@local_tools`
2. Restore system prompt to pre-injection state

The system prompt is snapshotted before injection and restored in the `ensure` block so state does not accumulate across calls.

---

## SKILL.md Format

Follows the AgentSkills.io specification. Front matter is YAML; body is Markdown.

```markdown
---
name: check_style
description: Review Ruby code style against project conventions
---
When reviewing code, check for:
- Frozen string literal comments
- Method length under 20 lines
- No inline rescue
```

RobotLab reads only `name` and `description` from front matter. All other front matter keys are ignored (no LLM config via SKILL.md — that remains the PM template system's domain).

---

## Script Tools

Given `~/.prompts/skills/check_style/scripts/run_rubocop.sh`:

- Tool name: `run_rubocop`
- Description: first `# comment` line in the file, else `"Run run_rubocop"`
- Input: optional `args` string passed as CLI arguments
- Execution: `Open3.capture2e("bash #{path} #{args}")`, returns combined output
- Not executable → log warn, skip (no error raised to the robot)

---

## Similarity Threshold

Default: `0.70` (cosine similarity, 0..1 range).

Accessible as `RobotLab::AgentSkillMatching::SIMILARITY_THRESHOLD`. Not yet user-configurable in v1; a future `config.agent_skill_threshold` can override it.

---

## Error Handling

| Situation | Behavior |
|---|---|
| `SKILL.md` missing `name` or `description` | `ConfigurationError` raised at catalog load |
| fastembed fails on message | Log warn, skip all AgentSkill injection for that call |
| Script not executable | Log warn, skip that tool; other scripts still wrap |
| No skills match threshold | Normal `run()` with no injection |
| Circular skill reference via AgentSkill | Existing cycle detection in `expand_skills` handles it |

---

## Testing

### Unit tests (`test/robot_lab/agent_skill_test.rb`)
- Parses `SKILL.md` front matter correctly
- Raises `ConfigurationError` when `name` or `description` missing
- `instructions` lazy-loads body content
- `scripts` lazy-globs `scripts/` directory

### Unit tests (`test/robot_lab/agent_skill_catalog_test.rb`)
- Scans fixture skills directory
- `find` returns correct `AgentSkill` by symbol
- `find` returns `nil` for unknown ID

### Unit tests (`test/robot_lab/script_tool_test.rb`)
- `from_path` produces a tool with correct name and description
- Tool execution returns stdout+stderr
- Non-executable script skipped with warning

### Unit tests (`test/robot_lab/robot/agent_skill_matching_test.rb`)
- `match_agent_skills` returns skills above threshold (mock embeddings)
- `match_agent_skills` returns empty when below threshold
- `inject_agent_skills` prepends instructions to system prompt
- `restore_after_agent_skills` removes injected tools and restores prompt
- Empty `@pending_agent_skills` short-circuits without embedding

### Integration tests (`test/robot_lab/robot_test.rb`)
- Robot with `skills: [:pm_template, :agent_skill_fixture]` correctly expands PM template eagerly and AgentSkill at runtime
- AgentSkill scripts appear in tool list during run, absent after

### Fixtures
- `test/fixtures/skills/test_skill/SKILL.md` — valid skill
- `test/fixtures/skills/bad_skill/SKILL.md` — missing description
- `test/fixtures/skills/scripted_skill/SKILL.md` + `scripts/hello.sh`

---

## File Layout

```
lib/robot_lab/
  agent_skill.rb                   # AgentSkill value object
  agent_skill_catalog.rb           # Singleton scanner/registry
  script_tool.rb                   # ScriptTool factory
  robot/
    agent_skill_matching.rb        # run() override mixin

test/robot_lab/
  agent_skill_test.rb
  agent_skill_catalog_test.rb
  script_tool_test.rb
  robot/
    agent_skill_matching_test.rb

test/fixtures/skills/
  test_skill/SKILL.md
  bad_skill/SKILL.md
  scripted_skill/SKILL.md
  scripted_skill/scripts/hello.sh
```

---

## Open Questions (deferred)

- `references/` and `assets/` subdirectories: make content available as context variables in future
- User-configurable similarity threshold via `RobotLab.config`
- Auto-catalog mode: discover all skills without explicit `skills:` listing
- AgentSkill nesting (a SKILL.md referencing other skill IDs)
