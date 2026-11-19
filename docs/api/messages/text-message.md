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

Hash representation. Inherited from `Message#to_h`, which ends in `.compact` — a
`nil` `stop_reason` is **omitted** rather than serialized as `nil`.

**Returns:**

```ruby
TextMessage.new(role: "assistant", content: "Hello! How can I help you today?").to_h
# => { type: "text", role: "assistant", content: "Hello! How can I help you today?" }

TextMessage.new(role: "assistant", content: "Done.", stop_reason: "stop").to_h
# => { type: "text", role: "assistant", content: "Done.", stop_reason: "stop" }
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

`Robot#run` returns a `RobotResult`, **not** a `TextMessage`. `RobotResult` has no
`text?` and no `content` — calling either raises `NoMethodError`. Read the reply
with `last_text_content` (aliased as `reply`):

```ruby
result = robot.run("Tell me a joke")

puts result.last_text_content   # => the assistant's text
puts result.reply               # => same thing
result.stopped?                 # => true whenever there are no tool calls
result.has_tool_calls?          # => whether the final message carried tool calls
```

!!! note "`RobotResult#stopped?` is not driven by `stop_reason`"
    A `RobotResult` produced by `Robot#run` always has `stop_reason == nil`
    (`RubyLLM::Message` does not define the method, so `build_result` falls back
    to `nil`), and the `TextMessage` it wraps is built without a `stop_reason`
    too. `stopped?` therefore reduces to `!has_tool_calls?` — it never becomes
    true because a `stop_reason` of `"stop"` was reported. The
    `stop_reason: "stop"` form shown above only applies to `TextMessage`
    instances you construct yourself.

`result.output` is an `Array` holding a single `TextMessage` rebuilt from the
final response text — it is not the full turn:

```ruby
msg = result.output.first
msg.text?      # => true
msg.content    # => the assistant's text
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
