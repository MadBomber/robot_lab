# Building Robots

This guide covers everything you need to know about creating robots in RobotLab.

## Basic Robot

Create a robot using the `RobotLab.build` factory method with keyword arguments:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful assistant."
)

result = robot.run("Hello!")
puts result.last_text_content
```

## Robot Properties

### Name

A unique identifier used for routing and logging. If omitted, an auto-generated name is used:

```ruby
robot = RobotLab.build(name: "support_agent", system_prompt: "...")
```

### Description

Describes what the robot does (useful for routing decisions):

```ruby
robot = RobotLab.build(
  name: "support_agent",
  description: "Handles customer support inquiries about orders and refunds",
  system_prompt: "..."
)
```

### Model

The LLM model to use. Defaults to the value in `RobotLab.config.ruby_llm.model`:

```ruby
robot = RobotLab.build(
  name: "writer",
  model: "claude-sonnet-4",
  system_prompt: "You are a creative writer."
)
```

### System Prompt

An inline string that defines the robot's personality and behavior:

```ruby
robot = RobotLab.build(
  name: "support",
  system_prompt: <<~PROMPT
    You are a customer support specialist for TechCo.

    Your responsibilities:
    - Answer questions about products and services
    - Help resolve order issues
    - Provide friendly, professional assistance

    Always be polite and acknowledge the customer's concerns.
  PROMPT
)
```

## Template Files

Templates are `.md` files managed by [prompt_manager](https://github.com/MadBomber/prompt_manager). Reference a template by symbol; RobotLab resolves it through the configured template path.

```ruby
# Reference template by symbol (loads prompts/support.md)
robot = RobotLab.build(
  name: "support",
  template: :support,
  context: { company: "TechCo", tone: "friendly" }
)
```

### Template Format

Templates use `.md` files with YAML front matter:

```markdown title="prompts/support.md"
---
description: Customer support assistant
parameters:
  company: "Acme"
  tone: "professional"
model: claude-sonnet-4
temperature: 0.7
---
You are a support agent for <%= company %>.
Your tone should be <%= tone %>.
```

### Front Matter Configuration

The following YAML front matter keys are applied to the robot's chat automatically:

**LLM Configuration:**

| Key | Description |
|-----|-------------|
| `model` | Override the LLM model |
| `temperature` | Controls randomness (0.0 - 1.0) |
| `top_p` | Nucleus sampling threshold |
| `top_k` | Top-k sampling |
| `max_tokens` | Maximum tokens in response |
| `presence_penalty` | Penalize based on presence |
| `frequency_penalty` | Penalize based on frequency |
| `stop` | Stop sequences |

**Robot Identity and Capabilities:**

| Key | Description |
|-----|-------------|
| `robot_name` | Override the robot's name (when constructor uses the default) |
| `description` | Human-readable description of the robot |
| `tools` | Array of tool class names (resolved via `Object.const_get`) |
| `mcp` | Array of MCP server configurations |

Constructor-provided values always take precedence over frontmatter values.

### Self-Contained Templates

Templates can declare everything a robot needs — identity, tools, MCP servers, and LLM config — making the `.md` file a complete robot definition:

```markdown title="prompts/github_assistant.md"
---
description: GitHub assistant with MCP tool access
robot_name: github_bot
mcp:
  - name: github
    transport: stdio
    command: npx
    args: ["-y", "@modelcontextprotocol/server-github"]
model: claude-sonnet-4
temperature: 0.3
---
You are a helpful GitHub assistant with access to GitHub tools via MCP.
Use the available tools to help answer questions about GitHub repositories.
```

Build the robot with minimal constructor arguments:

```ruby
# Template provides name, description, MCP config, model, and temperature
robot = RobotLab.build(template: :github_assistant)
```

### Tools in Front Matter

Declare tool classes by name in the `tools:` key. RobotLab resolves each string to a Ruby constant and instantiates it:

```markdown title="prompts/order_support.md"
---
description: Order support specialist
tools:
  - OrderLookup
  - RefundProcessor
---
You help customers with order inquiries and refunds.
```

```ruby
# Tools are loaded from frontmatter — no local_tools: needed
robot = RobotLab.build(template: :order_support)
```

Tool classes must be defined and loaded before the robot is built. If a tool name cannot be resolved, it is skipped with a warning.

Constructor `local_tools:` overrides frontmatter `tools:` when provided:

```ruby
# Constructor tools take precedence over frontmatter tools
robot = RobotLab.build(
  template: :order_support,
  local_tools: [OrderLookup]  # Only OrderLookup, not RefundProcessor
)
```

### MCP in Front Matter

Declare MCP server configurations directly in the template:

```markdown title="prompts/developer.md"
---
description: Developer assistant with filesystem access
mcp:
  - name: filesystem
    transport: stdio
    command: mcp-server-filesystem
    args: ["--root", "/home/user/projects"]
