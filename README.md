# RobotLab

A Ruby framework for building and orchestrating multi-robot LLM workflows.

## What is a Robot?

A **Robot** is an artificial object that performs work by following instructions. The term originates from Karel Čapek's 1920 Czech play *R.U.R.* (Rossum's Universal Robots), derived from the Czech word *robota*, meaning "forced labor" or "drudgery."

In the context of RobotLab, a Robot is an LLM-powered unit that:
- Follows a system prompt (instructions)
- Can use tools to accomplish tasks
- Maintains state across interactions
- Can be orchestrated with other robots in a network

> **Note:** Some software developers refer to similar constructs as **Service Objects** or **Agents**. RobotLab uses "Robot" to emphasize the autonomous, instruction-following nature of these objects.

## Features

- **Robots** - LLM-powered units with tools and lifecycle hooks
- **Networks** - Coordinate multiple robots with intelligent routing
- **Tools** - Define capabilities robots can invoke
- **MCP Integration** - Model Context Protocol support for external tool servers
- **Streaming** - Real-time event streaming during execution
- **State Management** - Share state across robots in a network
- **Rails Integration** - Generators and ActiveRecord-backed conversation history

## Installation

Add to your Gemfile:

```ruby
gem "robot_lab"
```

Then run:

```bash
bundle install
```

## Quick Start

### Creating a Simple Robot

```ruby
require "robot_lab"

# Configure your LLM provider
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end

# Create a robot
robot = RobotLab.build(
  name: "helper",
  system: "You are a helpful assistant. Be concise and friendly."
)

# Run the robot
result = robot.run("What is the capital of France?")
puts result.last_text_content
```

### Creating a Robot with Tools

```ruby
# Define a tool
weather_tool = RobotLab.create_tool(
  name: "get_weather",
  description: "Get the current weather for a location",
  parameters: {
    type: "object",
    properties: {
      location: { type: "string", description: "City name" }
    },
    required: ["location"]
  }
) do |input, **_opts|
  # Your weather API logic here
  { temperature: 72, conditions: "sunny", location: input[:location] }
end

# Create a robot with the tool
weather_robot = RobotLab.build(
  name: "weather_bot",
  system: "You help users check the weather. Use the get_weather tool when asked about weather.",
  tools: [weather_tool]
)

result = weather_robot.run("What's the weather in Paris?")
```

### Orchestrating Multiple Robots in a Network

```ruby
# Create specialized robots
classifier = RobotLab.build(
  name: "classifier",
  system: "Classify requests as 'billing', 'technical', or 'general'. Respond with only the category."
)

billing_robot = RobotLab.build(
  name: "billing",
  system: "You are a billing support specialist."
)

technical_robot = RobotLab.build(
  name: "technical",
  system: "You are a technical support specialist."
)

# Create a router
router = lambda do |input:, network:, last_result:, call_count:|
  return ["classifier"] if call_count.zero?

  if call_count == 1
    category = last_result&.last_text_content.to_s.downcase.strip
    return [category] if %w[billing technical].include?(category)
    return ["technical"] # default
  end

  nil # stop after specialist responds
end

# Create the network
network = RobotLab.create_network(
  name: "support",
  robots: [classifier, billing_robot, technical_robot],
  router: router
)

# Run the network
result = network.run("I was charged twice for my subscription")
```

## Configuration

```ruby
RobotLab.configure do |config|
  config.default_provider = :anthropic
  config.default_model = "claude-sonnet-4"
  config.max_iterations = 10
  config.max_tool_iterations = 10
  config.streaming_enabled = true
  config.logger = Logger.new($stdout)
end
```

## Rails Integration

### Installation

```bash
rails generate robot_lab:install
rails db:migrate
```

This creates:
- `config/initializers/robot_lab.rb` - Configuration
- `app/robots/` - Directory for your robots
- `app/tools/` - Directory for your tools
- Database tables for conversation history

### Generating Robots

```bash
rails generate robot_lab:robot Support --description="Handles support requests"
rails generate robot_lab:robot Router --routing
```

## Core Concepts

### Robot

The fundamental unit of work. Each robot has:
- A **name** - Unique identifier
- A **system prompt** - Instructions defining behavior
- **Tools** (optional) - Capabilities the robot can invoke
- **Lifecycle hooks** (optional) - Callbacks for customization

### Network

Orchestrates multiple robots:
- **Routing** - Determines which robot handles each request
- **State sharing** - Robots can share data via the network state
- **History** - Optional conversation persistence

### Tool

A capability that robots can invoke:
- **Name** and **description** - For LLM understanding
- **Parameters** - JSON Schema defining inputs
- **Handler** - Ruby code that executes the tool

### State

Shared context within a network execution:
- **Data** - Arbitrary key-value storage
- **Results** - History of robot outputs
- **Thread ID** - For conversation persistence
- **Memory** - Shared memory for robot communication

### Memory

Thread-safe shared memory for robots within a network:
- **Shared namespace** - Accessible by all robots
- **Robot namespaces** - Scoped to individual robots
- **Metadata** - Timestamps, access counts, custom metadata

## Shared Memory

Robots in a network can share information through memory:

```ruby
# Memory is automatically available in tool handlers and lifecycle hooks
weather_tool = RobotLab.create_tool(
  name: "get_weather",
  description: "Get weather for a location",
  parameters: {
    type: "object",
    properties: { location: { type: "string" } },
    required: ["location"]
  }
) do |input, memory:, **_opts|
  # Store in robot's namespace
  memory.remember(:last_location, input[:location])

  # Store in shared namespace (accessible by all robots)
  memory.shared.remember(:user_location, input[:location])

  { temperature: 72, location: input[:location] }
end

# Access memory in lifecycle hooks
lifecycle = RobotLab::Lifecycle.new(
  on_finish: ->(robot:, network:, memory:, result:) {
    # Track what each robot processed
    memory.remember(:completed_at, Time.now)
    memory.shared.remember(:last_robot, robot.name)
    result
  }
)

# Access memory directly from state
network.run("What's the weather?") do |event|
  puts network.state.memory.recall(:user_location, namespace: :shared)
end
```

### Memory Features

```ruby
memory = state.memory

# Basic operations
memory.remember(:key, "value")
memory.recall(:key)  # => "value"
memory.exists?(:key) # => true
memory.forget(:key)

# Namespaced operations
memory.remember(:finding, "data", namespace: :classifier)
memory.recall(:finding, namespace: :classifier)

# Scoped accessor
robot_memory = memory.scoped(:my_robot)
robot_memory.remember(:key, "value")  # Stores in :my_robot namespace
robot_memory.shared.recall(:key)      # Access shared namespace

# Search and stats
memory.search(/pattern/)
memory.stats  # => { total_entries: 5, namespaces: 3, ... }

# Serialization
hash = memory.to_h
restored = RobotLab::Memory.from_hash(hash)
```

## MCP (Model Context Protocol) Integration

Connect to external tool servers:

```ruby
robot = RobotLab.build(
  name: "db_robot",
  system: "You help with database queries",
  mcp_servers: [
    { name: "postgres", transport: { type: "stdio", command: "mcp-server-postgres" } }
  ]
)
```

## Streaming

Subscribe to real-time events during execution:

```ruby
network.run("Hello") do |event|
  case event[:event]
  when "text.delta"
    print event[:data][:delta]
  when "tool_call.output.delta"
    puts "Tool result: #{event[:data][:delta]}"
  end
end
```

## License

MIT License. See [LICENSE.txt](LICENSE.txt) for details.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/MadBomber/robot_lab.
