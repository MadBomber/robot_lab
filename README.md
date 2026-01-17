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
class Magic8Ball < RubyLLM::Tool
  description "Consult the mystical Magic 8-Ball for guidance on yes/no questions"

  param :question, type: "string", desc: "A yes/no question to ask the oracle"

  RESPONSES = [
    { answer: "It is certain", certainty: 0.95, vibe: "positive" },
    { answer: "Ask again later", certainty: 0.10, vibe: "evasive" },
    { answer: "Don't count on it", certainty: 0.85, vibe: "negative" },
    { answer: "Signs point to yes", certainty: 0.75, vibe: "positive" },
    { answer: "Reply hazy, try again", certainty: 0.05, vibe: "evasive" },
    { answer: "My sources say no", certainty: 0.80, vibe: "negative" },
    { answer: "Outlook good", certainty: 0.70, vibe: "positive" },
    { answer: "Cannot predict now", certainty: 0.00, vibe: "evasive" }
  ].freeze

  def execute(question:)
    response = RESPONSES.sample
    { question: question, **response }
  end
end

# Create robot with tools
robot = RobotLab.build(
  name: "oracle",
  system_prompt: "You are a mystical oracle. Use the Magic 8-Ball to answer questions about the future.",
  tools: [Magic8Ball]
)

result = robot.run(message: "Should I start learning Rust?")
```

## Orchestrating Multiple Robots

Networks use [SimpleFlow](https://github.com/MadBomber/simple_flow) pipelines with optional task activation for intelligent routing:

```ruby
# Custom classifier that activates the appropriate specialist
class ClassifierRobot < RobotLab::Robot
  def call(result)
    robot_result = run(**extract_run_context(result))

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    # Route based on classification
    category = robot_result.last_text_content.to_s.strip.downcase
    case category
    when /billing/ then new_result.activate(:billing)
    when /technical/ then new_result.activate(:technical)
    else new_result.activate(:general)
    end
  end
end

# Create specialized robots
classifier = ClassifierRobot.new(
  name: "classifier",
  template: :classifier
)

billing_robot = RobotLab.build(name: "billing", template: :billing)
technical_robot = RobotLab.build(name: "technical", template: :technical)
general_robot = RobotLab.build(name: "general", template: :general)

# Create network with optional task routing
network = RobotLab.create_network(name: "support") do
  task :classifier, classifier, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
  task :technical, technical_robot, depends_on: :optional
  task :general, general_robot, depends_on: :optional
end

# Run the network
result = network.run(message: "I was charged twice for my subscription")
puts result.value.last_text_content
```

## Memory

Both robots and networks have inherent memory that persists across runs:

```ruby
# Standalone robot with inherent memory
robot = RobotLab.build(name: "assistant", system_prompt: "You are helpful.")

robot.run(message: "My name is Alice")
robot.run(message: "What's my name?")  # Memory persists automatically

# Access robot's memory
robot.memory[:user_id] = 123
robot.memory.data[:category] = "billing"

# Runtime memory injection
robot.run(message: "Help me", memory: { session_id: "abc123", tier: "premium" })

# Reset memory when needed
robot.reset_memory
```

Networks pass context through SimpleFlow::Result:

```ruby
# Create network with specialized robots
network = RobotLab.create_network(name: "support") do
  task :classifier, classifier, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
end

# Run with context - available to all robots
result = network.run(
  message: "I have a billing question",
  customer_id: 456,
  ticket_id: "TKT-123"
)

# Access results from specific robots
classifier_result = result.context[:classifier]
billing_result = result.context[:billing]

# The final value is the last robot's output
puts result.value.last_text_content
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
