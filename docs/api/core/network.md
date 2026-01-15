# Network

Orchestrates multiple robots with routing and shared configuration.

## Class: `RobotLab::Network`

```ruby
network = RobotLab.create_network do
  name "customer_service"
  add_robot support_robot
  add_robot billing_robot
end
```

## Attributes

### name

```ruby
network.name  # => String
```

Network identifier for logging and debugging.

### robots

```ruby
network.robots  # => Hash<String, Robot>
```

Hash of robots keyed by name.

### default_model

```ruby
network.default_model  # => String
```

Default model for robots that don't specify one.

### router

```ruby
network.router  # => Proc
```

Router function for selecting robots.

### max_iter

```ruby
network.max_iter  # => Integer
```

Maximum robot executions per run (default: 10).

### history

```ruby
network.history  # => History::Config
```

History persistence configuration.

### mcp

```ruby
network.mcp  # => Array
```

MCP server configurations.

### tools

```ruby
network.tools  # => Array<String>
```

Tool whitelist.

## Methods

### run

```ruby
result = network.run(
  state: state,
  router: custom_router,
  streaming: callback,
  **context
)
# => NetworkRun
```

Execute the network.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `state` | `State` | Conversation state |
| `router` | `Proc`, `nil` | Override router |
| `streaming` | `Proc`, `nil` | Streaming callback |
| `**context` | `Hash` | Run context |

**Returns:** `NetworkRun`

### state

```ruby
state = network.state(data: {}, results: [], message: nil)
# => State
```

Create a state for this network.

### available_robots

```ruby
network.available_robots  # => Array<String>
```

Returns names of all robots.

### robot

```ruby
network.robot("support")  # => Robot
```

Get robot by name.

### to_h

```ruby
network.to_h  # => Hash
```

Hash representation.

## Builder DSL

### name

```ruby
name "my_network"
```

### add_robot

```ruby
add_robot my_robot
add_robot RobotLab.build { name "inline"; template "..." }
```

### default_model

```ruby
default_model "claude-sonnet-4"
```

### max_iterations

```ruby
max_iterations 20
```

### router

```ruby
router ->(args) {
  case args.call_count
  when 0 then :first_robot
  when 1 then :second_robot
  else nil
  end
}
```

### history

```ruby
history History::Config.new(
  create_thread: ->(state:, input:, **) { ... },
  get: ->(thread_id:, **) { ... },
  append_results: ->(thread_id:, new_results:, **) { ... }
)
```

### mcp

```ruby
mcp [
  { name: "server", transport: { type: "stdio", command: "cmd" } }
]
```

### tools

```ruby
tools %w[tool1 tool2]
```

## NetworkRun

When `run` is called, a `NetworkRun` is created:

### Attributes

```ruby
run.network         # => Network
run.state           # => State
run.run_id          # => String
run.execution_state # => Symbol
```

### Methods

```ruby
run.results      # All results
run.new_results  # Results from this run
run.last_result  # Most recent result
run.to_h         # Hash representation
```

### Execution States

| State | Description |
|-------|-------------|
| `:pending` | Not started |
| `:initializing` | Setting up |
| `:routing` | Selecting robot |
| `:executing_robot` | Robot running |
| `:robot_complete` | Robot finished |
| `:completed` | All done |
| `:failed` | Error occurred |

## Router

Routers receive `Router::Args`:

```ruby
router = ->(args) {
  args.call_count   # Times called
  args.network      # NetworkRun
  args.context      # Run context
  args.stack        # Scheduled robots
  args.last_result  # Previous result
  args.message      # Shortcut for context[:message]

  # Return: Robot, robot name, array of robots, or nil
}
```

## Examples

### Simple Network

```ruby
network = RobotLab.create_network do
  name "simple"
  add_robot assistant
end

result = network.run(state: state)
```

### Multi-Robot Network

```ruby
network = RobotLab.create_network do
  name "support_system"

  add_robot classifier
  add_robot billing_agent
  add_robot tech_agent
  add_robot general_agent

  router ->(args) {
    case args.call_count
    when 0 then :classifier
    when 1
      category = args.last_result&.output&.first&.content
      case category&.strip
      when "BILLING" then :billing_agent
      when "TECHNICAL" then :tech_agent
      else :general_agent
      end
    else nil
    end
  }
end
```

### Network with History

```ruby
network = RobotLab.create_network do
  name "persistent"
  add_robot assistant

  history History::ActiveRecordAdapter.new(
    thread_model: ConversationThread,
    result_model: ConversationResult
  ).to_config
end
```

## See Also

- [Creating Networks Guide](../../guides/creating-networks.md)
- [Robot](robot.md)
- [State](state.md)
