# Using Tools

Tools give robots the ability to interact with external systems. RobotLab supports three approaches: `RubyLLM::Tool` subclasses, `RobotLab::Tool` subclasses (with robot access), and `RobotLab::Tool.create` for dynamic tools.

## Defining Tools

### RubyLLM::Tool Subclass

For reusable tools that don't need robot access:

```ruby
class GetWeather < RubyLLM::Tool
  description "Get current weather for a location"

  param :location, type: :string, desc: "City name or zip code"
  param :unit, type: :string, desc: "Temperature unit", required: false

  def execute(location:, unit: "celsius")
    WeatherService.current(location, unit: unit)
  end
end
```

### RobotLab::Tool Subclass

For tools that need access to their owning robot (self-modification, spawning, etc.):

```ruby
class AdjustEnergy < RobotLab::Tool
  description "Adjust the robot's creativity level"

  param :level, type: "number", desc: "Temperature from 0.0 to 1.0"

  def execute(level:)
    robot.with_temperature(level)
    "Temperature adjusted to #{level}"
  end
end
```

Pass `robot: self` when constructing:

```ruby
class MyRobot < RobotLab::Robot
  def initialize
    super(
      name: "creative_bot",
      system_prompt: "You are creative.",
      local_tools: [AdjustEnergy.new(robot: self)]
    )
  end
end
```

### RobotLab::Tool.create (Dynamic Tools)

For quick, inline tools use the `Tool.create` factory:

```ruby
get_time = RobotLab::Tool.create(
  name: "get_time",
  description: "Get the current time"
) { |_args| Time.now.to_s }
```

With parameters:

```ruby
weather_tool = RobotLab::Tool.create(
  name: "get_weather",
  description: "Get current weather for a location",
  parameters: {
    type: "object",
    properties: {
      location: { type: "string", description: "City name" }
    },
    required: ["location"]
  }
) { |args| WeatherService.current(args[:location]) }
```

## Attaching Tools to Robots

Pass tools via the `local_tools:` parameter when building a robot:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful assistant with tool access.",
  local_tools: [GetWeather, CalculatorTool]
)
```

You can also add tools dynamically with chaining:

```ruby
robot = RobotLab.build(name: "assistant", system_prompt: "...")
robot.with_tools(GetWeather, CalculatorTool)
```

## Parameter Types

Define parameters on `RubyLLM::Tool` subclasses using `param`:

### String

```ruby
param :name, type: :string, desc: "User's full name"
```

### Integer

```ruby
param :count, type: :integer, desc: "Number of results"
```

### Number (Float)

```ruby
param :price, type: :number, desc: "Price in dollars"
```

### Boolean

```ruby
param :active, type: :boolean, desc: "Whether the user is active"
```

### Array

```ruby
param :tags, type: :array, desc: "List of tags"
```

### Enum

```ruby
param :status, type: :string, desc: "Order status", enum: %w[pending active completed]
```

### Required vs Optional

Parameters are required by default. Mark optional with `required: false`:

```ruby
param :query, type: :string, desc: "Search query"                    # required
param :limit, type: :integer, desc: "Max results", required: false   # optional
```

## Tool Patterns

### Database Lookup

```ruby
class FindUser < RubyLLM::Tool
  description "Find user by email or ID"

  param :identifier, type: :string, desc: "Email address or user ID"

  def execute(identifier:)
    user = User.find_by(id: identifier) || User.find_by(email: identifier)
    user ? user.to_h : { error: "User not found" }
  end
end
```

### API Integration

```ruby
class GetStockPrice < RubyLLM::Tool
  description "Get current stock price for a ticker symbol"

  param :symbol, type: :string, desc: "Stock ticker symbol (e.g. AAPL)"

  def execute(symbol:)
    response = HTTP.get("https://api.stocks.example/quote/#{symbol}")
    JSON.parse(response.body)
  rescue HTTP::Error => e
    { error: "Failed to fetch stock price: #{e.message}" }
  end
