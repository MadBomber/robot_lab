# Examples

Complete working examples demonstrating RobotLab features.

## Overview

These examples show how to use RobotLab for common scenarios, from simple chatbots to complex multi-robot systems.

## Examples

| Example | Description |
|---------|-------------|
| [Basic Chat](basic-chat.md) | Simple conversational robot |
| [Multi-Robot Network](multi-robot-network.md) | Customer service with routing |
| [Tool Usage](tool-usage.md) | External API integration |
| [MCP Server](mcp-server.md) | Creating an MCP tool server |
| [Rails Application](rails-application.md) | Full Rails integration |

## Quick Links

### Simple Examples

- [Hello World Robot](#hello-world)
- [Robot with Tools](#robot-with-tools)
- [Network with Routing](#network-with-routing)

### Advanced Examples

- [Streaming Responses](basic-chat.md#with-streaming)
- [Persistent Conversations](basic-chat.md#with-conversation-history)
- [MCP Integration](mcp-server.md)

## Hello World

```ruby
require "robot_lab"

# Configuration is handled automatically via MywayConfig.
# Set API keys via environment variables:
#   ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...
# Or via config files (~/.config/robot_lab/config.yml)

robot = RobotLab.build(
  name: "greeter",
  system_prompt: "You are a friendly greeter. Say hello warmly."
)

result = robot.run("Hi there!")

puts result.last_text_content
```

## Robot with Tools

```ruby
class CalculatorTool < RubyLLM::Tool
  description "Perform a calculation"

  param :expression, type: :string, desc: "Math expression to evaluate"

  def execute(expression:)
    eval(expression).to_s
  end
end

robot = RobotLab.build(
  name: "calculator",
  system_prompt: "You help with calculations.",
  local_tools: [CalculatorTool]
)

result = robot.run("What's 25 * 4?")
puts result.last_text_content
```

## Network with Routing

```ruby
classifier = RobotLab.build(
  name: "classifier",
  system_prompt: "Classify the request as BILLING or TECHNICAL. Respond with only the category."
)

billing = RobotLab.build(
  name: "billing",
  system_prompt: "You handle billing questions."
)

tech = RobotLab.build(
  name: "tech",
  system_prompt: "You handle technical issues."
)

network = RobotLab.create_network(name: "support") do
  task :classifier, classifier, depends_on: :none
  task :billing, billing, depends_on: :optional
  task :tech, tech, depends_on: :optional
end

result = network.run(message: "I was charged twice for my subscription")

# Access individual robot results via context
classifier_result = result.context[:classifier]
puts classifier_result.last_text_content
```

## Chaining Configuration

Robots support `with_*` methods that return `self` for chaining:

```ruby
robot = RobotLab.build(name: "assistant")
  .with_instructions("You are a helpful coding assistant.")
  .with_temperature(0.3)
  .with_model("gpt-4o")

result = robot.run("Explain Ruby blocks.")
puts result.last_text_content
```

## Using Templates

Templates are `.md` files with optional YAML front matter, managed by prompt_manager:

```ruby
# Template file: prompts/support.md
# ---
# model: claude-sonnet-4
# temperature: 0.5
# ---
# You are a support assistant for {{ company_name }}.

robot = RobotLab.build(
  name: "support",
  template: :support,
  context: { company_name: "Acme Corp" }
)

result = robot.run("How do I reset my password?")
puts result.last_text_content
```

## Running Examples

1. Install dependencies:
   ```bash
   bundle install
   ```

2. Set API key:
   ```bash
   export ANTHROPIC_API_KEY="your-key"
   ```

3. Run example:
   ```bash
   ruby examples/basic_chat.rb
   ```

Or use the provided rake tasks:

```bash
bundle exec rake examples:all          # Run all examples
bundle exec rake examples:run[1]       # Run specific example by number
```

## See Also

- [Getting Started](../getting-started/index.md)
- [Guides](../guides/index.md)
- [API Reference](../api/index.md)