---
You are a developer assistant with filesystem access.
```

```ruby
robot = RobotLab.build(template: :developer)
```

Constructor `mcp:` overrides frontmatter `mcp:` when provided.

### Template with System Prompt

You can combine a template and an inline system prompt. Both are applied to the chat -- the template first, then the system prompt is appended as additional instructions:

```ruby
robot = RobotLab.build(
  name: "support",
  template: :support,
  context: { company: "TechCo" },
  system_prompt: "Always respond in Spanish."
)
```

## Adding Tools

Give robots capabilities via the `local_tools:` parameter. Tools can be `RubyLLM::Tool` subclasses or `RobotLab::Tool` instances:

```ruby
robot = RobotLab.build(
  name: "order_assistant",
  system_prompt: "You help customers with orders.",
  local_tools: [OrderLookup, InventoryCheck]
)
```

See the [Using Tools](using-tools.md) guide for details on defining tools.

## MCP Configuration

Connect to MCP (Model Context Protocol) servers via the `mcp:` parameter:

```ruby
robot = RobotLab.build(
  name: "coder",
  template: :developer,
  mcp: [
    {
      name: "filesystem",
      transport: { type: "stdio", command: "mcp-server-fs", args: ["--root", "/data"] }
    }
  ]
)
```

MCP configuration supports hierarchical resolution:

| Value | Behavior |
|-------|----------|
| `:none` | No MCP servers (default) |
| `:inherit` | Use parent network/config MCP servers |
| `[...]` | Explicit array of server configurations |

See the [MCP Integration](mcp-integration.md) guide for transport types and advanced patterns.

## Chaining Configuration

Robots support `with_*` method chaining for runtime reconfiguration. Each method returns `self` for fluent usage:

```ruby
robot = RobotLab.build(name: "bot")

result = robot
  .with_instructions("Be concise and direct.")
  .with_temperature(0.9)
  .with_model("claude-sonnet-4")
  .run("Summarize quantum computing in one sentence.")
```

### Available Chain Methods

| Method | Description |
|--------|-------------|
| `with_model(id)` | Change the LLM model |
| `with_instructions(text)` | Set system instructions |
| `with_temperature(val)` | Set temperature |
| `with_top_p(val)` | Set nucleus sampling |
| `with_top_k(val)` | Set top-k sampling |
| `with_max_tokens(val)` | Set max output tokens |
| `with_presence_penalty(val)` | Set presence penalty |
| `with_frequency_penalty(val)` | Set frequency penalty |
| `with_stop(sequences)` | Set stop sequences |
| `with_tool(tool)` | Add a single tool |
| `with_tools(*tools)` | Add multiple tools |
| `with_template(id, **ctx)` | Apply a prompt template |
| `with_schema(schema)` | Set structured output schema |
| `with_thinking(config)` | Enable extended thinking |
| `with_bus(bus)` | Connect to a message bus (creates one if nil) |

## Running Robots

### Standalone

Run a robot directly with a string message:

```ruby
result = robot.run("Hello!")
puts result.last_text_content
```

The `run` method returns a `RobotResult` with:

```ruby
result.last_text_content  # => "Hi there! How can I help?"
result.output             # => Array of output messages
result.tool_calls         # => Array of tool call results
result.robot_name         # => "assistant"
result.stop_reason        # => stop reason from the LLM
```

### With Runtime Memory

Inject memory values for a single run:

```ruby
result = robot.run("What's my account status?", memory: { user_id: 123 })
```

### In a Network

Run through a network for orchestration:

```ruby
network = RobotLab.create_network(name: "pipeline") do
  task :assistant, robot, depends_on: :none
end

result = network.run(message: "Hello!")
puts result.value.last_text_content
```

### With Streaming

Stream responses in real-time by passing a block:

```ruby
robot.run("Tell me a story") do |event|
  case event[:event]
  when "text.delta"
    print event[:data][:content]
  when "tool_call"
    puts "\nCalling tool: #{event[:data][:name]}"
  end
end
```

## Robot Patterns

### Classifier Robot

Route requests to specialized handlers. Subclass `RobotLab::Robot` and override `call` for custom pipeline behavior:

```ruby
class ClassifierRobot < RobotLab::Robot
  def call(result)
    context = extract_run_context(result)
    message = context.delete(:message)
    robot_result = run(message, **context)

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    category = robot_result.last_text_content.to_s.strip.downcase

    case category
    when /billing/ then new_result.activate(:billing)
    when /technical/ then new_result.activate(:technical)
    else new_result.activate(:general)
    end
  end
end

classifier = ClassifierRobot.new(
  name: "classifier",
  system_prompt: <<~PROMPT
    Classify the user's message into exactly one category:
    - billing
    - technical
    - general
    Respond with only the category name, nothing else.
  PROMPT
)
```

### Specialist Robot

Handle specific domains with template and tools:

```ruby
billing_specialist = RobotLab.build(
  name: "billing_specialist",
  description: "Handles billing and payment inquiries",
  template: :billing,
  context: { department: "billing" },
  local_tools: [InvoiceLookup, RefundProcessor]
)
```

### Summarizer Robot

Condense information:

```ruby
summarizer = RobotLab.build(
  name: "summarizer",
  description: "Summarizes conversations and documents",
  system_prompt: <<~PROMPT
    Create concise summaries of the provided content.
    Focus on key points and actionable items.
    Use bullet points for clarity.
  PROMPT
)
```

### Bus-Connected Robot

Enable bidirectional communication between robots using a message bus. This pattern supports negotiation loops and convergence:

```ruby
bus = TypedBus::MessageBus.new

