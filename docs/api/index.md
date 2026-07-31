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

# Hooks
RobotLab.hooks                       # => HookRegistry
RobotLab.on(HandlerClass, context: nil)
RobotLab.clear_hooks!

# Extensions
RobotLab.register_extension(name, mod)
RobotLab.extension_loaded?(:ractor)  # => Boolean
RobotLab.extension(:ractor)
RobotLab.loaded_extensions           # => Array<Symbol>
```

!!! warning "Tools and MCP are opt-in per call"
    `Robot#run` defaults to `tools: :none, mcp: :none`. A bare `robot.run("...")`
    sends the LLM **zero** tools and connects **no** MCP servers, even when
    `local_tools:`/`mcp:` were supplied at build time. Pass `tools: :inherit`
    (and `mcp: :inherit`) at *run* time to use what is attached. For a standalone
    robot, do not pass `tools: :inherit` at *build* time — it resolves to an
    allowlist matching nothing. (Inside a network it is the required opt-in to a
    network `config:` list.) See [Robot: Configuration Hierarchy](core/robot.md#configuration-hierarchy).

See individual class documentation for detailed method references.
