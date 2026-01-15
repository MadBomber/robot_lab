# ToolResultMessage

Result from tool execution.

## Class: `RobotLab::ToolResultMessage`

```ruby
message = ToolResultMessage.new(
  id: "call_abc123",
  result: { temperature: 72, conditions: "sunny" }
)
```

## Constructor

```ruby
ToolResultMessage.new(id:, result:)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `id` | `String` | Matching tool call ID |
| `result` | `Object` | Tool execution result |

## Attributes

### id

```ruby
message.id  # => String
```

Identifier matching the corresponding `ToolCallMessage`.

### result

```ruby
message.result  # => Object
```

The result returned by the tool. Can be any serializable object.

### role

```ruby
message.role  # => :tool
```

Always returns `:tool`.

## Methods

### to_h

```ruby
message.to_h  # => Hash
```

Hash representation.

**Returns:**

```ruby
{
  role: :tool,
  tool_result: {
    id: "call_abc123",
    result: { temperature: 72, conditions: "sunny" }
  }
}
```

### to_json

```ruby
message.to_json  # => String
```

JSON representation.

## Examples

### Basic Result

```ruby
result = ToolResultMessage.new(
  id: "call_1",
  result: { success: true, order_id: "ord_123" }
)
```

### String Result

```ruby
result = ToolResultMessage.new(
  id: "call_time",
  result: "2024-01-15T10:30:00Z"
)
```

### Array Result

```ruby
result = ToolResultMessage.new(
  id: "call_search",
  result: [
    { id: 1, name: "Product A" },
    { id: 2, name: "Product B" }
  ]
)
```

### Error Result

```ruby
result = ToolResultMessage.new(
  id: "call_order",
  result: { success: false, error: "Order not found" }
)
```

### Matching with Tool Calls

```ruby
# Process all tool interactions
result.output.each_cons(2) do |a, b|
  if a.is_a?(ToolCallMessage) && b.is_a?(ToolResultMessage)
    if a.id == b.id
      puts "#{a.name}(#{a.input}) => #{b.result}"
    end
  end
end
```

### In Result History

```ruby
# Find all tool results from execution
tool_results = state.results
  .flat_map(&:output)
  .select { |m| m.is_a?(ToolResultMessage) }

tool_results.each do |tr|
  puts "Tool result: #{tr.result}"
end
```

## See Also

- [ToolCallMessage](tool-call-message.md)
- [Tool](../core/tool.md)
- [Using Tools Guide](../../guides/using-tools.md)
