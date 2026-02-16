# Messages

Message types for LLM conversation representation.

## Overview

RobotLab uses a structured message system to represent conversations between users, assistants, and tools.

```ruby
# User input
user_msg = UserMessage.new("Hello", session_id: "123")

# Assistant response
text_msg = TextMessage.new(role: "assistant", content: "Hi there!")

# Tool interaction
tool = ToolMessage.new(id: "call_1", name: "get_weather", input: { city: "NYC" })
tool_call = ToolCallMessage.new(role: "assistant", tools: [tool])
tool_result = ToolResultMessage.new(tool: tool, content: { data: { temp: 72 } })
```

## Message Hierarchy

```
Message (base)
├── TextMessage         - role + text content
├── ToolCallMessage     - role + Array<ToolMessage>
└── ToolResultMessage   - tool + result content

UserMessage             - Standalone (not a Message subclass)
ToolMessage             - Standalone (not a Message subclass)
```

## Common Interface

All Message subclasses implement:

```ruby
message.role       # => String ("user", "assistant", "tool_result")
message.content    # => String or structured data
message.type       # => String ("text", "tool_call", "tool_result")
message.to_h       # => Hash representation
message.to_json    # => JSON string
```

Type and role predicates:

```ruby
message.text?       # => true if type is "text"
message.tool_call?  # => true if type is "tool_call"
message.tool_result? # => true if type is "tool_result"
message.system?     # => true if role is "system"
message.user?       # => true if role is "user"
message.assistant?  # => true if role is "assistant"
message.stopped?    # => true if stop_reason is "stop"
message.tool_stop?  # => true if stop_reason is "tool"
```

## Classes

| Class | Description |
|-------|-------------|
| [UserMessage](user-message.md) | User input with session and metadata |
| [TextMessage](text-message.md) | Text message with role (system, user, or assistant) |
| [ToolCallMessage](tool-call-message.md) | Tool invocation request containing ToolMessage objects |
| [ToolResultMessage](tool-result-message.md) | Tool execution result |

## Usage in Memory

Messages are typically accessed through memory:

```ruby
memory.messages  # => Array<Message>

# Format for LLM
memory.format_history  # => Array<Message>
```

## See Also

- [Memory](../core/memory.md)
- [Message Flow Architecture](../../architecture/message-flow.md)
