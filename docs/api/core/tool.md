# Tool

Callable function that robots can use to interact with external systems.

## Class: `RobotLab::Tool`

```ruby
tool = RobotLab::Tool.new(
  name: "get_weather",
  description: "Get weather for a location",
  parameters: { location: { type: "string", required: true } },
  handler: ->(location:, **_) { WeatherService.fetch(location) }
)
```

## Constructor

```ruby
Tool.new(
  name:,
  description: nil,
  parameters: {},
  handler:,
  mcp: false,
  strict: false
)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `name` | `String` | Tool identifier |
| `description` | `String` | What the tool does |
| `parameters` | `Hash` | Parameter definitions |
| `handler` | `Proc` | Execution function |
| `mcp` | `Boolean` | Is this an MCP tool? |
| `strict` | `Boolean` | Strict parameter validation |

## Attributes

### name

```ruby
tool.name  # => String
```

Tool identifier.

### description

```ruby
tool.description  # => String
```

Human-readable description.

### parameters

```ruby
tool.parameters  # => Hash
```

Parameter schema.

### handler

```ruby
tool.handler  # => Proc
```

Function that executes the tool.

### mcp

```ruby
tool.mcp  # => Boolean
```

Whether this is an MCP-sourced tool.

### strict

```ruby
tool.strict  # => Boolean
```

Whether to use strict parameter validation.

## Methods

### call

```ruby
result = tool.call(
  params,
  robot: robot,
  network: network,
  state: state
)
```

Execute the tool with parameters.

### to_h

```ruby
tool.to_h  # => Hash
```

Hash representation.

### to_json

```ruby
tool.to_json  # => String
```

JSON representation.

### to_json_schema

```ruby
tool.to_json_schema  # => Hash
```

JSON Schema representation for LLM.

## Parameter Schema

### Basic Types

```ruby
parameters: {
  name: { type: "string" },
  count: { type: "integer" },
  price: { type: "number" },
  active: { type: "boolean" },
  tags: { type: "array" }
}
```

### Required Parameters

```ruby
parameters: {
  id: { type: "string", required: true }
}
```

### Descriptions

```ruby
parameters: {
  query: {
    type: "string",
    description: "Search query (supports wildcards)"
  }
}
```

### Enums

```ruby
parameters: {
  status: {
    type: "string",
    enum: ["pending", "active", "completed"]
  }
}
```

### Defaults

```ruby
parameters: {
  limit: {
    type: "integer",
    default: 10
  }
}
```

## Handler

### Basic Handler

```ruby
handler: ->(param:, **_context) {
  do_something(param)
}
```

### With Context

```ruby
handler: ->(param:, robot:, network:, state:) {
  # robot - The executing Robot
  # network - The NetworkRun
  # state - Current State

  user = state.data[:user_id]
  state.memory.remember("last_action", param)

  perform_action(param, user)
}
```

### Error Handling

```ruby
handler: ->(id:, **_) {
  record = Record.find_by(id: id)

  if record
    { success: true, data: record.to_h }
  else
    { success: false, error: "Not found" }
  end
rescue StandardError => e
  { success: false, error: e.message }
}
```

## Builder DSL

In robot builder:

```ruby
tool :tool_name do
  description "What it does"

  parameter :param1, type: :string, required: true
  parameter :param2, type: :integer, default: 10

  handler do |param1:, param2:, **_context|
    # Implementation
  end
end
```

## ToolManifest

Wrap tools with modified metadata:

```ruby
manifest = RobotLab::ToolManifest.new(
  tool: original_tool,
  name: "custom_name",
  description: "Custom description"
)

# Original tool is used, metadata is overridden
```

### Attributes

- `tool` - The wrapped tool
- `name` - Override name (or original)
- `description` - Override description (or original)
- `aliases` - Alternative names

## Examples

### Simple Tool

```ruby
tool = Tool.new(
  name: "current_time",
  description: "Get the current time",
  handler: ->(**, _) { Time.now.iso8601 }
)
```

### Tool with Parameters

```ruby
tool = Tool.new(
  name: "search_users",
  description: "Search users by criteria",
  parameters: {
    query: {
      type: "string",
      description: "Search query",
      required: true
    },
    limit: {
      type: "integer",
      description: "Max results",
      default: 10
    },
    status: {
      type: "string",
      enum: ["active", "inactive", "all"],
      default: "active"
    }
  },
  handler: ->(query:, limit:, status:, **_) {
    User.search(query, limit: limit, status: status)
  }
)
```

### API Integration Tool

```ruby
tool = Tool.new(
  name: "fetch_stock_price",
  description: "Get current stock price",
  parameters: {
    symbol: { type: "string", required: true }
  },
  handler: ->(symbol:, **_) {
    response = HTTP.get("https://api.stocks.example/#{symbol}")

    if response.status.success?
      JSON.parse(response.body)
    else
      { error: "Failed to fetch", status: response.status.code }
    end
  rescue HTTP::Error => e
    { error: "Network error: #{e.message}" }
  }
)
```

### Database Tool

```ruby
tool = Tool.new(
  name: "get_order",
  description: "Get order details",
  parameters: {
    order_id: { type: "string", required: true }
  },
  handler: ->(order_id:, state:, **_) {
    user_id = state.data[:user_id]
    order = Order.find_by(id: order_id, user_id: user_id)

    if order
      order.as_json(include: [:items, :shipping])
    else
      { error: "Order not found or unauthorized" }
    end
  }
)
```

## See Also

- [Using Tools Guide](../../guides/using-tools.md)
- [Robot](robot.md)
- [MCP Integration](../../guides/mcp-integration.md)
