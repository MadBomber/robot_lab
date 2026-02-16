# Tool

Callable function that robots can use to interact with external systems.

## Class: `RobotLab::Tool < RubyLLM::Tool`

RobotLab::Tool inherits from RubyLLM::Tool, adding a `robot:` constructor parameter and a `Tool.create` factory for dynamic tools.

### Subclass Pattern

```ruby
class GetWeather < RobotLab::Tool
  description "Get weather for a location"

  param :location, type: "string", desc: "City name or zip code"
  param :unit, type: "string", desc: "Temperature unit", required: false

  def execute(location:, unit: "celsius")
    WeatherService.current(location, unit: unit)
  end
end
```

### Factory Pattern

```ruby
tool = RobotLab::Tool.create(
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

## Constructor

```ruby
Tool.new(robot: nil)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `robot` | `Robot, nil` | The owning robot instance |

## Class Methods

### Tool.create

Factory for dynamic tools (MCP wrappers, inline tools).

```ruby
Tool.create(
  name:,
  description: nil,
  parameters: nil,
  mcp: nil,
  robot: nil,
  &handler
)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `name` | `String, Symbol` | Tool identifier |
| `description` | `String` | What the tool does |
| `parameters` | `Hash` | JSON Schema parameter definition |
| `mcp` | `String` | MCP server name |
| `robot` | `Robot` | Owning robot instance |
| `&handler` | `Block` | Receives `args` hash, returns result |

## Inherited DSL (from RubyLLM::Tool)

### description

```ruby
class MyTool < RobotLab::Tool
  description "What this tool does"
end
```

### param

```ruby
class MyTool < RobotLab::Tool
  param :name, type: "string", desc: "User's name"
  param :age, type: "integer", desc: "User's age", required: false
end
```

### execute

```ruby
class MyTool < RobotLab::Tool
  def execute(name:, age: nil)
    # Implementation
  end
end
```

### halt

Stop the tool use loop from within execute:

```ruby
def execute(**)
  halt("Done processing")
end
```

### with_params

Set provider-specific parameters:

```ruby
class MyTool < RobotLab::Tool
  with_params(strict: true)
end
```

## Attributes

### robot

```ruby
tool.robot  # => Robot or nil
tool.robot = some_robot
```

Read/write accessor for the owning robot. Set via constructor or assigned later.

### mcp

```ruby
tool.mcp  # => String or nil
```

The MCP server name, set via `Tool.create(mcp: "server_name")`.

## Methods

### name

```ruby
tool.name  # => String
```

Returns the tool name. For subclasses, derived from the class name (CamelCase to snake_case). For `create`d tools, returns the explicit name.

### mcp?

```ruby
tool.mcp?  # => Boolean
```

Whether this is an MCP-provided tool.

### call

```ruby
result = tool.call(args_hash)
```

Inherited from RubyLLM::Tool. Converts string keys to symbols and calls `execute(**args)`.

### params_schema

```ruby
tool.params_schema  # => Hash or nil
```

Inherited. Returns the JSON Schema for tool parameters.

### provider_params

```ruby
tool.provider_params  # => Hash
```

Inherited. Returns provider-specific parameters (e.g., `{ strict: true }`).

### to_h

```ruby
tool.to_h  # => Hash
```

Hash representation with `:name`, `:description`, `:mcp`.

### to_json

```ruby
tool.to_json  # => String
```

JSON representation.

### to_json_schema

```ruby
tool.to_json_schema  # => Hash
```

JSON Schema representation for LLM function calling. Returns `{ name:, description:, parameters: }`.

## Robot-Aware Tools

Tools that modify their owning robot use the `robot` accessor:

```ruby
class AdjustTemperature < RobotLab::Tool
  description "Adjust the robot's creativity level"

  param :level, type: "number", desc: "Temperature from 0.0 to 1.0"

  def execute(level:)
    robot.with_temperature(level)
    "Temperature adjusted to #{level}"
  end
end

# Pass robot: self when constructing
robot = RobotLab.build(
  name: "creative_bot",
  system_prompt: "You are creative.",
  local_tools: [AdjustTemperature.new(robot: self)]
)
```

## Parameter Types

### String

```ruby
param :name, type: "string", desc: "User's full name"
```

### Integer

```ruby
param :count, type: "integer", desc: "Number of results"
```

### Number (Float)

```ruby
param :price, type: "number", desc: "Price in dollars"
```

### Boolean

```ruby
param :active, type: "boolean", desc: "Whether the user is active"
```

### Required vs Optional

Parameters are required by default. Mark optional with `required: false`:

```ruby
param :query, type: "string", desc: "Search query"                    # required
param :limit, type: "integer", desc: "Max results", required: false   # optional
```

## See Also

- [Using Tools Guide](../../guides/using-tools.md)
- [Robot](robot.md)
- [MCP Integration](../../guides/mcp-integration.md)
