# UserMessage

User input with conversation metadata.

## Class: `RobotLab::UserMessage`

```ruby
message = UserMessage.new(
  "What's my order status?",
  session_id: "session_123",
  system_prompt: "Be concise",
  metadata: { source: "web" }
)
```

**Note:** `UserMessage` is a standalone class, not a subclass of `Message`.

## Constructor

```ruby
UserMessage.new(content, session_id: nil, system_prompt: nil, metadata: nil, id: nil)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `content` | `String` | Message text |
| `session_id` | `String`, `nil` | Conversation session ID |
| `system_prompt` | `String`, `nil` | Override system prompt |
| `metadata` | `Hash`, `nil` | Additional metadata |
| `id` | `String`, `nil` | Unique message ID (defaults to UUID) |

## Attributes

### content

```ruby
message.content  # => String
```

The message text.

### session_id

```ruby
message.session_id  # => String | nil
```

Conversation session identifier for history persistence.

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

## Methods

### to_h

```ruby
message.to_h  # => Hash
```

Hash representation.

**Returns:**

```ruby
{
  content: "What's my order status?",
  session_id: "session_123",
  system_prompt: "Be concise",
  metadata: { source: "web" },
  id: "uuid-here",
  created_at: "2024-01-15T10:30:00Z"
}
```

### to_json

```ruby
message.to_json  # => String
```

JSON representation.

### to_message

```ruby
message.to_message  # => TextMessage
```

Converts to a `TextMessage` with role `"user"` for use in conversation history.

### to_s

```ruby
message.to_s  # => String
```

Returns the content string.

### self.from

```ruby
UserMessage.from(input)  # => UserMessage
```

Creates a `UserMessage` from a String, Hash, or existing `UserMessage`.

## Examples

### Basic Message

```ruby
message = UserMessage.new("Hello!")
```

### With Session ID

```ruby
message = UserMessage.new(
  "Continue our conversation",
  session_id: "session_abc123"
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

### Creating from Various Inputs

```ruby
# From a string
msg = UserMessage.from("Hello!")

# From a hash
msg = UserMessage.from(content: "Hello!", session_id: "123")

# From an existing UserMessage (returns as-is)
msg = UserMessage.from(existing_message)
```

## See Also

- [Memory](../core/memory.md)
- [TextMessage](text-message.md)
