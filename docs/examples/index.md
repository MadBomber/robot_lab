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
| [MCP Server](mcp-server.md) | Connecting a robot to external MCP servers |
| [Message Bus](#message-bus) | Bidirectional robot communication with convergence |
| [Spawning Robots](#spawning-robots) | Dynamic specialist creation at runtime |

> **Rails example** — see [robot_lab-rails](https://github.com/MadBomber/robot_lab-rails/blob/main/docs/examples/rails-application.md) for a full Rails integration example.

## Quick Links

### Simple Examples

- [Hello World Robot](#hello-world)
- [Robot with Tools](#robot-with-tools)
- [Network with Routing](#network-with-routing)

### Advanced Examples

- [Streaming Responses](basic-chat.md#with-streaming)
- [Persistent Conversations](basic-chat.md#with-memory)
- [MCP Integration](mcp-server.md)
- [Message Bus Communication](#message-bus)
- [Spawning Robots](#spawning-robots)

## Hello World

```ruby
require "robot_lab"

# Configuration is handled automatically via MywayConfig.
# Set API keys via environment variables:
#   ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...
# Or via config files (~/.config/robot_lab/robot_lab.yml — the filename
# repeats the app name; ~/.config/robot_lab/config.yml is never read)

robot = RobotLab.build(
  name: "greeter",
  system_prompt: "You are a friendly greeter. Say hello warmly."
)

result = robot.run("Hi there!")

puts result.last_text_content
```

## Robot with Tools

Give the LLM a fixed set of operations rather than an expression evaluator —
never `eval` a string the model produced.

```ruby
class CalculatorTool < RubyLLM::Tool
  description "Performs basic arithmetic operations"

  param :operation, type: "string", desc: "add, subtract, multiply, or divide"
  param :a,         type: "number", desc: "First operand"
  param :b,         type: "number", desc: "Second operand"

  def execute(operation:, a:, b:)
    case operation
    when "add"      then a + b
    when "subtract" then a - b
    when "multiply" then a * b
    when "divide"   then a.to_f / b
    else "Unknown operation: #{operation}"
    end
  end
end

robot = RobotLab.build(
  name: "calculator",
  system_prompt: "You help with calculations.",
  local_tools: [CalculatorTool]
)

# tools: :inherit is REQUIRED — run() defaults to tools: :none
result = robot.run("What's 25 * 4?", tools: :inherit)
puts result.last_text_content
```

> [!WARNING]
> `Robot#run` defaults to `tools: :none` and `mcp: :none`. A plain
> `robot.run("...")` sends the LLM **no tools at all**, even when `local_tools:`
> were attached at build time. Pass `tools: :inherit` on the call that should be
> able to use them.
>
> For a **standalone** robot like this one, do not pass `tools: :inherit` at
> *build* time — there the parent level is the global default (`:none`), so it
> produces an allowlist that matches nothing. Leave `tools:` unset in the
> constructor. (Inside a network the opposite holds: build-time `:inherit` is how a
> robot opts into the allowlist on the network's `config:`. See
> [Configuration](../getting-started/configuration.md#hierarchical-mcp-and-tools).)

See [`examples/02_tools.rb`](https://github.com/MadBomber/robot_lab/blob/main/examples/02_tools.rb)
for a second tool definition (`FortuneCookie`) alongside the calculator.

## Network with Routing

Routing is not configured declaratively — a robot performs it. Subclass
`RobotLab::Robot`, override `#call`, and activate one of the `depends_on: :optional`
tasks based on what the LLM returned.

```ruby
class ClassifierRobot < RobotLab::Robot
  def call(result)
    run_context = extract_run_context(result)
    message     = run_context.delete(:message)
    robot_result = run(message, **run_context)

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    case robot_result.reply.to_s.strip.downcase
    when /billing/   then new_result.activate(:billing)
    when /technical/ then new_result.activate(:technical)
    else                  new_result.activate(:general)
    end
  end
end

classifier = ClassifierRobot.new(
  name: "classifier",
  system_prompt: "Classify the request as BILLING, TECHNICAL, or GENERAL. Respond with only the category."
)

billing = RobotLab.build(name: "billing",   system_prompt: "You handle billing questions.")
tech    = RobotLab.build(name: "technical", system_prompt: "You handle technical issues.")
general = RobotLab.build(name: "general",   system_prompt: "You handle everything else.")

network = RobotLab.create_network(name: "support") do
  task :classifier, classifier, depends_on: :none
  task :billing,    billing,    depends_on: :optional
  task :technical,  tech,       depends_on: :optional
  task :general,    general,    depends_on: :optional
end

result = network.run(message: "I was charged twice for my subscription")

# Access individual robot results via context
puts result.context[:classifier].last_text_content
puts result.value.last_text_content   # the specialist that was activated
```

> [!WARNING]
> `result.context` is keyed by the **robot's** name (`with_context(@name.to_sym, ...)`),
> not the task name, and `activate(:name)` takes a **task** name. Keep the two
> identical — activating a task name that was never declared **raises
> `ArgumentError` and aborts the run** (`Step :classifier attempted to activate
> unknown step :billing`). The same happens for a task that was declared without
> `depends_on: :optional`.

Full version: [`examples/03_network.rb`](https://github.com/MadBomber/robot_lab/blob/main/examples/03_network.rb).

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

> [!NOTE]
> The chainable set is exactly what `RubyLLM::Chat` exposes — `with_context`,
> `with_headers`, `with_instructions`, `with_model`, `with_params`, `with_schema`,
> `with_temperature`, `with_thinking`, `with_tool`, `with_tools` — plus RobotLab's
> `with_template` and `with_bus`. There is no `with_max_tokens`, `with_top_p`, or
> `with_top_k`; use a constructor kwarg or `with_params(max_tokens: 2000)`.

## Using Templates

Templates are `.md` files with optional YAML front matter, managed by prompt_manager.
The body is rendered with **ERB** — interpolate with `<%= var %>`.

```ruby
# Template file: prompts/support.md
# ---
# model: claude-sonnet-4
# temperature: 0.5
# parameters:
#   company_name: null
# ---
# You are a support assistant for <%= company_name %>.

robot = RobotLab.build(
  name: "support",
  template: :support,
  context: { company_name: "Acme Corp" }
)

result = robot.run("How do I reset my password?")
puts result.last_text_content
```

> [!NOTE]
> `{{ var }}` is **not** interpolated — it passes through to the LLM verbatim.
> Of the LLM keys accepted in front matter, only `model:` and `temperature:` are
> actually applied to the chat. `top_p`, `top_k`, `max_tokens`, `presence_penalty`,
> `frequency_penalty`, and `stop` are parsed and then silently dropped; supply
> those as constructor kwargs or via a `RunConfig` instead.

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
   ruby examples/01_simple_robot.rb
   ```

Or use the provided rake tasks:

```bash
bundle exec rake examples:all          # Run all examples
bundle exec rake examples:run[1]       # Run specific example by number
```

## Shared Example Setup (`examples/common.rb`)

Most numbered examples (`01_*.rb` through `35_*.rb`) pull in a shared setup file:

```ruby
require_relative "common"
```

The line sits below each example's header comment rather than at the very top of
the file, and three examples do without it entirely —
`32_newsletter_reader.rb`, `33_stock_generator.rb`, and `33_stock_predictor.rb`.

`common.rb` handles the shared boilerplate so individual examples stay focused:

- **`LLM` hash** — frozen lookup of provider/model pairs accessible as `LLM[:default]`, `LLM[:local]`, `LLM[:anthropic]`. Each entry is a `LlmConfig = Data.define(:provider, :model)` value, so you access the model string as `LLM[:default].model`.
- **`RubyLLM.configure`** — sets a null logger and `LLM[:default].model` as the `default_model`.
- **`RobotLab.configure`** — sets a null logger.
- **Output helpers** — `banner(title)`, `section(title)`, `hr`, and `show_code(ruby_string, label:)` (Rouge-highlighted) for consistent terminal formatting.

## Template Path via direnv

Examples that bundle their own `prompts/` directory ship with a `.envrc` file:

```
examples/.envrc
examples/14_rusty_circuit/.envrc
examples/15_memory_network_and_bus/.envrc
examples/16_writers_room/.envrc
```

Each sets `ROBOT_LAB_TEMPLATE_PATH` to the local `prompts/` directory when [direnv](https://direnv.net/) is active. `common.rb` also sets this variable as a fallback if `direnv` has not loaded the `.envrc`:

```ruby
ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "prompts")
```

This means examples work correctly whether you run them from the project root with rake tasks or directly from inside the example's own directory.

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
      joke = run(message.content.to_s).reply.strip
      send_reply(to: message.from.to_sym, content: joke, in_reply_to: message.key)
    end
  end

  attr_reader :attempts
end

class ComedyCritic < RobotLab::Robot
  def initialize(bus:)
    super(name: "alice", template: :comedy_critic, bus: bus)
    @accepted = false
    @rounds   = 0
    on_message do |message|
      @rounds += 1
      verdict = run("Evaluate this joke:\n\n#{message.content}").reply.strip
      @accepted = verdict.start_with?("FUNNY")
      # The @rounds guard is what terminates the loop — without it the critic
      # keeps sending Bob back forever.
      send_message(to: :bob, content: "Not funny enough. Try again.") unless @accepted || @rounds >= MAX_ATTEMPTS
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
- **Convergence loop** that terminates when the critic approves *or* `MAX_ATTEMPTS` is reached

> [!WARNING]
> `MAX_ATTEMPTS` only bounds the loop because the critic checks it before sending
> Bob back. Declaring the constant without testing it leaves the two robots
> messaging each other indefinitely.

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
