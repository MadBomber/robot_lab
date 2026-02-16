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
| [Message Bus](#message-bus) | Bidirectional robot communication with convergence |
| [Spawning Robots](#spawning-robots) | Dynamic specialist creation at runtime |

## Quick Links

### Simple Examples

- [Hello World Robot](#hello-world)
- [Robot with Tools](#robot-with-tools)
- [Network with Routing](#network-with-routing)

### Advanced Examples

- [Streaming Responses](basic-chat.md#with-streaming)
- [Persistent Conversations](basic-chat.md#with-conversation-history)
- [MCP Integration](mcp-server.md)
- [Message Bus Communication](#message-bus)
- [Spawning Robots](#spawning-robots)

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

## Message Bus

Robots can communicate bidirectionally via a message bus, enabling convergence loops and negotiation patterns. This example demonstrates a comedy critic tasking a comedian to generate jokes until one passes:

```ruby
ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")
require "robot_lab"

MAX_ATTEMPTS = 5

class Comedian < RobotLab::Robot
  TEMP_START = 0.2
  TEMP_STEP  = 0.2

  def initialize(bus:)
    super(name: "bob", template: :comedian, bus: bus, temperature: TEMP_START)
    @attempts = 0
    on_message do |message|
      @attempts += 1
      temp = [TEMP_START + TEMP_STEP * (@attempts - 1), 1.0].min
      with_temperature(temp)
      joke = run(message.content.to_s).last_text_content.strip
      send_reply(to: message.from.to_sym, content: joke, in_reply_to: message.key)
    end
  end

  attr_reader :attempts
end

class ComedyCritic < RobotLab::Robot
  def initialize(bus:)
    super(name: "alice", template: :comedy_critic, bus: bus)
    @accepted = false
    on_message do |message|
      verdict = run("Evaluate this joke:\n\n#{message.content}").last_text_content.strip
      @accepted = verdict.start_with?("FUNNY")
      send_message(to: :bob, content: "Not funny enough. Try again.") unless @accepted
    end
  end

  attr_reader :accepted
end

bus   = TypedBus::MessageBus.new
bob   = Comedian.new(bus: bus)
alice = ComedyCritic.new(bus: bus)

alice.send_message(to: :bob, content: "Tell me a funny robot joke.")
puts "Attempts: #{bob.attempts} / #{MAX_ATTEMPTS}"
puts "Accepted: #{alice.accepted}"
```

Key patterns demonstrated:

- **Robot subclasses** with templates for prompt management
- **Auto-ack** via 1-arg `on_message` blocks
- **`send_reply(to:, content:, in_reply_to:)`** for correlated responses
- **Temperature ramping** (0.2 &rarr; 1.0) for increasing creativity
- **Convergence loop** that terminates when the critic approves

Run: `bundle exec ruby examples/12_message_bus.rb`

## Spawning Robots

Robots can create new specialist robots at runtime using `spawn`. A dispatcher receives questions, decides what kind of specialist is needed, and spawns one on the fly. The bus is created lazily — no explicit setup required:

```ruby
ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")
require "robot_lab"

QUESTIONS = [
  "Why did the Roman Empire fall?",
  "Write a haiku about recursion.",
  "What is the square root of 144?",
].freeze

class Dispatcher < RobotLab::Robot
  attr_reader :spawned

  def initialize(bus: nil)
    super(name: "dispatcher", template: :dispatcher, bus: bus)
    @spawned = {}
    @pending = {}

    on_message do |message|
      puts "  Dispatcher  <- :#{message.from} replied"
      puts "               | #{message.content.to_s.lines.first&.strip}"
      @pending.delete(message.from)
    end
  end

  def dispatch(question)
    plan = run(question).last_text_content.strip
    role, instruction = plan.split("\n", 2)
    role = role.strip.downcase.gsub(/\s+/, "_")
    instruction = instruction&.strip || "You are a helpful #{role}."

    specialist = @spawned[role] ||= spawn(
      name: role,
      system_prompt: instruction
    )

    @pending[role] = question

    specialist.send_message(to: :dispatcher, content:
      specialist.run(question).last_text_content.strip
    )
  end
end

dispatcher = Dispatcher.new

QUESTIONS.each_with_index do |question, i|
  puts "\nQuestion #{i + 1}: #{question}"
  dispatcher.dispatch(question)
end

puts "\nSpecialists spawned: #{dispatcher.spawned.keys.join(', ')}"
```

Key patterns demonstrated:

- **`spawn`** for dynamic robot creation (bus created lazily)
- **`on_message`** for reply handling
- **LLM-driven delegation** — the dispatcher asks its LLM what specialist to create
- **Specialist reuse** — spawned robots are cached and reused across questions

Run: `bundle exec ruby examples/13_spawn.rb`

## See Also

- [Getting Started](../getting-started/index.md)
- [Guides](../guides/index.md)
- [API Reference](../api/index.md)
