# RobotLab

> [!CAUTION]
> This gem is under active development. APIs and features may change without notice. See the [CHANGELOG](CHANGELOG.md) for details.
<br>
<table>
<tr>
<td width="50%" align="center" valign="top">
<img src="docs/assets/images/robot_lab.jpg" alt="RobotLab"><br>
<em>"Build robots. Solve problems."</em>
</td>
<td width="50%" valign="top">
<strong>Multi-robot LLM workflow orchestration for Ruby</strong><br><br>
RobotLab enables you to build sophisticated AI applications using multiple specialized robots (LLM agents) that work together to accomplish complex tasks. Each robot has its own system prompt, tools, and capabilities.<br><br>
<strong>Key Features</strong><br>

- <strong>Multi-Robot Architecture</strong> - Build with specialized AI agents<br>
- <strong>Network Orchestration</strong> - Connect robots with flexible routing<br>
- <strong>Extensible Tools</strong> - Give robots custom capabilities<br>
- <strong>MCP Integration</strong> - Connect to external tool servers<br>
- <strong>Shared Memory</strong> - Hierarchical memory with namespaced scopes<br>
- <strong>Conversation History</strong> - Persist and restore threads<br>
- <strong>Streaming</strong> - Real-time event streaming<br>
- <strong>Rails Integration</strong> - Generators and ActiveRecord support
</td>
</tr>
</table>

## Installation

Add to your Gemfile:

```ruby
gem "robot_lab"
```

Then run:

```bash
bundle install
```

### Requirements

- Ruby >= 3.2
- An LLM provider API key (Anthropic, OpenAI, or Google)

## Getting Started

```ruby
require "robot_lab"

# Configure RobotLab
RobotLab.configure do |config|
  config.default_model = "claude-sonnet-4"
end

# Create a robot
robot = RobotLab.build do
  name "assistant"
  template "You are a helpful assistant. Be concise and friendly."
end

# Run the robot
state = RobotLab.create_state(message: "What is the capital of France?")
result = robot.run(state: state)

puts result.output.first.content
# => "The capital of France is Paris."
```

## Creating a Robot with Tools

```ruby
robot = RobotLab.build do
  name "weather_bot"
  template "You help users check the weather."

  tool :get_weather do
    description "Get current weather for a location"
    parameter :location, type: :string, required: true

    handler do |location:, **_|
      # Your weather API logic here
      { temperature: 72, conditions: "sunny", location: location }
    end
  end
end

state = RobotLab.create_state(message: "What's the weather in Paris?")
result = robot.run(state: state)
```

## Orchestrating Multiple Robots

```ruby
# Create specialized robots
classifier = RobotLab.build do
  name "classifier"
  template "Classify requests as BILLING, TECHNICAL, or GENERAL. Respond with only the category."
end

billing_robot = RobotLab.build do
  name "billing"
  template "You are a billing support specialist."
end

technical_robot = RobotLab.build do
  name "technical"
  template "You are a technical support specialist."
end

# Create a network with routing
network = RobotLab.create_network do
  name "support"
  add_robot classifier
  add_robot billing_robot
  add_robot technical_robot

  router ->(args) {
    case args.call_count
    when 0 then :classifier
    when 1
      category = args.last_result&.output&.first&.content&.strip&.upcase
      category == "BILLING" ? :billing : :technical
    end
  }
end

# Run the network
state = RobotLab.create_state(message: "I was charged twice for my subscription")
result = network.run(state: state)
```

## Shared Memory

Robots in a network can share information through memory:

```ruby
robot = RobotLab.build do
  name "assistant"
  template "You help users."

  tool :remember_preference do
    description "Remember a user preference"
    parameter :key, type: :string, required: true
    parameter :value, type: :string, required: true

    handler do |key:, value:, state:, **_|
      state.memory.remember(key, value)
      { saved: true }
    end
  end
end

# Access memory from state
state.memory.remember(:user_name, "Alice")
state.memory.recall(:user_name)  # => "Alice"

# Scoped memory
user_memory = state.memory.scoped("user:123")
user_memory.remember(:preference, "dark_mode")
```

## MCP Integration

Connect to external tool servers via Model Context Protocol:

```ruby
robot = RobotLab.build do
  name "developer"
  template "You help with coding tasks."

  mcp [
    { name: "filesystem", transport: { type: "stdio", command: "mcp-server-filesystem" } }
  ]
end
```

## Streaming

Subscribe to real-time events during execution:

```ruby
robot.run(state: state) do |event|
  case event.type
  when :text_delta
    print event.text
  when :tool_call
    puts "Calling: #{event.name}"
  end
end
```

## Rails Integration

```bash
rails generate robot_lab:install
rails db:migrate
```

This creates:
- `config/initializers/robot_lab.rb` - Configuration
- `app/robots/` - Directory for your robots
- Database tables for conversation history

## Documentation

Full documentation is available at **[https://madbomber.github.io/robot_lab](https://madbomber.github.io/robot_lab)**

## License

MIT License - Copyright (c) 2025 Dewayne VanHoozer

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/MadBomber/robot_lab.
