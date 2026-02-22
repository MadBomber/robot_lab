# Tool

Callable function that robots can use to interact with external systems.

## Class: `RobotLab::Tool < RubyLLM::Tool`

RobotLab::Tool inherits from RubyLLM::Tool, adding a `robot:` constructor parameter, a `Tool.create` factory for dynamic tools, and graceful error handling that returns plain-text errors to the LLM instead of crashing the run.

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

### raise_on_error / raise_on_error?

```ruby
MyTool.raise_on_error = true
MyTool.raise_on_error?  # => true
```

Per-class flag controlling whether `call` propagates exceptions from `execute` instead of catching them. Defaults to `false`. Does not affect other tool classes.

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

Overrides `RubyLLM::Tool#call` with graceful error handling. Converts string keys to symbols and calls `execute(**args)`. If `execute` raises a `StandardError`, the error is caught and returned as a plain-text string the LLM can reason about:

```
Error (tool_name): exception message
```

The error is also logged via `RobotLab.config.logger` at `:warn` level.

To propagate exceptions instead of catching them (for critical tools), set `raise_on_error` on the class:

```ruby
class CriticalTool < RobotLab::Tool
  self.raise_on_error = true
  # ...
end
```

`raise_on_error` is per-class (defaults to `false`) and does not affect other tool classes.

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

## Built-in: AskUser

`RobotLab::AskUser` is a built-in tool that lets a robot ask the user a question via the terminal. The LLM decides when human input is needed and calls this tool.

### Class: `RobotLab::AskUser < RobotLab::Tool`

```ruby
class RobotLab::AskUser < RobotLab::Tool
  description "Ask the user a question and wait for their typed response"
  param :question, type: "string",  desc: "The question to ask the user"
  param :choices,  type: "array",   desc: "Optional list of choices to present", required: false
  param :default,  type: "string",  desc: "Default value if user presses Enter",  required: false
end
```

### Parameters

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `question` | `String` | Yes | The question to display |
| `choices` | `Array` | No | Numbered choices to present |
| `default` | `String` | No | Value returned when user presses Enter without typing |

### IO Resolution

The tool reads input and writes output using the owning robot's `input`/`output` accessors:

1. `robot.input` / `robot.output` if set
2. Falls back to `$stdin` / `$stdout`

### Terminal Output

```
[robot_name] What programming language do you want to learn?
  1. Ruby
  2. Python
  3. Go
> [Ruby]
```

### Usage

```ruby
robot = RobotLab.build(
  name: "interviewer",
  system_prompt: "Interview the user about their project needs. Use ask_user to gather information.",
  local_tools: [RobotLab::AskUser]
)
robot.run("Find out what the user wants to build")
```

### Testing with StringIO

```ruby
robot = RobotLab::Robot.new(name: "bot", template: :assistant)
robot.input  = StringIO.new("Ruby\n")
robot.output = StringIO.new

tool = RobotLab::AskUser.new(robot: robot)
result = tool.call("question" => "Pick a language:", "choices" => ["Ruby", "Python"])
# => "Ruby"
```

### Choice Mapping

When `choices` are provided, the user can type either:

- A **number** (e.g., `2`) — mapped to the corresponding choice text
- **Text** (e.g., `Python`) — returned as-is

Out-of-range numbers are returned as-is (the LLM can re-ask if needed).

## See Also

- [Using Tools Guide](../../guides/using-tools.md)
- [Robot](robot.md)
- [MCP Integration](../../guides/mcp-integration.md)
