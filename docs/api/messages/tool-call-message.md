# ToolCallMessage

Tool invocation request from the LLM.

## Class: `RobotLab::ToolCallMessage`

```ruby
message = ToolCallMessage.new(
  role: "assistant",
  tools: [
    ToolMessage.new(id: "call_abc123", name: "get_weather", input: { city: "New York" })
  ]
)
```

## Constructor

```ruby
ToolCallMessage.new(role:, tools:, stop_reason: nil)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `role` | `String` | Message role (typically "assistant") |
| `tools` | `Array<ToolMessage>` | Array of tool call objects |
| `stop_reason` | `String`, `nil` | Stop reason (defaults to "tool") |

## ToolMessage

Each tool call is represented by a standalone `ToolMessage` object:

```ruby
ToolMessage.new(id:, name:, input:)
```

| Name | Type | Description |
|------|------|-------------|
| `id` | `String` | Unique call identifier |
| `name` | `String` | Tool name |
| `input` | `Hash` | Tool parameters |

## Attributes

### tools

```ruby
message.tools  # => Array<ToolMessage>
```

Array of `ToolMessage` objects representing the tool calls.

### role

```ruby
message.role  # => "assistant"
```

Returns a String. The LLM initiates tool calls, so this is typically `"assistant"`.

### type

```ruby
message.type  # => "tool_call"
```

Always returns `"tool_call"`.

### content

```ruby
message.content  # => nil
```

Always `nil` for tool call messages (the tool data is in `tools`).

### stop_reason

```ruby
message.stop_reason  # => "tool"
```

Defaults to `"tool"` indicating the conversation stopped for tool execution.

## Methods

### to_h

```ruby
message.to_h  # => Hash
```

Hash representation.

**Returns:**

```ruby
{
  type: "tool_call",
  role: "assistant",
  tools: [
    { type: "tool", id: "call_abc123", name: "get_weather", input: { city: "New York" } }
  ],
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
message.tool_call?  # => true
message.text?       # => false
message.assistant?  # => true
message.tool_stop?  # => true
```

## Examples

### Single Tool Call

```ruby
tool = ToolMessage.new(
  id: "call_1",
  name: "search_orders",
  input: { user_id: "123", status: "pending" }
)

call = ToolCallMessage.new(role: "assistant", tools: [tool])
```

### Multiple Tool Calls

```ruby
tools = [
  ToolMessage.new(id: "call_1", name: "get_weather", input: { city: "NYC" }),
  ToolMessage.new(id: "call_2", name: "get_time", input: { timezone: "EST" })
]

call = ToolCallMessage.new(role: "assistant", tools: tools)
call.tools.length  # => 2
```

### Processing Tool Calls

```ruby
if message.tool_call?
  message.tools.each do |tool|
    puts "Tool called: #{tool.name}"
    puts "Parameters: #{tool.input.inspect}"
  end
end
```

### In Tool Execution Flow

```ruby
# LLM returns a tool call
tool = ToolMessage.new(id: "call_weather_1", name: "get_weather", input: { city: "Seattle" })
tool_call = ToolCallMessage.new(role: "assistant", tools: [tool])

# Execute the tool and record the result
result_data = execute_tool(tool.name, tool.input)

tool_result = ToolResultMessage.new(
  tool: tool,
  content: { data: result_data }
)
```

## See Also

- [ToolResultMessage](tool-result-message.md)
- [Tool](../core/tool.md)
- [Using Tools Guide](../../guides/using-tools.md)
