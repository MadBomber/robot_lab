# ToolManifest Evolution Plan

## Concept: Dynamic Tool Selection in Pipelines

There is a pattern where the total number of tools available within RobotLab numbers in the hundreds -- too many to send to any single LLM call. A pipeline uses a "selector" robot that reviews the next robot's prompt and determines which tools should be made available. The selected subset is then applied to the target robot via `with_tools(...)`.

### Example Flow

```
Selector Robot (step 1)
  - Receives the user prompt destined for step 2
  - Has access to a summary of all available tools (name + description)
  - Outputs a list of tool names relevant to the task

Target Robot (step 2)
  - Receives the selected tools via with_tools(...)
  - Runs with only the relevant subset (e.g., 5-10 tools instead of hundreds)
```

## Current State

`ToolManifest` (lib/robot_lab/tool_manifest.rb, 218 lines) is a name-keyed Hash wrapper with:
- Lookup by name (`[]`, `fetch`)
- `Enumerable` support
- Merge/replace operations
- Serialization (`to_h`, `to_json`, `from_hash`)

It is not currently used by any production code path. `Robot` stores tools as plain arrays (`@local_tools`, `@mcp_tools`) and `all_tools` concatenates them.

## What It Needs to Become

### 1. Global Registry Entry Point

A singleton or module-level registry where all available tools accumulate:

```ruby
RobotLab.tool_registry  # => ToolManifest (global instance)
RobotLab.tool_registry.add(MyTool)
RobotLab.tool_registry.names  # => ["my_tool", "weather", "calculator", ...]
```

### 2. Metadata for Selection

Categories, tags, or other metadata so the selector robot can reason about which tools are relevant without seeing full schemas:

```ruby
# Registration with metadata
RobotLab.tool_registry.add(MyTool, tags: [:database, :read_only])

# Filtering
RobotLab.tool_registry.tagged(:database)  # => subset manifest
```

### 3. Search-Friendly Summary Output

The selector robot needs a compact summary it can reason over -- name + description pairs, not full JSON schemas:

```ruby
RobotLab.tool_registry.summary
# => [{ name: "get_weather", description: "Get current weather for a location" },
#     { name: "calculate", description: "Performs basic arithmetic" }, ...]
```

### 4. Subset Extraction by Name

Resolve a list of tool names (the selector robot's output) into actual tool objects:

```ruby
names = ["get_weather", "calculate"]  # from selector robot
tools = RobotLab.tool_registry.select_by_names(names)
target_robot.with_tools(tools)
```

### 5. Integration with Robot

`Robot#all_tools` and `with_tools(...)` should accept a ToolManifest or be able to pull from the global registry.

## Design Decisions Still Needed

- Should MCP-discovered tools auto-register in the global manifest?
- How does the selector robot receive the tool summary -- as part of its system prompt, injected into the user message, or via a tool call?
- Should categories/tags be defined on the Tool class itself (e.g., `Tool.create(name: ..., tags: [...])`), or only at registration time?
- Does the manifest need versioning or hot-reload support for long-running processes?

---

## Review Notes

### The Problem Statement is Strong

The "selector robot" pattern — an LLM choosing tools from hundreds based on a compact summary — is a real need. Sending 200+ tool schemas in every API call is both expensive and degrades LLM accuracy. The plan correctly identifies that `ToolManifest` as it exists today is a passive container that nothing actually uses.

### What's Solid

- **Global registry** (section 1) — The right call. Tools currently scatter across `@local_tools` and `@mcp_tools` per-robot with no central view. `RobotLab.tool_registry` is the obvious home.
- **Summary output** (section 3) — Essential for the selector pattern. Name + description pairs are the right granularity for LLM reasoning.
- **Subset extraction** (section 4) — `select_by_names` maps cleanly to what `ToolConfig.filter_tools` already does, but at the registry level.

### Gaps and Concerns

**1. Tags/metadata may be premature.**

Section 2 proposes tags (`tags: [:database, :read_only]`) and `.tagged(:database)` filtering. This adds a classification system that someone has to maintain. In the selector-robot pattern, the LLM is doing the classification — that's the whole point. If you also hand-tag tools, you're duplicating the selector's job.

A simpler alternative: let `summary` be the only interface the selector sees. If you later want pre-filtering (e.g., "only show the selector database-related tools"), add it then. Right now it's YAGNI.

**2. MCP tool auto-registration is the key decision, not a footnote.**

The plan lists "Should MCP-discovered tools auto-register in the global manifest?" as an open question. This is actually the central architectural decision. Looking at `MCPManagement#discover_mcp_tools`, MCP tools are created dynamically per-robot, per-connection. They hold closures over their specific `mcp_client` instance. If you auto-register them globally, you need to handle:

- **Lifecycle** — MCP tools are only valid while their client is connected. The global registry would hold dead references after `disconnect`.
- **Duplicates** — Two robots connecting to the same MCP server would register the same tool names with different client closures.
- **Scope** — An MCP tool created for robot A shouldn't be callable by robot B unless they share the client.

Suggestion: MCP tools should **not** auto-register. The global registry should hold "tool definitions" (name, description, schema) — not live callable instances. The selector robot picks names; the target robot resolves those names against its own live tools.

**3. The plan doesn't address the split between "tool definition" and "tool instance."**

Currently `Tool` is both the definition (name, description, parameters) and the callable (the `execute` method with its closure). For a global registry, you want the definition without the closure. The selector robot doesn't need to call tools — it just needs to read summaries and output names.

This suggests `ToolManifest` should store lightweight descriptors, and `Robot#filtered_tools` continues resolving names to live instances from `all_tools`.

**4. Integration with `Robot#with_tools` needs more thought.**

The plan says "`with_tools(...)` should accept a ToolManifest." But `with_tools` currently delegates to `@chat.with_tools` from RubyLLM, which expects tool class/instance objects. Accepting a manifest means either:

- Converting manifest entries back to tool instances (requires the live tool lookup), or
- Passing tool names and letting the robot resolve internally (which is what `filtered_tools` already does)

The second path is simpler and already mostly works. The plan could just say: "The selector robot outputs tool names. Pass them to `robot.run(..., tools: names)`." That's the existing `tools:` parameter.

**5. Missing: how the selector robot itself gets built.**

The plan describes the pattern but not the API. Is this a special network task type? A built-in robot template? A method on `ToolManifest`? Something like:

```ruby
network = RobotLab.create_network(name: "smart_pipeline") do
  task :selector, selector_robot, depends_on: :none
  task :worker, worker_robot, tools: :from_selector, depends_on: [:selector]
end
```

The `tools: :from_selector` (or similar) is the glue that needs designing.

### Suggested Simplification

Instead of evolving ToolManifest into a full registry with tags, a narrower v1:

1. **`RobotLab.tool_registry`** — Global `ToolManifest` that accumulates tool descriptors (name + description only, no live instances)
2. **`ToolManifest#summary`** — Returns the compact format for selector prompts
3. **`ToolManifest#select_by_names(names)`** — Returns a sub-manifest (already close to what exists)
4. **Auto-registration of local tools at `Robot.new`** — Push descriptors into the registry when robots are created
5. **No auto-registration of MCP tools** — Too coupled to connection lifecycle

Skip tags, skip `with_tools(manifest)` integration, skip hot-reload. Those can come later if needed.
