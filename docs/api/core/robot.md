# Robot

LLM-powered agent with template-based prompts, tools, memory, and MCP integration.

## Class Hierarchy

```
RubyLLM::Agent
  └── RobotLab::Robot
        └── Your custom subclasses (e.g., ClassifierRobot)
```

`Robot` inherits from `RubyLLM::Agent`, which creates a persistent `@chat` on initialization. The robot adds template-based prompts, shared memory, hierarchical MCP configuration, and SimpleFlow pipeline integration on top of the base agent.

## Constructor

```ruby
Robot.new(
  name:,
  template: nil,
  system_prompt: nil,
  context: {},
  description: nil,
  local_tools: [],
  model: nil,
  mcp_servers: [],
  mcp: :none,
  tools: :none,
  on_tool_call: nil,
  on_tool_result: nil,
  enable_cache: true,
  bus: nil,
  temperature: nil,
  top_p: nil,
  top_k: nil,
  max_tokens: nil,
  presence_penalty: nil,
  frequency_penalty: nil,
  stop: nil,
  run_config: nil
)
```

### Parameters

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `String` | **required** | Unique identifier for the robot |
| `template` | `Symbol`, `nil` | `nil` | Prompt template (e.g., `:assistant` loads `prompts/assistant.md`) |
| `system_prompt` | `String`, `nil` | `nil` | Inline system prompt (appended after template if both given) |
| `context` | `Hash`, `Proc` | `{}` | Variables passed to the template |
| `description` | `String`, `nil` | `nil` | Human-readable description of what the robot does |
| `local_tools` | `Array` | `[]` | Tools defined locally (`RubyLLM::Tool` subclasses or `RobotLab::Tool` instances) |
| `model` | `String`, `nil` | `nil` | LLM model ID (falls back to `RobotLab.config.ruby_llm.model`) |
| `mcp_servers` | `Array` | `[]` | Legacy MCP server configurations |
| `mcp` | `Symbol`, `Array` | `:none` | Hierarchical MCP config (`:none`, `:inherit`, or server array) |
| `tools` | `Symbol`, `Array` | `:none` | Hierarchical tools config (`:none`, `:inherit`, or tool name array) |
| `on_tool_call` | `Proc`, `nil` | `nil` | Callback invoked when a tool is called |
| `on_tool_result` | `Proc`, `nil` | `nil` | Callback invoked when a tool returns a result |
| `enable_cache` | `Boolean` | `true` | Whether to enable semantic caching |
| `bus` | `TypedBus::MessageBus`, `nil` | `nil` | Optional message bus for inter-robot communication |
| `run_config` | `RunConfig`, `nil` | `nil` | Shared config merged with explicit kwargs (see [RunConfig](#runconfig)) |
| `temperature` | `Float`, `nil` | `nil` | Controls randomness (0.0-1.0) |
| `top_p` | `Float`, `nil` | `nil` | Nucleus sampling threshold |
| `top_k` | `Integer`, `nil` | `nil` | Top-k sampling |
| `max_tokens` | `Integer`, `nil` | `nil` | Maximum tokens in response |
| `presence_penalty` | `Float`, `nil` | `nil` | Penalize based on presence |
| `frequency_penalty` | `Float`, `nil` | `nil` | Penalize based on frequency |
| `stop` | `String`, `Array`, `nil` | `nil` | Stop sequences |

When both `run_config:` and explicit kwargs (e.g., `temperature:`) are provided, explicit kwargs always win.

## Factory Method

```ruby
robot = RobotLab.build(
  name: "robot",      # Defaults to "robot"
  template: nil,
  system_prompt: nil,
  context: {},
  enable_cache: true,
  bus: nil,           # Optional TypedBus::MessageBus
  **options           # All other Robot.new parameters
)
# => RobotLab::Robot
```

If `name` is omitted, it defaults to `"robot"`.

## Attributes (Read-Only)

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | `String` | Unique identifier |
| `description` | `String`, `nil` | Human-readable description |
| `template` | `Symbol`, `nil` | Prompt template identifier |
| `system_prompt` | `String`, `nil` | Inline system prompt |
| `local_tools` | `Array` | Locally defined tools |
| `mcp_clients` | `Hash<String, MCP::Client>` | Connected MCP clients, keyed by server name |
| `mcp_tools` | `Array<Tool>` | Tools discovered from MCP servers |
| `memory` | `Memory` | Inherent memory (used when standalone, not in network) |
| `bus` | `TypedBus::MessageBus`, `nil` | Message bus instance (nil if not configured) |
| `outbox` | `Hash` | Sent messages tracked by composite key with status and replies |
| `run_config` | `RunConfig` | Effective RunConfig (merged from constructor kwargs and passed-in config) |
| `mcp_config` | `Symbol`, `Array` | Build-time MCP configuration (raw, unresolved) |
| `tools_config` | `Symbol`, `Array` | Build-time tools configuration (raw, unresolved) |

## Attributes (Read-Write)

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `input` | `IO`, `nil` | `nil` | Input stream for user interaction (falls back to `$stdin`) |
| `output` | `IO`, `nil` | `nil` | Output stream for user interaction (falls back to `$stdout`) |

Used by tools like [`AskUser`](tool.md#built-in-askuser) that need terminal IO. Set to `StringIO` for testing.

## Methods

### run

```ruby
result = robot.run(message, **kwargs)
# => RobotResult
```

Primary execution method. Sends a message to the LLM with memory/MCP/tools resolution and returns a `RobotResult`.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `message` | `String` | **required** | The user message to send |
| `network` | `NetworkRun`, `nil` | `nil` | Network context (passed internally) |
| `network_memory` | `Memory`, `nil` | `nil` | Shared network memory |
| `memory` | `Memory`, `Hash`, `nil` | `nil` | Runtime memory to merge |
| `mcp` | `Symbol`, `Array` | `:none` | Runtime MCP override |
| `tools` | `Symbol`, `Array` | `:none` | Runtime tools override |
| `**kwargs` | `Hash` | `{}` | Additional keyword arguments passed to `Agent#ask` |

**Returns:** `RobotResult`

**Examples:**

```ruby
# Simple message
result = robot.run("What is 2+2?")

# With runtime memory
result = robot.run("Summarize the data", memory: { data: report })

# With streaming block
result = robot.run("Tell me a story") { |event| print event.text }

# With runtime overrides
result = robot.run("Help me", mcp: :none, tools: :none)
```

### model

```ruby
robot.model  # => "claude-sonnet-4" or nil
```

Returns the model ID string. Resolves through the underlying chat object.

### update

```ruby
robot.update(
  template: nil,
  context: nil,
  system_prompt: nil,
  model: nil,
  temperature: nil,
  **kwargs
)
# => self
```

Reconfigure the robot after construction. Returns `self` for chaining.

### with_* Methods (Chaining)

All `with_*` methods delegate to the persistent `@chat` and return `self` for chaining:

| Method | Description |
|--------|-------------|
| `with_model(model_id)` | Change the LLM model |
| `with_temperature(temp)` | Set temperature |
| `with_top_p(value)` | Set nucleus sampling |
| `with_top_k(value)` | Set top-k sampling |
| `with_max_tokens(value)` | Set max response tokens |
| `with_presence_penalty(value)` | Set presence penalty |
| `with_frequency_penalty(value)` | Set frequency penalty |
| `with_stop(sequences)` | Set stop sequences |
| `with_instructions(prompt)` | Set system instructions |
| `with_tool(tool)` | Add a single tool |
| `with_tools(*tools)` | Add multiple tools |
| `with_params(**params)` | Set additional parameters |
| `with_headers(**headers)` | Set custom headers |
| `with_schema(schema)` | Set output schema |
| `with_context(**ctx)` | Set context |
| `with_thinking(opts)` | Enable extended thinking |
| `with_bus(bus)` | Connect to a message bus (creates one if nil) |

**Example:**

```ruby
robot = RobotLab.build(name: "bot")
robot
  .with_model("claude-sonnet-4")
  .with_temperature(0.7)
  .with_instructions("Be concise.")
  .run("Hello")
```

### with_template

```ruby
robot.with_template(:assistant, tone: "friendly")
# => self
```

Apply a prompt_manager template. Separate from the delegated `with_*` methods because it handles template parsing and front matter config.

### call

```ruby
robot.call(result)
# => SimpleFlow::Result
```

SimpleFlow step interface. Extracts the message from `result.context[:run_params]`, calls `run`, and wraps the output in a continued `SimpleFlow::Result`.

Override this method in subclasses for custom routing logic (e.g., classifiers).

### reset_memory

```ruby
robot.reset_memory
# => self
```

Reset the robot's inherent memory to its initial state.

### send_message

```ruby
message = robot.send_message(to: :bob, content: "Tell me a joke.")
# => RobotMessage
```

Publish a message to another robot's bus channel. Increments the internal message counter, creates a `RobotMessage`, tracks it in the outbox, and publishes to the target channel.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `to` | `String`, `Symbol` | Target robot's channel name |
| `content` | `String`, `Hash` | Message payload |

**Returns:** `RobotMessage`

**Raises:** `BusError` if no bus is configured.

### send_reply

```ruby
reply = robot.send_reply(to: :alice, content: "Here's a joke...", in_reply_to: "alice:1")
# => RobotMessage
```

Publish a correlated reply to a specific message. The `in_reply_to` composite key links this reply to the original message.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `to` | `String`, `Symbol` | Target robot's channel name |
| `content` | `String`, `Hash` | Reply payload |
| `in_reply_to` | `String` | Composite key of the original message (e.g., `"alice:1"`) |

**Returns:** `RobotMessage`

**Raises:** `BusError` if no bus is configured.

### on_message

```ruby
robot.on_message { |message| puts message.content }
# => self
```

Register a custom handler for incoming bus messages. Block arity controls delivery handling:

- **1 argument** `|message|` — auto-acknowledges the delivery before calling the block
- **2 arguments** `|delivery, message|` — manual mode; you call `delivery.ack!` or `delivery.nack!`

**Examples:**

```ruby
# Auto-ack mode (1 arg)
robot.on_message do |message|
  joke = run(message.content.to_s).last_text_content
  send_reply(to: message.from.to_sym, content: joke, in_reply_to: message.key)
end

# Manual mode (2 args)
robot.on_message do |delivery, message|
  if message.content.to_s.length > 10
    delivery.ack!
    send_reply(to: message.from.to_sym, content: "Got it!", in_reply_to: message.key)
  else
    delivery.nack!
  end
end
```

### spawn

```ruby
child = robot.spawn(
  name: "specialist",
  system_prompt: "You are a specialist."
)
# => RobotLab::Robot (connected to same bus)
```

Create a new robot on the same message bus. If the parent has no bus, one is created automatically and the parent is connected to it.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `String` | `"robot"` | Name for the new robot |
| `system_prompt` | `String`, `nil` | `nil` | Inline system prompt |
| `template` | `Symbol`, `nil` | `nil` | Prompt template |
| `local_tools` | `Array` | `[]` | Tools for the new robot |
| `**options` | `Hash` | `{}` | Additional options passed to `RobotLab.build` |

**Returns:** `Robot`

**Examples:**

```ruby
# Minimal spawn (bus created automatically)
bot  = RobotLab.build
bot2 = bot.spawn(system_prompt: "You are helpful.")

# Spawn with template
specialist = dispatcher.spawn(
  name: "billing",
  template: :billing,
  local_tools: [InvoiceLookup]
)

# Fan-out: multiple robots with the same name
worker1 = bot.spawn(name: "worker", system_prompt: "Worker 1")
worker2 = bot.spawn(name: "worker", system_prompt: "Worker 2")
# Messages sent to :worker are delivered to both
```

### with_bus

```ruby
robot.with_bus(bus)
# => self
```

Connect the robot to a message bus after creation. If called without an argument and the robot has no bus, a new one is created. Returns `self` for chaining.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `bus` | `TypedBus::MessageBus`, `nil` | `nil` | Bus to join (creates one if nil and robot has no bus) |

**Returns:** `self`

**Examples:**

```ruby
# Join an existing bus
bot = RobotLab.build(name: "bot")
bot.with_bus(some_bus)

# Create a bus on demand
bot = RobotLab.build(name: "bot").with_bus

# Switch buses
bot.with_bus(bus1)  # joins bus1
bot.with_bus(bus2)  # leaves bus1, joins bus2
```

### disconnect

```ruby
robot.disconnect
# => self
```

Disconnect from all MCP servers and bus channels.

### to_h

```ruby
robot.to_h
# => Hash
```

Returns a hash representation of the robot including name, description, template, system_prompt, local_tools, mcp_tools, mcp_config, tools_config, mcp_servers, model, and bus (true if configured, omitted otherwise).

## Memory Behavior

- **Standalone**: Robot uses its own inherent `Memory` instance (`robot.memory`).
- **In a Network**: Robot uses the network's shared memory (passed via `network_memory:`).

```ruby
# Standalone memory access
robot.memory[:user_id] = 123
robot.memory[:user_id]  # => 123

# Reset standalone memory
robot.reset_memory
```

## Templates

Templates are `.md` files with optional YAML front matter, loaded via `prompt_manager`. The `template:` parameter maps to a file path relative to the configured template directory:

```ruby
# template: :assistant  =>  prompts/assistant.md
robot = RobotLab.build(name: "bot", template: :assistant, context: { tone: "friendly" })
```

Front matter supports two categories of keys:

**LLM Config:** `model`, `temperature`, `top_p`, `top_k`, `max_tokens`, `presence_penalty`, `frequency_penalty`, `stop` — applied to the underlying chat.

**Robot Extras:** `robot_name`, `description`, `tools`, `mcp` — applied to the robot's identity and capabilities. Constructor-provided values always take precedence.

| Key | Type | Description |
|-----|------|-------------|
| `robot_name` | `String` | Override robot name (when constructor uses the default `"robot"`) |
| `description` | `String` | Human-readable description |
| `tools` | `Array<String>` | Tool class names resolved via `Object.const_get` |
| `mcp` | `Array<Hash>` | MCP server configurations |

## RunConfig

`RunConfig` provides shared operational defaults that flow through the configuration hierarchy. Pass it via the `run_config:` parameter on `Robot.new` or `RobotLab.build`.

```ruby
shared = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.7)

robot = RobotLab.build(
  name: "writer",
  system_prompt: "You write creatively.",
  run_config: shared,
  temperature: 0.9  # explicit kwargs override run_config
)

robot.run_config  #=> RunConfig with model: "claude-sonnet-4", temperature: 0.9, ...
```

RunConfig fields: `model`, `temperature`, `top_p`, `top_k`, `max_tokens`, `presence_penalty`, `frequency_penalty`, `stop`, `mcp`, `tools`, `on_tool_call`, `on_tool_result`, `bus`, `enable_cache`.

See [Configuration: RunConfig](../../getting-started/configuration.md#runconfig-shared-operational-defaults) for full details.

## Configuration Hierarchy

Tools and MCP servers use hierarchical resolution: **runtime > robot > network > global config**.

```
RobotLab.config (global)
  |
  +-- Network (run_config:)
  |     |
  |     +-- Task (run_config:)
  |     |     |
  |     |     +-- Robot (run_config: + build-time mcp:, tools:)
  |     |           |
  |     |           +-- Template front matter
  |     |                 |
  |     |                 +-- run() call (runtime mcp:, tools:)
```

Values at each level:

- `:none` -- no tools/MCP at this level
- `:inherit` -- inherit from parent level
- `Array` -- explicit list of tool names or MCP server configs

## Examples

### Basic Robot

```ruby
robot = RobotLab.build(
  name: "greeter",
  system_prompt: "You greet users warmly."
)
result = robot.run("Hello!")
puts result.last_text_content
```

### Robot with Template

```ruby
robot = RobotLab.build(
  name: "support",
  template: :support,
  context: { company: "Acme Corp" }
)
result = robot.run("I need help with my order")
```

### Robot with Tools

```ruby
class Calculator < RubyLLM::Tool
  description "Performs basic arithmetic"
  param :operation, type: "string", desc: "add, subtract, multiply, divide"
  param :a, type: "number", desc: "First operand"
  param :b, type: "number", desc: "Second operand"

  def execute(operation:, a:, b:)
    case operation
    when "add" then a + b
    when "subtract" then a - b
    when "multiply" then a * b
    when "divide" then a.to_f / b
    end
  end
end

robot = RobotLab.build(
  name: "math_bot",
  system_prompt: "You help with math.",
  local_tools: [Calculator]
)
result = robot.run("What is 15 * 7?")
```

### Robot with MCP

```ruby
robot = RobotLab.build(
  name: "developer",
  system_prompt: "You help with coding tasks.",
  mcp: [
    {
      name: "github",
      transport: { type: "stdio", command: "github-mcp-server", args: ["stdio"] }
    }
  ]
)
result = robot.run("Search for popular Ruby repos")
robot.disconnect
```

### Bare Robot with Chaining

```ruby
robot = RobotLab.build(name: "bot")
result = robot
  .with_instructions("Be concise.")
  .with_temperature(0.3)
  .run("Explain quantum computing")
```

### Robot with Message Bus

```ruby
bus = TypedBus::MessageBus.new

bob = RobotLab.build(name: "bob", system_prompt: "You tell jokes.", bus: bus)

alice = RobotLab.build(name: "alice", system_prompt: "You evaluate jokes.", bus: bus)
alice.on_message do |message|
  verdict = alice.run("Is this funny? #{message.content}").last_text_content
  puts verdict
end

bob.on_message do |message|
  joke = bob.run(message.content.to_s).last_text_content
  bob.send_reply(to: message.from.to_sym, content: joke, in_reply_to: message.key)
end

alice.send_message(to: :bob, content: "Tell me a robot joke.")
```

### Spawning Robots Dynamically

```ruby
# Parent robot spawns specialists on demand
dispatcher = RobotLab.build(
  name: "dispatcher",
  system_prompt: "You delegate work."
)

dispatcher.on_message do |message|
  puts "Reply from #{message.from}: #{message.content}"
end

# spawn creates child on same bus (bus created lazily)
helper = dispatcher.spawn(
  name: "helper",
  system_prompt: "You answer questions concisely."
)

answer = helper.run("What is 2+2?").last_text_content
helper.send_message(to: :dispatcher, content: answer)
```

### Connecting to a Bus After Creation

```ruby
bot = RobotLab.build(name: "latecomer", system_prompt: "Hi there.")

# Join a bus later
bus = TypedBus::MessageBus.new
bot.with_bus(bus)

# Now bot can send/receive messages
bot.send_message(to: :someone, content: "Hello!")
```

## See Also

- [Building Robots Guide](../../guides/building-robots.md)
- [Tool](tool.md)
- [Network](network.md)