class Comedian < RobotLab::Robot
  def initialize(bus:)
    super(name: "bob", template: :comedian, bus: bus)
    on_message do |message|
      joke = run(message.content.to_s).last_text_content.strip
      send_reply(to: message.from.to_sym, content: joke, in_reply_to: message.key)
    end
  end
end

class ComedyCritic < RobotLab::Robot
  def initialize(bus:)
    super(name: "alice", template: :comedy_critic, bus: bus)
    @accepted = false
    on_message do |message|
      verdict = run("Evaluate: #{message.content}").last_text_content.strip
      @accepted = verdict.start_with?("FUNNY")
      send_message(to: :bob, content: "Try again.") unless @accepted
    end
  end
  attr_reader :accepted
end

bob   = Comedian.new(bus: bus)
alice = ComedyCritic.new(bus: bus)
alice.send_message(to: :bob, content: "Tell me a funny robot joke.")
```

The `on_message` block arity controls delivery handling:
- **1 argument** `|message|` — auto-acknowledges before calling
- **2 arguments** `|delivery, message|` — manual `delivery.ack!` / `delivery.nack!`

See [Message Bus](../architecture/core-concepts.md#message-bus) for details.

### Spawning Robots Dynamically

Create new robots at runtime using `spawn`. The bus is created lazily — no upfront wiring required:

```ruby
class Dispatcher < RobotLab::Robot
  attr_reader :spawned

  def initialize(bus: nil)
    super(name: "dispatcher", template: :dispatcher, bus: bus)
    @spawned = {}

    on_message do |message|
      puts "#{message.from} replied: #{message.content.to_s.lines.first&.strip}"
    end
  end

  def dispatch(question)
    # Ask LLM what specialist to create
    plan = run(question).last_text_content.strip
    role, instruction = plan.split("\n", 2)
    role = role.strip.downcase.gsub(/\s+/, "_")

    # Spawn (or reuse) a specialist
    specialist = @spawned[role] ||= spawn(
      name: role,
      system_prompt: instruction&.strip || "You are a helpful #{role}."
    )

    # Have the specialist answer and reply
    answer = specialist.run(question).last_text_content.strip
    specialist.send_message(to: :dispatcher, content: answer)
  end
end
```

Key features of `spawn`:

- Creates a child robot on the same bus as the parent
- Creates a bus lazily if the parent doesn't have one
- Spawned robots can immediately send and receive messages
- Multiple robots with the same name enable fan-out messaging

Robots can also join a bus after creation:

```ruby
bot = RobotLab.build(name: "latecomer", system_prompt: "Hello.")
bot.with_bus(existing_bus)  # now connected and can send/receive messages
```

## Configuration

RobotLab uses `MywayConfig` for configuration. Access the config object directly -- there is no `RobotLab.configure` block:

```ruby
RobotLab.config.ruby_llm.model           # => "claude-sonnet-4"
RobotLab.config.ruby_llm.request_timeout  # => 120
```

Configuration is loaded from:

- Bundled defaults (`lib/robot_lab/config/defaults.yml`)
- Environment-specific overrides (development, test, production)
- XDG config files (`~/.config/robot_lab/config.yml`)
- Project config (`./config/robot_lab.yml`)
- Environment variables (`ROBOT_LAB_*` prefix)

## Best Practices

### 1. Clear, Focused Prompts

```ruby
# Good: Specific and focused
robot = RobotLab.build(
  name: "reviewer",
  system_prompt: <<~PROMPT
    You are a code reviewer. Review code for:
    - Security vulnerabilities
    - Performance issues
    - Best practice violations

    Provide specific line numbers and suggestions.
  PROMPT
)

# Bad: Vague and unfocused
robot = RobotLab.build(
  name: "reviewer",
  system_prompt: "You help with code stuff."
)
```

### 2. Use Templates for Reusable Prompts

Templates keep prompts in version-controlled files and allow parameterization:

```ruby
robot = RobotLab.build(
  name: "support",
  template: :support,
  context: { company: "TechCo", language: "English" }
)
```

### 3. Handle Tool Errors Gracefully

See [Using Tools: Error Handling](using-tools.md#error-handling) for patterns.

## Next Steps

- [Creating Networks](creating-networks.md) - Orchestrate multiple robots
- [Message Bus](../architecture/core-concepts.md#message-bus) - Bidirectional robot communication
- [Dynamic Spawning](../architecture/core-concepts.md#dynamic-spawning) - Robots creating robots at runtime
- [Using Tools](using-tools.md) - Advanced tool patterns
- [Memory Guide](memory.md) - Share data between runs and robots
- [API Reference: Robot](../api/core/robot.md) - Complete API documentation
