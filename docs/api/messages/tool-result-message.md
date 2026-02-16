# ToolResultMessage

Result from tool execution.

## Class: `RobotLab::ToolResultMessage`

```ruby
tool = ToolMessage.new(id: "call_abc123", name: "get_weather", input: { city: "NYC" })

message = ToolResultMessage.new(
  tool: tool,
  content: { data: { temperature: 72, conditions: "sunny" } }
)
```

## Constructor

```ruby
ToolResultMessage.new(tool:, content:, stop_reason: nil)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `tool` | `ToolMessage` | The tool call that was executed |
| `content` | `Hash` | Result with `:data` key (success) or `:error` key (failure) |
| `stop_reason` | `String`, `nil` | Stop reason (defaults to "tool") |

## Attributes

### tool

```ruby
message.tool  # => ToolMessage
```

The `ToolMessage` representing the tool call that produced this result. Provides access to `tool.id`, `tool.name`, and `tool.input`.

### content

```ruby
message.content  # => Hash
```

The result content. Contains either a `:data` key (success) or an `:error` key (failure).

### role

```ruby
message.role  # => "tool_result"
```

Always returns `"tool_result"`.

### type

```ruby
message.type  # => "tool_result"
```

Always returns `"tool_result"`.

### stop_reason

```ruby
message.stop_reason  # => "tool"
```

Defaults to `"tool"`.

## Methods

### success?

```ruby
message.success?  # => Boolean
```

Returns `true` if the content contains a `:data` key.

### error?

```ruby
message.error?  # => Boolean
```

Returns `true` if the content contains an `:error` key.

### data

```ruby
message.data  # => Object | nil
```

Returns the result data if successful, `nil` otherwise.

### error

```ruby
message.error  # => String | nil
```

Returns the error message if there was an error, `nil` otherwise.

### to_h

```ruby
message.to_h  # => Hash
```

Hash representation.

**Returns:**

```ruby
{
  type: "tool_result",
  role: "tool_result",
  tool: { type: "tool", id: "call_abc123", name: "get_weather", input: { city: "NYC" } },
  content: { data: { temperature: 72, conditions: "sunny" } },
  stop_reason: "tool"
}
```

### to_json

```ruby
message.to_json  # => String
```

JSON representation.

### Predicates

```ruby
message.tool_result?  # => true
message.tool_call?    # => false
message.text?         # => false
message.tool_stop?    # => true
```

## Examples

### Successful Result

```ruby
tool = ToolMessage.new(id: "call_1", name: "search_orders", input: { user_id: "123" })

result = ToolResultMessage.new(
  tool: tool,
  content: { data: { order_id: "ord_123", status: "shipped" } }
)

result.success?  # => true
result.data      # => { order_id: "ord_123", status: "shipped" }
```

### Error Result

```ruby
tool = ToolMessage.new(id: "call_order", name: "get_order", input: { id: "bad" })

result = ToolResultMessage.new(
  tool: tool,
  content: { error: "Order not found" }
)

result.error?  # => true
result.error   # => "Order not found"
result.data    # => nil
```

### Accessing Tool Information

```ruby
result = ToolResultMessage.new(
  tool: ToolMessage.new(id: "call_1", name: "get_weather", input: { city: "Berlin" }),
  content: { data: { temperature: 15, unit: "celsius" } }
)

result.tool.name   # => "get_weather"
result.tool.id     # => "call_1"
result.tool.input  # => { city: "Berlin" }
result.data        # => { temperature: 15, unit: "celsius" }
```

### Matching Tool Calls with Results

```ruby
# Given a ToolCallMessage and its results
tool_call_msg.tools.each do |tool|
  # Find the matching result
  matching_result = results.find { |r| r.tool.id == tool.id }

  if matching_result&.success?
    puts "#{tool.name}(#{tool.input}) => #{matching_result.data}"
  elsif matching_result&.error?
    puts "#{tool.name} failed: #{matching_result.error}"
  end
end
```

### In Memory History

```ruby
# Find all tool results from memory
tool_results = memory.messages.select(&:tool_result?)

tool_results.each do |tr|
  if tr.success?
    puts "#{tr.tool.name}: #{tr.data}"
  else
    puts "#{tr.tool.name} error: #{tr.error}"
  end
end
```

## See Also

- [ToolCallMessage](tool-call-message.md)
- [Tool](../core/tool.md)
- [Using Tools Guide](../../guides/using-tools.md)
