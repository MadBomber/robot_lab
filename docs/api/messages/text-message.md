# TextMessage

Text message from system, user, or assistant.

## Class: `RobotLab::TextMessage`

```ruby
message = TextMessage.new(role: "assistant", content: "Hello! How can I help you today?")
```

## Constructor

```ruby
TextMessage.new(role:, content:, stop_reason: nil)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `role` | `String` | Message role ("system", "user", or "assistant") |
| `content` | `String` | The text content |
| `stop_reason` | `String`, `nil` | Stop reason ("stop" or "tool") |

## Attributes

### content

```ruby
message.content  # => String
```

The text content.

### role

```ruby
message.role  # => "assistant"
```

Returns a String: `"system"`, `"user"`, or `"assistant"`.

### type

```ruby
message.type  # => "text"
```

Always returns `"text"`.

### stop_reason

```ruby
message.stop_reason  # => "stop" or nil
```

The stop reason, if any.

## Methods

### to_h

```ruby
message.to_h  # => Hash
```

Hash representation.

**Returns:**

```ruby
{
  type: "text",
  role: "assistant",
  content: "Hello! How can I help you today?",
  stop_reason: "stop"
}
```

### to_json

```ruby
message.to_json  # => String
```

JSON representation.

### Predicates

```ruby
message.text?       # => true
message.tool_call?  # => false
message.assistant?  # => true (if role is "assistant")
message.user?       # => false
message.stopped?    # => true (if stop_reason is "stop")
```

## Examples

### System Message

```ruby
message = TextMessage.new(role: "system", content: "You are a helpful assistant")
message.system?  # => true
```

### User Message

```ruby
message = TextMessage.new(role: "user", content: "What's the weather?")
message.user?  # => true
```

### Assistant Response

```ruby
message = TextMessage.new(
  role: "assistant",
  content: "Your order has shipped!",
  stop_reason: "stop"
)
message.assistant?  # => true
message.stopped?    # => true
```

### In Robot Results

```ruby
result = robot.run("Tell me a joke")

# The result is a TextMessage when the assistant replies with text
if result.text?
  puts result.content
end
```

### Filtering Text Content

```ruby
# Get only text messages from memory
text_messages = memory.messages.select(&:text?).map(&:content)
```

## See Also

- [UserMessage](user-message.md)
- [ToolCallMessage](tool-call-message.md)
- [Robot](../core/robot.md)
