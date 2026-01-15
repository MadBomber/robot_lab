# UserMessage

User input with conversation metadata.

## Class: `RobotLab::UserMessage`

```ruby
message = UserMessage.new(
  "What's my order status?",
  thread_id: "thread_123",
  system_prompt: "Be concise",
  metadata: { source: "web" }
)
```

## Constructor

```ruby
UserMessage.new(content, thread_id: nil, system_prompt: nil, metadata: {})
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `content` | `String` | Message text |
| `thread_id` | `String`, `nil` | Conversation thread ID |
| `system_prompt` | `String`, `nil` | Override system prompt |
| `metadata` | `Hash` | Additional metadata |

## Attributes

### content

```ruby
message.content  # => String
```

The message text.

### thread_id

```ruby
message.thread_id  # => String | nil
```

Conversation thread identifier for history persistence.

### system_prompt

```ruby
message.system_prompt  # => String | nil
```

Optional system prompt override for this message.

### metadata

```ruby
message.metadata  # => Hash
```

Arbitrary metadata (source, timestamp, user info, etc.).

### id

```ruby
message.id  # => String (UUID)
```

Unique message identifier.

### created_at

```ruby
message.created_at  # => Time
```

Message creation timestamp.

### role

```ruby
message.role  # => :user
```

Always returns `:user`.

## Methods

### to_h

```ruby
message.to_h  # => Hash
```

Hash representation.

**Returns:**

```ruby
{
  role: :user,
  content: "What's my order status?",
  id: "uuid-here",
  thread_id: "thread_123",
  created_at: "2024-01-15T10:30:00Z"
}
```

### to_json

```ruby
message.to_json  # => String
```

JSON representation.

## Examples

### Basic Message

```ruby
message = UserMessage.new("Hello!")
```

### With Thread ID

```ruby
message = UserMessage.new(
  "Continue our conversation",
  thread_id: "thread_abc123"
)
```

### With System Prompt Override

```ruby
message = UserMessage.new(
  "Translate this",
  system_prompt: "You are a translator. Respond in Spanish."
)
```

### With Metadata

```ruby
message = UserMessage.new(
  "Help with my account",
  metadata: {
    source: "mobile_app",
    user_id: "user_123",
    session_id: "sess_456",
    locale: "en-US"
  }
)
```

### Creating State

```ruby
message = UserMessage.new("Help", thread_id: "thread_123")
state = RobotLab.create_state(message: message)

state.thread_id  # => "thread_123"
```

## See Also

- [State](../core/state.md)
- [TextMessage](text-message.md)
