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

Hash representation. The hash ends in `.compact`, so keys whose value is `nil`
are **omitted** — a message built without `session_id:` or `system_prompt:` has
no such keys at all. `metadata` always survives because it defaults to `{}`.

`created_at` is serialized with `Time#iso8601`, which carries the **local** UTC
offset. It is not normalized to `Z`/UTC.

**Returns:**

```ruby
UserMessage.new(
  "What's my order status?",
  session_id: "session_123",
  system_prompt: "Be concise",
  metadata: { source: "web" }
).to_h
# => {
#      content: "What's my order status?",
#      session_id: "session_123",
#      system_prompt: "Be concise",
#      metadata: { source: "web" },
#      id: "uuid-here",
#      created_at: "2026-07-31T13:04:42-05:00"
#    }

UserMessage.new("hi").to_h
# => {
#      content: "hi",
#      metadata: {},
#      id: "uuid-here",
#      created_at: "2026-07-31T13:04:42-05:00"
#    }
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

Normalizes any input into a `UserMessage`:

| Input | Result |
|-------|--------|
| `UserMessage` | Returned unchanged (same object) |
| `String` | `new(input)` |
| `Hash` | Keys symbolized, then `new(content, session_id:, system_prompt:, metadata:, id:)` |
| `TextMessage` | `new(input.content)` — role and stop reason are dropped |
| anything else | `new(input.to_s)` |

There is no "unsupported input" branch: `from` never raises for an unrecognized
type, it falls through to `to_s`.

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

# From a TextMessage (only the content is carried over)
msg = UserMessage.from(TextMessage.new(role: "user", content: "Hello!"))
msg.content  # => "Hello!"

# Anything else falls back to to_s
UserMessage.from(42).content  # => "42"
```

## See Also

- [Memory](../core/memory.md)
- [TextMessage](text-message.md)
