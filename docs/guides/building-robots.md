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
- [Using Tools](using-tools.md) - Advanced tool patterns
- [Memory Guide](memory.md) - Share data between runs and robots
- [API Reference: Robot](../api/core/robot.md) - Complete API documentation
