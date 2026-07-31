# API Reference

Complete API documentation for RobotLab.

## Core Classes

The fundamental building blocks of RobotLab:

| Class | Description |
|-------|-------------|
| [Robot](core/robot.md) | LLM-powered agent with templates, tools, memory, and MCP |
| [RobotResult](core/result.md) | Value object returned by every `robot.run()` |
| [Network](core/network.md) | Orchestrates multiple robots as a SimpleFlow pipeline |
| [Memory](core/memory.md) | Reactive key-value store for sharing data |
| [StateProxy](core/state.md) | Hash/method-access wrapper returned by `memory.data` |
| [Tool](core/tool.md) | Custom function robots can call |
| `RunConfig` | Shared LLM / tool / infrastructure configuration — see [Robot: RunConfig](core/robot.md#runconfig) |

There is **no** `RobotLab::State` class and no `RobotLab::NetworkRun` class. Runtime
state lives in `Memory`; `memory.data` returns a `StateProxy`.

## Hooks

The framework's extension seam — `Hooks.run` brackets every robot run, network
run, task, LLM generation, tool call, compaction, and `learn` call:

| Class | Description |
|-------|-------------|
| [Hook](hooks.md#robotlabhook) | Handler base class; subclasses implement hooks as class methods |
| [HookRegistry](hooks.md#robotlabhookregistry) | The store behind `RobotLab.hooks`, `network.hooks`, `robot.hooks` |
| [Hooks](hooks.md#robotlabhooks) | The dispatcher |
| [HookContext](hooks.md#robotlabhookcontext) | Base context, plus one subclass per family |

## Skills

`SKILL.md` bundles, the scripts they expose as tools, and the sandbox that
confines them:

| Class | Description |
|-------|-------------|
| [AgentSkill](skills.md#robotlabagentskill) | One skill bundle: instructions + `scripts/` |
| [AgentSkillCatalog](skills.md#robotlabagentskillcatalog) | Lazy registry over `~/.prompts/skills/` |
| [Capabilities](skills.md#robotlabcapabilities) | Declared vs. ceiling filesystem / network / timeout grant |
| [ScriptTool](skills.md#robotlabscripttool) | Wraps an executable script as a `Tool` |
| [Sandbox](skills.md#robotlabsandbox) | macOS Seatbelt confinement, or a passthrough |

## Support Classes

Everything else with a public surface — `Task`, `Runnable`, `ToolConfig`,
`ToolManifest`, `Budget::Ledger`, `DoomLoopDetector`, `HistoryCompressor`,
`Convergence`, `TextAnalysis`, `DelegationFuture`, `RobotMessage`, `BusPoller`,
`Waiter`, `Narrator`, `Config`, `MCP::ServerDiscovery`,
`MCP::ConnectionPoller`, and `Streaming::SequenceCounter` — is documented on the
[Support Classes](support.md) page.

## Messages

Message types for LLM communication:

| Class | Description |
|-------|-------------|
| [UserMessage](messages/user-message.md) | User input with metadata |
| [TextMessage](messages/text-message.md) | Text message with role |
| [ToolCallMessage](messages/tool-call-message.md) | Tool execution request |
| [ToolResultMessage](messages/tool-result-message.md) | Tool execution result |

## MCP (Model Context Protocol)

Connect to external tool servers:

| Class | Description |
|-------|-------------|
| [Client](mcp/client.md) | MCP server connection |
| [Server](mcp/server.md) | Server configuration |
| [Transports](mcp/transports.md) | Connection transports |

## Streaming

Real-time response streaming:

| Class | Description |
|-------|-------------|
| [Context](streaming/context.md) | Streaming context |
| [Events](streaming/events.md) | Event utilities |

## Module Methods

### RobotLab

```ruby
# Configuration
RobotLab.config                      # => Config instance
RobotLab.configure { |c| ... }       # => yields the Config for mutation
RobotLab.reload_config!              # => reload from all sources

# Building
RobotLab.build(name: "robot", template: nil, system_prompt: nil, context: {},
               enable_cache: true, bus: nil, skills: nil, config: nil, **options)
RobotLab.create_network(name:, concurrency: :auto, config: nil) { ... }
RobotLab.create_memory(data: {}, enable_cache: true, **options)

# Rendering a template to a String (not a robot) -- see Building Robots guide
RobotLab.render_template(name, **context)  # => String

# Hooks -- see the Hooks API page
RobotLab.hooks                       # => HookRegistry
RobotLab.on(HandlerClass, context: nil)
RobotLab.clear_hooks!                # => replaces the global registry with a fresh one

# Hook scope (internal plumbing; read by Tool#call)
RobotLab.with_hook_scope(registries, per_run_hooks) { ... }
RobotLab.current_hook_scope          # => { registries:, per_run_hooks: } or nil

# Extensions
RobotLab.register_extension(name, mod)
RobotLab.extension_loaded?(:ractor)  # => Boolean
RobotLab.extension(:ractor)
RobotLab.loaded_extensions           # => Array<Symbol>
```

`with_hook_scope` publishes the active run's registries in a `Thread.current`
slot so a tool executing deep inside RubyLLM's tool loop resolves the same
registries — including the network's and any per-run `hooks:` — instead of
falling back to `[RobotLab.hooks, robot.hooks]`. It is thread-local, so it does
not reach a tool that runs on another thread. See
[Hooks: with_hook_scope](hooks.md#with_hook_scope-current_hook_scope).

!!! warning "Tools and MCP are opt-in per call"
    `Robot#run` defaults to `tools: :none, mcp: :none`. A bare `robot.run("...")`
    sends the LLM **zero** tools and connects **no** MCP servers, even when
    `local_tools:`/`mcp:` were supplied at build time. Pass `tools: :inherit`
    (and `mcp: :inherit`) at *run* time to use what is attached. For a standalone
    robot, do not pass `tools: :inherit` at *build* time — it resolves to an
    allowlist matching nothing. (Inside a network it is the required opt-in to a
    network `config:` list.) See [Robot: Configuration Hierarchy](core/robot.md#configuration-hierarchy).

See individual class documentation for detailed method references.
