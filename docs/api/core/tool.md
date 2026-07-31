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

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `RobotLab::Robot::DEFAULT_MAX_TOOLS` | `128` | Ceiling on the number of tools a robot hands the provider per turn. Override per robot with `RunConfig#max_tools`; a nil, zero, or negative value falls back to 128, so the cap cannot be disabled |

## Class Methods

### raise_on_error / raise_on_error?

```ruby
MyTool.raise_on_error = true
MyTool.raise_on_error?  # => true
```

Per-class flag controlling whether `call` propagates exceptions from `execute` instead of catching them. Defaults to `false`.

!!! warning "`raise_on_error` does not walk the inheritance chain"
    The reader is `defined?(@raise_on_error) ? @raise_on_error : false` — it
    inspects only the receiving class's own instance variable. A subclass of a
    class that set `self.raise_on_error = true` silently reverts to `false`:

    ```ruby
    class Critical < RobotLab::Tool; self.raise_on_error = true; end
    class Derived  < Critical; end

    Critical.raise_on_error?  # => true
    Derived.raise_on_error?   # => false   <-- errors are swallowed again
    ```

    Set the flag explicitly on every subclass that needs it. Contrast
    [`ractor_safe`](#ractor_safe-ractor_safe), which *does* walk the chain.

### ractor_safe / ractor_safe?

```ruby
class Pure < RobotLab::Tool
  ractor_safe true
end

Pure.ractor_safe?  # => true
```

Declares that the tool class is safe to run inside a Ractor. With no argument it
acts as a getter; with a Boolean it sets the value. `ractor_safe?` is an alias
for `ractor_safe`.

Unlike `raise_on_error`, the getter **does** walk the inheritance chain: if the
class has no `@ractor_safe` of its own it asks its superclass, terminating at
`false`.

```ruby
class Pure    < RobotLab::Tool; ractor_safe true; end
class Derived < Pure; end

Derived.ractor_safe?   # => true — inherited
```

**Ractor pool dispatch.** `Tool#call` routes through the Ractor worker pool
(`RobotLab.ractor_pool.submit(self.class.name, args)`) only when **all three**
hold:

1. `self.class.ractor_safe?` is true
2. `self.class.name` is not `nil` (an anonymous class — including everything from
   `Tool.create` — always falls through to the inline path)
3. `RobotLab.extension_loaded?(:ractor)` — i.e. the `robot_lab-ractor` gem is loaded

Otherwise `execute` runs inline on the calling thread. Ractor-safe tools must be
stateless: they are instantiated fresh inside the worker for each call.

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
| `mcp` | `String` | MCP server name; makes `mcp?` true |
| `robot` | `Robot` | Owning robot instance |
| `&handler` | `Block` | Receives the `args` hash, returns the result |

`create` builds an **anonymous** subclass (`Class.new(self)`) and stashes the
explicit name on the instance. Two consequences:

- `parameters` is read with **symbol** keys (`params_hash[:properties]`,
  `pdef[:type]`, `pdef[:description]`, `params_hash[:required]`). A string-keyed
  schema is silently ignored and the tool ends up with no parameters.
- Because `self.class.name` is `nil`, a `create`d tool never dispatches to the
  Ractor pool even if you set `ractor_safe`.

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

`param` accepts exactly four options — anything else raises
`ArgumentError: unknown keyword`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `type` | `String` | `"string"` | JSON Schema type (`"string"`, `"integer"`, `"number"`, `"boolean"`, `"array"`, `"object"`) |
| `desc` | `String` | `nil` | Description shown to the LLM |
| `description` | `String` | `nil` | Synonym for `desc` |
| `required` | `Boolean` | `true` | Whether the LLM must supply the parameter |

!!! warning "There is no `enum:` option"
    `param :unit, type: "string", enum: %w[c f]` raises
    `ArgumentError: unknown keyword: :enum`. Constrain the value in the
    description and validate it inside `execute`, or supply a full JSON Schema
    through [`Tool.create(parameters:)`](#toolcreate).

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

Returns the tool name. For `create`d tools, the explicit `name:` you passed. For
subclasses, ruby_llm derives it from the class name — **including the namespace**,
with `::` rendered as `--`:

```ruby
RobotLab::AskUser.new.name   # => "robot_lab--ask_user"

class Sub1 < RobotLab::Tool; end
Sub1.new.name                # => "sub1"   (top-level class, no namespace)
```

This matters when writing a `tools:` name allowlist: the allowlist must contain
the fully-derived name (`"robot_lab--ask_user"`), not the short one.

### mcp?

```ruby
tool.mcp?  # => Boolean
```

Whether this is an MCP-provided tool.

### call

```ruby
result = tool.call(args_hash)
```

Overrides `RubyLLM::Tool#call`. The whole invocation is wrapped in the
`:tool_call` hook family, then dispatched either to the Ractor pool or inline
(see [`ractor_safe`](#ractor_safe-ractor_safe)); ruby_llm's `call` converts
string keys to symbols and invokes `execute(**args)`.

Errors are caught and returned to the LLM as a plain-text string it can reason
about. There are two distinct paths:

| Raised | Returned text | Logged? |
|--------|---------------|---------|
| `RobotLab::ToolError` | `Error (<name>): <message>` — plus `" (retryable)"` when `RobotLab::Errors.retryable?` is true | **No** |
| any other `StandardError` | `Error (<name>): <message>` | Yes — `RobotLab.config.logger.warn("Tool '<name>' error: <Class>: <message>")` |

```ruby
class T2 < RobotLab::Tool
  description "t"
  def execute(**) = raise RobotLab::ToolError.new("nope", retryable: true)
end
T2.new.call({})   # => "Error (t2): nope (retryable)"   -- nothing logged

class T3 < RobotLab::Tool
  description "t"
  def execute(**) = raise ArgumentError, "bad"
end
T3.new.call({})   # => "Error (t3): bad"                -- WARN logged
```

`" (retryable)"` is appended only for `ToolError`/`MCPError` instances
constructed with `retryable: true` — see [Retryable Errors](../errors.md#retryable-errors).

To propagate exceptions instead of catching them (for critical tools), set `raise_on_error` on the class:

```ruby
class CriticalTool < RobotLab::Tool
  self.raise_on_error = true
  # ...
end
```

`raise_on_error` applies to **both** paths, is per-class, defaults to `false`, and
[is not inherited by subclasses](#raise_on_error-raise_on_error).

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

Hash representation with `:name`, `:description`, `:mcp` — `.compact`ed, so
`:description` and `:mcp` are absent when nil:

```ruby
class T4 < RobotLab::Tool
  description "t"
  def execute(**) = nil
end
T4.new.to_h   # => { name: "t4", description: "t" }   -- no :mcp key
```

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

# The robot must exist before the tool can reference it, so attach afterwards
robot = RobotLab.build(name: "creative_bot", system_prompt: "You are creative.")
robot.local_tools << AdjustTemperature.new(robot: robot)

robot.run("Be more creative.", tools: :inherit)
```

Passing the bare **class** (`local_tools: [AdjustTemperature]`) leaves
`tool.robot` as `nil` — ruby_llm instantiates it with no arguments — and
`robot.with_temperature` then raises `NoMethodError` on nil. Instantiate with
`robot:` whenever the tool needs its owner.

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

Its LLM-facing name is **`robot_lab--ask_user`** (namespace included), not `ask_user`.

### IO Resolution

The tool reads input and writes output using the owning robot's `input`/`output` accessors:

1. `robot.input` / `robot.output` if set
2. Falls back to `$stdin` / `$stdout`

The prompt label is `robot&.name || "Robot"`.

!!! warning "Attach an instance, not the class"
    `local_tools: [RobotLab::AskUser]` gives ruby_llm a bare class, which it
    instantiates with no arguments — so `tool.robot` is `nil`, IO falls back to
    `$stdin`/`$stdout`, and every prompt is labelled `[Robot]`. Pass
    `RobotLab::AskUser.new(robot: robot)` to get the robot's own name and streams.

### Terminal Output

```
[interviewer] What programming language do you want to learn?
  1. Ruby
  2. Python
  3. Go
> [Ruby]
```

### Usage

```ruby
robot = RobotLab.build(
  name: "interviewer",
  system_prompt: "Interview the user about their project needs. " \
                 "Use robot_lab--ask_user to gather information."
)
robot.local_tools << RobotLab::AskUser.new(robot: robot)

# run() defaults to tools: :none — :inherit is required for the tool to be sent
robot.run("Find out what the user wants to build", tools: :inherit)
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
