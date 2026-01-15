# API Reference

Complete API documentation for RobotLab.

## Core Classes

The fundamental building blocks of RobotLab:

| Class | Description |
|-------|-------------|
| [Robot](core/robot.md) | LLM-powered agent with personality and tools |
| [Network](core/network.md) | Orchestrates multiple robots |
| [State](core/state.md) | Manages conversation and workflow data |
| [Tool](core/tool.md) | Custom function robots can call |
| [Memory](core/memory.md) | Shared key-value store |

## Messages

Message types for LLM communication:

| Class | Description |
|-------|-------------|
| [UserMessage](messages/user-message.md) | User input with metadata |
| [TextMessage](messages/text-message.md) | Assistant text response |
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
RobotLab.configuration
RobotLab.configure { |config| ... }

# Building
RobotLab.build { ... }
RobotLab.create_network { ... }
RobotLab.create_state(...)
```

See individual class documentation for detailed method references.
