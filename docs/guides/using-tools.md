# Using Tools

Tools give robots the ability to interact with external systems.

## Defining Tools

### In Robot Builder

```ruby
robot = RobotLab.build do
  name "assistant"

  tool :get_weather do
    description "Get current weather for a location"
    parameter :location, type: :string, required: true
    handler { |location:, **_| WeatherService.current(location) }
  end
end
```

### Standalone Tool

```ruby
weather_tool = RobotLab::Tool.new(
  name: "get_weather",
  description: "Get current weather for a location",
  parameters: {
    location: {
      type: "string",
      description: "City name",
      required: true
    }
  },
  handler: ->(location:, **_context) {
    WeatherService.current(location)
  }
)
```

## Parameter Types

### String

```ruby
parameter :name, type: :string, required: true
```

### Integer

```ruby
parameter :count, type: :integer, default: 10
```

### Number (Float)

```ruby
parameter :price, type: :number
```

### Boolean

```ruby
parameter :active, type: :boolean, default: true
```

### Array

```ruby
parameter :tags, type: :array
```

### Enum

```ruby
parameter :status, type: :string, enum: %w[pending active completed]
```

### With Description

```ruby
parameter :query,
          type: :string,
          required: true,
          description: "Search query (supports wildcards)"
```

## Handler Patterns

### Simple Handler

```ruby
handler { |param:, **_| do_something(param) }
```

### With Context Access

```ruby
handler do |param:, robot:, network:, state:|
  user_id = state.data[:user_id]
  result = perform_action(param, user_id)
  state.memory.remember("last_action", result[:id])
  result
end
```

### Error Handling

```ruby
handler do |id:, **_|
  record = Record.find_by(id: id)
  if record
    { success: true, data: record.to_h }
  else
    { success: false, error: "Record not found" }
  end
rescue StandardError => e
  { success: false, error: e.message }
end
```

### Async Operations

```ruby
handler do |url:, **_|
  # Long-running operation
  response = HTTP.timeout(30).get(url)
  { status: response.status, body: response.body.to_s[0..1000] }
end
```

## Tool Return Values

### Structured Data

```ruby
handler do |user_id:, **_|
  user = User.find(user_id)
  {
    id: user.id,
    name: user.name,
    email: user.email,
    created_at: user.created_at.iso8601
  }
end
```

### Simple Values

```ruby
handler { |**_| Time.now.to_s }
handler { |**_| 42 }
handler { |**_| true }
```

### Lists

```ruby
handler do |query:, **_|
  results = Search.query(query)
  results.map { |r| { id: r.id, title: r.title, score: r.score } }
end
```

## Tool Manifests

Wrap existing tools with modified metadata:

```ruby
# Original tool
base_tool = RobotLab::Tool.new(
  name: "search",
  description: "General search",
  handler: ->(q:, **_) { Search.query(q) }
)

# Customized version
product_search = RobotLab::ToolManifest.new(
  tool: base_tool,
  name: "search_products",
  description: "Search the product catalog"
)

code_search = RobotLab::ToolManifest.new(
  tool: base_tool,
  name: "search_code",
  description: "Search source code"
)
```

## Tool Whitelisting

### At Robot Level

```ruby
robot = RobotLab.build do
  tools %w[read_file list_directory]  # Only these tools
  tools :inherit                       # Use network's tools
  tools :none                          # No inherited tools
end
```

### At Network Level

```ruby
network = RobotLab.create_network do
  tools %w[search create_issue]  # Global whitelist
end
```

### Configuration Hierarchy

```
Global (RobotLab.configure)
  └── Network (tools: [...])
        └── Robot (tools: :inherit | :none | [...])
```

## MCP Tools

Use tools from MCP servers:

```ruby
network = RobotLab.create_network do
  mcp [
    {
      name: "github",
      transport: { type: "stdio", command: "mcp-server-github" }
    }
  ]

  # MCP tools automatically available
  # e.g., search_repositories, create_issue, etc.
end
```

### Filtering MCP Tools

```ruby
robot = RobotLab.build do
  mcp :inherit  # Use network's MCP servers
  tools %w[search_repositories create_issue]  # Only these MCP tools
end
```

## Common Tool Patterns

### Database Lookup

```ruby
tool :find_user do
  description "Find user by email or ID"
  parameter :identifier, type: :string, required: true
  handler do |identifier:, **_|
    user = User.find_by(id: identifier) || User.find_by(email: identifier)
    user ? user.to_h : { error: "User not found" }
  end
end
```

### API Integration

```ruby
tool :get_stock_price do
  description "Get current stock price"
  parameter :symbol, type: :string, required: true
  handler do |symbol:, **_|
    response = HTTP.get("https://api.stocks.example/quote/#{symbol}")
    JSON.parse(response.body)
  rescue HTTP::Error => e
    { error: "Failed to fetch stock price: #{e.message}" }
  end
end
```

### File Operations

```ruby
tool :read_file do
  description "Read contents of a file"
  parameter :path, type: :string, required: true
  handler do |path:, **_|
    if File.exist?(path) && File.readable?(path)
      { content: File.read(path), size: File.size(path) }
    else
      { error: "File not found or not readable" }
    end
  end
end
```

### State Modification

```ruby
tool :update_preference do
  description "Update user preference"
  parameter :key, type: :string, required: true
  parameter :value, type: :string, required: true
  handler do |key:, value:, state:, **_|
    state.memory.remember("pref:#{key}", value)
    { success: true, key: key, value: value }
  end
end
```

### Multi-Step Operations

```ruby
tool :process_order do
  description "Process a customer order"
  parameter :order_id, type: :string, required: true
  handler do |order_id:, state:, **_|
    order = Order.find(order_id)

    # Validate
    return { error: "Invalid order" } unless order.valid?

    # Process
    result = PaymentProcessor.charge(order)
    return { error: result[:error] } unless result[:success]

    # Update
    order.update!(status: "paid")

    # Store for later reference
    state.memory.remember("processed_order", order.id)

    { success: true, order_id: order.id, amount: order.total }
  end
end
```

## Best Practices

### 1. Clear Descriptions

```ruby
# Good: Specific and actionable
tool :search_orders do
  description "Search customer orders by date range, status, or customer email. Returns up to 50 matching orders."
end

# Bad: Vague
tool :search do
  description "Searches stuff"
end
```

### 2. Validate Inputs

```ruby
handler do |email:, **_|
  unless email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
    return { error: "Invalid email format" }
  end
  # ... rest of handler
end
```

### 3. Handle Errors Gracefully

```ruby
handler do |id:, **_|
  result = ExternalAPI.fetch(id)
  { success: true, data: result }
rescue ExternalAPI::NotFound
  { success: false, error: "Resource not found", id: id }
rescue ExternalAPI::RateLimited => e
  { success: false, error: "Rate limited", retry_after: e.retry_after }
rescue StandardError => e
  { success: false, error: "Unexpected error: #{e.message}" }
end
```

### 4. Return Structured Data

```ruby
# Good: Structured and consistent
handler do |**_|
  {
    success: true,
    data: { id: 1, name: "Item" },
    metadata: { fetched_at: Time.now.iso8601 }
  }
end

# Bad: Unstructured
handler { |**_| "Found item with id 1 named Item" }
```

## Next Steps

- [MCP Integration](mcp-integration.md) - External tool servers
- [Building Robots](building-robots.md) - Robot creation patterns
- [API Reference: Tool](../api/core/tool.md) - Complete API
