# Robot

LLM-powered agent with personality, tools, and model configuration.

## Class: `RobotLab::Robot`

```ruby
robot = RobotLab.build do
  name "assistant"
  description "A helpful assistant"
  model "claude-sonnet-4"
  template "You are helpful."
end
```

## Attributes

### name

```ruby
robot.name  # => String
```

Unique identifier for the robot within a network.

### description

```ruby
robot.description  # => String
```

Human-readable description of what the robot does.

### model

```ruby
robot.model  # => String
```

LLM model identifier (e.g., "claude-sonnet-4", "gpt-4o").

### template

```ruby
robot.template  # => String
```

System prompt that defines the robot's personality.

### local_tools

```ruby
robot.local_tools  # => Array<Tool>
```

Tools defined directly on the robot.

### mcp_clients

```ruby
robot.mcp_clients  # => Array<MCP::Client>
```

Connected MCP server clients.

### mcp_tools

```ruby
robot.mcp_tools  # => Array<Tool>
```

Tools discovered from MCP servers.

### mcp_config

```ruby
robot.mcp_config  # => Symbol | Array
```

MCP configuration (`:inherit`, `:none`, or server array).

### tools_config

```ruby
robot.tools_config  # => Symbol | Array
```

Tools whitelist configuration (`:inherit`, `:none`, or tool names).

## Methods

### tools

```ruby
robot.tools  # => Array<Tool>
```

Returns all available tools (local + MCP, filtered by whitelist).

### run

```ruby
result = robot.run(
  state: state,
  network: network,
  streaming: nil,
  **context
)
# => RobotResult
```

Execute the robot with the given state.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `state` | `State` | Conversation state |
| `network` | `Network`, `NetworkRun`, `nil` | Network context |
| `streaming` | `Proc`, `nil` | Streaming callback |
| `**context` | `Hash` | Additional context |

**Returns:** `RobotResult`

### disconnect

```ruby
robot.disconnect
```

Disconnect from all MCP servers.

### to_h

```ruby
robot.to_h  # => Hash
```

Returns hash representation of the robot.

## Builder DSL

### name

```ruby
name "my_robot"
```

Set the robot's name.

### description

```ruby
description "Handles customer inquiries"
```

Set the robot's description.

### model

```ruby
model "claude-sonnet-4"
```

Set the LLM model.

### template

```ruby
# Inline template
template "You are a helpful assistant."

# Template file (loads from template_path)
template "support/system_prompt"

# Template file with variables
template "support/system_prompt", company: "Acme"
```

Set the system prompt.

### tool

```ruby
tool :tool_name do
  description "What the tool does"
  parameter :param, type: :string, required: true
  handler { |param:, **_| do_something(param) }
end
```

Define a tool for the robot.

### mcp

```ruby
mcp :inherit  # Use network's MCP servers
mcp :none     # No MCP servers
mcp [         # Specific servers
  { name: "fs", transport: { type: "stdio", command: "mcp-fs" } }
]
```

Configure MCP servers.

### tools (whitelist)

```ruby
tools :inherit            # Use network's tools
tools :none               # No inherited tools
tools %w[read_file write_file]  # Only these tools
```

Configure tool whitelist.

## Examples

### Basic Robot

```ruby
robot = RobotLab.build do
  name "greeter"
  template "You greet users warmly."
end
```

### Robot with Tools

```ruby
robot = RobotLab.build do
  name "calculator"
  model "claude-sonnet-4"
  template "You help with math problems."

  tool :add do
    description "Add two numbers"
    parameter :a, type: :number, required: true
    parameter :b, type: :number, required: true
    handler { |a:, b:, **_| a + b }
  end

  tool :multiply do
    description "Multiply two numbers"
    parameter :a, type: :number, required: true
    parameter :b, type: :number, required: true
    handler { |a:, b:, **_| a * b }
  end
end
```

### Robot with MCP

```ruby
robot = RobotLab.build do
  name "developer"
  template "You help with coding tasks."

  mcp [
    {
      name: "github",
      transport: { type: "stdio", command: "mcp-server-github" }
    }
  ]

  tools %w[search_repositories create_issue]
end
```

## See Also

- [Building Robots Guide](../../guides/building-robots.md)
- [Tool](tool.md)
- [Network](network.md)
