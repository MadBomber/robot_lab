# ToolCallMessage

Tool invocation request from the LLM.

## Class: `RobotLab::ToolCallMessage`

```ruby
message = ToolCallMessage.new(
  id: "call_abc123",
  name: "get_weather",
  input: { city: "New York", units: "fahrenheit" }
)
```

## Constructor

```ruby
ToolCallMessage.new(id:, name:, input:)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `id` | `String` | Unique call identifier |
| `name` | `String` | Tool name |
| `input` | `Hash` | Tool parameters |

## Attributes

### id

```ruby
message.id  # => String
```

Unique identifier for this tool call. Used to match with `ToolResultMessage`.

### name

```ruby
message.name  # => String
```

Name of the tool being invoked.

### input

```ruby
message.input  # => Hash
```

Parameters passed to the tool.

### role

```ruby
message.role  # => :assistant
```

Always returns `:assistant` (the LLM initiates tool calls).

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
  tool_call: {
    id: "call_abc123",
    name: "get_weather",
    input: { city: "New York", units: "fahrenheit" }
  }
}
```

### to_json

```ruby
message.to_json  # => String
```

JSON representation.

## Examples

### Basic Tool Call

```ruby
call = ToolCallMessage.new(
  id: "call_1",
  name: "search_orders",
  input: { user_id: "123", status: "pending" }
)
```

### Processing Tool Calls

```ruby
result.output.each do |msg|
  case msg
  when ToolCallMessage
    puts "Tool called: #{msg.name}"
    puts "Parameters: #{msg.input.inspect}"
  when ToolResultMessage
    puts "Result for #{msg.id}: #{msg.result}"
  end
end
```

### In Tool Execution Flow

```ruby
# LLM returns a tool call
tool_call = ToolCallMessage.new(
  id: "call_weather_1",
  name: "get_weather",
  input: { city: "Seattle" }
)

# Tool is executed
result = tool.call(tool_call.input, state: state)

# Result is recorded
tool_result = ToolResultMessage.new(
  id: tool_call.id,
  result: result
)
```

## See Also

- [ToolResultMessage](tool-result-message.md)
- [Tool](../core/tool.md)
- [Using Tools Guide](../../guides/using-tools.md)
