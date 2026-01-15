# Messages

Message types for LLM conversation representation.

## Overview

RobotLab uses a structured message system to represent conversations between users, assistants, and tools.

```ruby
# User input
user_msg = UserMessage.new("Hello", thread_id: "123")

# Assistant response
text_msg = TextMessage.new("Hi there!")

# Tool interaction
tool_call = ToolCallMessage.new(id: "call_1", name: "get_weather", input: { city: "NYC" })
tool_result = ToolResultMessage.new(id: "call_1", result: { temp: 72 })
```

## Message Hierarchy

```
Message (base)
├── UserMessage      - User input with metadata
├── TextMessage      - Assistant text response
├── ToolMessage      - Tool-related messages
│   ├── ToolCallMessage   - Tool invocation
│   └── ToolResultMessage - Tool result
└── SystemMessage    - System prompts
```

## Common Interface

All messages implement:

```ruby
message.role       # => Symbol (:user, :assistant, :tool)
message.content    # => String or structured data
message.to_h       # => Hash representation
message.to_json    # => JSON string
```

## Classes

| Class | Description |
|-------|-------------|
| [UserMessage](user-message.md) | User input with thread and metadata |
| [TextMessage](text-message.md) | Assistant text response |
| [ToolCallMessage](tool-call-message.md) | Tool invocation request |
| [ToolResultMessage](tool-result-message.md) | Tool execution result |

## Usage in State

Messages are typically accessed through state:

```ruby
state.messages  # => Array<Message>

# Format for LLM
state.format_history  # => Array<Hash>
```

## See Also

- [State](../core/state.md)
- [Message Flow Architecture](../../architecture/message-flow.md)