end
```

### File Operations

```ruby
class ReadFile < RubyLLM::Tool
  description "Read contents of a file"

  param :path, type: :string, desc: "Absolute path to the file"

  def execute(path:)
    if File.exist?(path) && File.readable?(path)
      { content: File.read(path), size: File.size(path) }
    else
      { error: "File not found or not readable" }
    end
  end
end
```

### Multi-Step Operations

```ruby
class ProcessOrder < RubyLLM::Tool
  description "Validate and process a customer order"

  param :order_id, type: :string, desc: "The order ID to process"

  def execute(order_id:)
    order = Order.find(order_id)

    # Validate
    return { error: "Invalid order" } unless order.valid?

    # Process payment
    result = PaymentProcessor.charge(order)
    return { error: result[:error] } unless result[:success]

    # Update status
    order.update!(status: "paid")

    { success: true, order_id: order.id, amount: order.total }
  end
end
```

## Tool Return Values

### Structured Data

Return hashes with consistent structure:

```ruby
def execute(user_id:)
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
def execute(**_)
  Time.now.to_s
end
```

### Lists

```ruby
def execute(query:)
  results = Search.query(query)
  results.map { |r| { id: r.id, title: r.title, score: r.score } }
end
```

## Error Handling

Always handle errors gracefully. Return structured error information so the LLM can decide how to proceed:

```ruby
class FetchResource < RubyLLM::Tool
  description "Fetch a resource from an external API"

  param :id, type: :string, desc: "Resource ID"

  def execute(id:)
    result = ExternalAPI.fetch(id)
    { success: true, data: result }
  rescue ExternalAPI::NotFound
    { success: false, error: "Resource not found", id: id }
  rescue ExternalAPI::RateLimited => e
    { success: false, error: "Rate limited", retry_after: e.retry_after }
  rescue StandardError => e
    { success: false, error: "Unexpected error: #{e.message}" }
  end
end
```

## Tool Callbacks

Robots support `on_tool_call` and `on_tool_result` callbacks for monitoring tool usage:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "...",
  local_tools: [GetWeather],
  on_tool_call: ->(call) { puts "Calling: #{call}" },
  on_tool_result: ->(result) { puts "Result: #{result}" }
)
```

## RobotLab::Tool.create with Schema

For dynamic tools via `Tool.create`, pass parameters as a JSON Schema hash:

```ruby
tool = RobotLab::Tool.create(
  name: "search",
  description: "Search for items",
  parameters: {
    type: "object",
    properties: {
      query: { type: "string", description: "Search query" },
      limit: { type: "integer", description: "Max results" }
    },
    required: ["query"]
  }
) { |args| Search.query(args[:query], limit: args[:limit] || 10) }
```

## Best Practices

### 1. Clear Descriptions

Write descriptions that help the LLM understand when and how to use the tool:

```ruby
# Good: Specific and actionable
class SearchOrders < RubyLLM::Tool
  description "Search customer orders by date range, status, or customer email. Returns up to 50 matching orders sorted by date."
  # ...
end

# Bad: Vague
class Search < RubyLLM::Tool
  description "Searches stuff"
  # ...
end
```

### 2. Validate Inputs

```ruby
def execute(email:)
  unless email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
    return { error: "Invalid email format" }
  end
  # ... rest of logic
end
```

### 3. Return Structured Data

```ruby
# Good: Structured and consistent
def execute(**_)
  {
    success: true,
    data: { id: 1, name: "Item" },
    metadata: { fetched_at: Time.now.iso8601 }
  }
end

# Bad: Unstructured
def execute(**_)
  "Found item with id 1 named Item"
end
```

### 4. Keep Tools Focused

Each tool should do one thing well. Prefer multiple focused tools over one tool that does everything.

## Next Steps

- [MCP Integration](mcp-integration.md) - External tool servers
- [Building Robots](building-robots.md) - Robot creation patterns
- [API Reference: Tool](../api/core/tool.md) - Complete API
