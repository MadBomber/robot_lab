# API Reference

Complete API documentation for RobotLab.

## Core Classes

The fundamental building blocks of RobotLab:

| Class | Description |
|-------|-------------|
| [Robot](core/robot.md) | LLM-powered agent with personality and tools |
| [Network](core/network.md) | Orchestrates multiple robots |
| [Memory](core/memory.md) | Reactive key-value store for sharing data |
| [Tool](core/tool.md) | Custom function robots can call |

## Messages

Message types for LLM communication:

| Class | Description |
|-------|-------------|
| [UserMessage](messages/user-message.md) | User input with metadata |
| [TextMessage](messages/text-message.md) | Text message with role |
| [ToolCallMessage](messages/tool-call-message.md) | Tool execution request |
| [ToolResultMessage](messages/tool-result-message.md) | Tool execution result |

## Adapters

Provider-specific message conversion:

| Class | Description |
|-------|-------------|
| [Anthropic](adapters/anthropic.md) | Claude models adapter |
| [OpenAI](adapters/openai.md) | GPT models adapter |
| [Gemini](adapters/gemini.md) | Google Gemini adapter |

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

## History

Conversation persistence:

| Class | Description |
|-------|-------------|
| [Config](history/config.md) | History configuration |
| [ThreadManager](history/thread-manager.md) | Thread lifecycle |
| [ActiveRecordAdapter](history/active-record-adapter.md) | Rails adapter |

## Module Methods

### RobotLab

```ruby
# Configuration
RobotLab.config              # => Config instance
RobotLab.reload_config!      # => reload from all sources

# Building
RobotLab.build(name:, template:, system_prompt:, context:, **options)
RobotLab.create_network(name:, concurrency:) { ... }
RobotLab.create_memory(data:, enable_cache:, **options)
```

See individual class documentation for detailed method references.
