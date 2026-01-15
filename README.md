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

```bash
bundle add robot_lab
```

Or install it directly:

```bash
gem install robot_lab
```

### Requirements

- Ruby >= 3.2
- [One or more API Keys for LLM providers supported by RubyLLM](https://rubyllm.com/configuration/#provider-configuration)

For comprehensive guides and API documentation, visit **[https://madbomber.github.io/robot_lab](https://madbomber.github.io/robot_lab)**

## Getting Started

The simplest way to create a robot is with an inline `system_prompt`. This approach is ideal for development, testing, and quick prototyping:

```ruby
require "robot_lab"

# Configure RobotLab
RobotLab.configure do |config|
  config.default_model = "claude-sonnet-4"
end

# Create a robot with an inline system prompt
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful assistant. Be concise and friendly."
)

# Run the robot
result = robot.run(message: "What is the capital of France?")

puts result.output.first.content
# => "The capital of France is Paris."
```

### Using Templates

For production applications, RobotLab supports a powerful template system built on ERB. Templates allow you to:

- **Compose prompts** from reusable components
- **Inject dynamic context** at build-time and run-time
- **Version control** your prompts alongside your code
- **Share prompts** across multiple robots

Configure the template directory:

```ruby
RobotLab.configure do |config|
  config.template_path = "app/prompts"
end
```

Each template is a **directory** containing ERB files for different message roles:

```
app/prompts/
  assistant/
    ├── system.txt.erb    # System message (required)
    ├── user.txt.erb      # User prompt template (optional)
    ├── assistant.txt.erb # Pre-filled assistant response (optional)
    └── schema.rb         # Structured output schema (optional)
```

Create the system message at `app/prompts/assistant/system.txt.erb`:

```erb
You are a helpful assistant for <%= company_name %>.

Your responsibilities:
- Answer questions accurately and concisely
- Be friendly and professional
- Admit when you don't know something

<% if guidelines %>
Additional guidelines:
<%= guidelines %>
<% end %>
```

Reference the template directory using a Symbol:

```ruby
robot = RobotLab.build(
  name: "assistant",
  template: :assistant,
  context: { company_name: "Acme Corp", guidelines: nil }
)
```

### Combining Templates with System Prompts

The `system_prompt` parameter can also be used alongside a template. When both are provided, the template renders first and the `system_prompt` is appended. This is particularly useful during development and testing when you want to add temporary instructions or context to an existing template:

```ruby
robot = RobotLab.build(
  name: "assistant",
  template: :assistant,
  context: { company_name: "Acme Corp" },
  system_prompt: "DEBUG MODE: Log all tool calls. Today's date is #{Date.today}."
)
```

## Creating a Robot with Tools

```ruby
# Define tools using RubyLLM::Tool
class GetWeather < RubyLLM::Tool
  description "Get current weather for a location"

  param :location, type: "string", desc: "City name or location"

  def execute(location:)
    # Your weather API logic here
    { temperature: 72, conditions: "sunny", location: location }
  end
end

# Create robot with tools (uses app/prompts/weather_bot.erb)
robot = RobotLab.build(
  name: "weather_bot",
  template: :weather_bot,
  tools: [GetWeather]
)

result = robot.run(message: "What's the weather in Paris?")
```

## Orchestrating Multiple Robots

```ruby
# Create specialized robots (each uses a template from app/prompts/)
classifier = RobotLab.build(
  name: "classifier",
  template: :classifier
)

billing_robot = RobotLab.build(
  name: "billing",
  template: :billing
)

technical_robot = RobotLab.build(
  name: "technical",
  template: :technical
)

# Create router function
router = lambda do |args|
  return ["classifier"] if args.call_count.zero?

  if args.call_count == 1
    category = args.last_result&.output&.last&.content.to_s.upcase.strip
    category == "BILLING" ? ["billing"] : ["technical"]
  end
end

# Create a network with routing
network = RobotLab.create_network(
  name: "support",
  robots: [classifier, billing_robot, technical_robot],
  router: router
)

# Run the network
result = network.run(message: "I was charged twice for my subscription")
```

## Shared Memory

Robots in a network can share information through memory:

```ruby
# Create state with memory
state = RobotLab.create_state(data: { user_id: 123 })

# Access memory from state
state.memory.remember(:user_name, "Alice")
state.memory.recall(:user_name)  # => "Alice"

# Scoped memory for isolation
user_memory = state.memory.scoped("user:123")
user_memory.remember(:preference, "dark_mode")
user_memory.recall(:preference)  # => "dark_mode"

# Memory persists across robot runs in a network
network.run(message: "Remember my name is Alice", state: state)
network.run(message: "What's my name?", state: state)
```

## MCP Integration

Connect to external tool servers via Model Context Protocol:

```ruby
# Configure MCP server
filesystem_server = {
  name: "filesystem",
  transport: {
    type: "stdio",
    command: "mcp-server-filesystem",
    args: ["/path/to/allowed/directory"]
  }
}

# Create robot with MCP server - tools are auto-discovered
robot = RobotLab.build(
  name: "developer",
  template: :developer,
  mcp_servers: [filesystem_server]
)

# Robot can now use filesystem tools
result = robot.run(message: "List the files in the current directory")
```

## Streaming

Subscribe to real-time events during execution:

```ruby
result = robot.run(message: "Tell me a story") do |event|
  case event[:event]
  when "text.delta"
    print event[:data][:delta]
  when "run.completed"
    puts "\nDone!"
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
