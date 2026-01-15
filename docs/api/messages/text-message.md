# TextMessage

Assistant text response.

## Class: `RobotLab::TextMessage`

```ruby
message = TextMessage.new("Hello! How can I help you today?")
```

## Constructor

```ruby
TextMessage.new(content)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `content` | `String` | Response text |

## Attributes

### content

```ruby
message.content  # => String
```

The response text.

### role

```ruby
message.role  # => :assistant
```

Always returns `:assistant`.

## Methods

### to_h

```ruby
message.to_h  # => Hash
```

Hash representation.

**Returns:**

```ruby
{
  role: :assistant,
  content: "Hello! How can I help you today?"
}
```

### to_json

```ruby
message.to_json  # => String
```

JSON representation.

## Examples

### Basic Response

```ruby
message = TextMessage.new("Your order has shipped!")
```

### In Robot Results

```ruby
result = robot.run(state: state)

# Extract text messages
result.output.each do |msg|
  if msg.is_a?(TextMessage)
    puts msg.content
  end
end
```

### Filtering Text Content

```ruby
# Get only text responses from results
text_responses = state.results.flat_map(&:output).select do |msg|
  msg.is_a?(TextMessage)
end.map(&:content)
```

## See Also

- [UserMessage](user-message.md)
- [ToolCallMessage](tool-call-message.md)
- [Robot](../core/robot.md)
