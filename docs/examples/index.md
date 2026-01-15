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

RobotLab.configure do |config|
  config.default_model = "claude-sonnet-4"
end

robot = RobotLab.build do
  name "greeter"
  template "You are a friendly greeter. Say hello warmly."
end

state = RobotLab.create_state(message: "Hi there!")
result = robot.run(state: state)

puts result.output.first.content
```

## Robot with Tools

```ruby
robot = RobotLab.build do
  name "calculator"
  template "You help with calculations."

  tool :calculate do
    description "Perform a calculation"
    parameter :expression, type: :string, required: true
    handler { |expression:, **_| eval(expression).to_s }
  end
end

state = RobotLab.create_state(message: "What's 25 * 4?")
result = robot.run(state: state)
```

## Network with Routing

```ruby
classifier = RobotLab.build do
  name "classifier"
  template "Classify: BILLING, TECHNICAL, or GENERAL"
end

billing = RobotLab.build do
  name "billing"
  template "You handle billing questions."
end

tech = RobotLab.build do
  name "tech"
  template "You handle technical issues."
end

network = RobotLab.create_network do
  name "support"
  add_robot classifier
  add_robot billing
  add_robot tech

  router ->(args) {
    case args.call_count
    when 0 then :classifier
    when 1
      category = args.last_result&.output&.first&.content&.strip
      category == "BILLING" ? :billing : :tech
    end
  }
end

result = network.run(state: state)
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

## See Also

- [Getting Started](../getting-started/index.md)
- [Guides](../guides/index.md)
- [API Reference](../api/index.md)
