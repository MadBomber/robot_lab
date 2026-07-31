# Core Concepts

This page provides an in-depth look at RobotLab's fundamental building blocks.

## Robot

A Robot is the primary unit of computation in RobotLab. It is a subclass of `RubyLLM::Agent` that wraps a persistent `@chat` with:

- A unique identity (name, description)
- A personality (system prompt and/or template)
- Capabilities (tools, MCP connections)
- Model, provider, and inference configuration
- Inherent memory (key-value store)

### Robot Anatomy

```ruby
robot = RobotLab.build(
  name: "support_agent",                    # Unique identifier
  description: "Handles support requests",  # Used for routing hints
  model: "claude-sonnet-4",                 # LLM model
  system_prompt: <<~PROMPT,                 # Inline system prompt
    You are a friendly customer support agent for Acme Corp.
    Always be polite and helpful. If you don't know something,
    say so honestly.
  PROMPT
  local_tools: [OrderLookup, RefundProcessor],  # RubyLLM::Tool subclasses
  mcp: :inherit,                                 # Use the network's MCP servers
  temperature: 0.7                               # Inference parameter
)
```

The build-time `mcp: :inherit` above assumes this robot will be added to a
network whose `config:` supplies an `mcp:` list. The parent is resolved on every
run, so `:inherit` picks up whatever the enclosing network provides. For a robot
that will run **standalone**, `:inherit` resolves against the global default
`:none` and yields nothing — give it an explicit array instead.

Or with a template:

```ruby
robot = RobotLab.build(
  name: "support_agent",
  template: :support,                  # Loads prompts/support.md
  context: { company: "Acme Corp" },   # Template variables
  local_tools: [OrderLookup]
)
```

### Robot Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Created: RobotLab.build / Robot.new
    Created --> Running: robot.run("message")
    Running --> ToolLoop: tool_call from LLM
    ToolLoop --> Running: tool result sent back
    Running --> Completed: final text response
    Completed --> Running: robot.run("next message")
    Completed --> [*]: robot.disconnect
```

The persistent `@chat` maintains conversation history across multiple `run` calls, making the robot stateful.

### Robot Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | `String` | Unique identifier within network |
| `description` | `String`, `nil` | What the robot does |
| `model` | `String` | LLM model ID (resolved from chat) |
| `template` | `Symbol`, `nil` | Prompt template identifier |
| `system_prompt` | `String`, `nil` | Inline system prompt |
| `local_tools` | `Array` | Locally defined tools |
| `mcp_clients` | `Hash` | Connected MCP clients by server name |
| `mcp_tools` | `Array` | Tools discovered from MCP servers |
| `memory` | `Memory` | Inherent key-value memory |
| `bus` | `TypedBus::MessageBus`, `nil` | Message bus instance |
| `outbox` | `Hash` | Sent messages tracked with status and replies |
| `mcp_config` | `Symbol`, `Array` | Build-time MCP configuration |
| `tools_config` | `Symbol`, `Array` | Build-time tools configuration |

### Running a Robot

The primary method is `robot.run("message")`:

```ruby
result = robot.run("What is the weather in Berlin?")
puts result.last_text_content
```

`run` defaults to `mcp: :none, tools: :none`. Those defaults are *explicit* "send nothing this turn" values, not "unset" — so a plain `run` connects no MCP servers and sends the LLM zero tools even when `local_tools:`/`mcp:` were supplied at build time. Opt in per run:

```ruby
robot.run("...", tools: :inherit)                 # send the attached local tools
robot.run("...", mcp: :inherit, tools: :inherit)  # connect MCP servers and send their tools
```

With other runtime overrides:

```ruby
result = robot.run("Analyze this",
  memory: { data: report },
  tools: :inherit
)
```

With streaming — the block receives a `RubyLLM::Chunk`, whose text is in `content`:

```ruby
robot.run("Tell me a story") do |chunk|
  print chunk.content
end
```

An `on_content:` callback (constructor kwarg or `RunConfig` field) fires on every run. When both an `on_content` callback and a block are supplied, both fire, stored callback first.

## Tool

Tools give robots the ability to interact with external systems. There are two patterns for defining tools.

### RubyLLM::Tool Subclass (Primary)

```ruby
class GetWeather < RubyLLM::Tool
  description "Get current weather for a location"

  param :location, type: "string", desc: "City name"
  param :unit, type: "string", desc: "celsius or fahrenheit"

  def execute(location:, unit: "celsius")
    WeatherAPI.current(location, unit: unit)
  end
end
```

Tools defined as `RubyLLM::Tool` subclasses are passed to robots via `local_tools:`:

```ruby
robot = RobotLab.build(
  name: "weather_bot",
  system_prompt: "You provide weather information.",
  local_tools: [GetWeather]
)
```

### RobotLab::Tool.create Factory

For simpler tools that do not need a class:

```ruby
tool = RobotLab::Tool.create(
  name: "get_time",
  description: "Get the current time"
) { |_args| Time.now.to_s }
```

With parameter schema:

```ruby
tool = RobotLab::Tool.create(
  name: "get_weather",
  description: "Get weather for a location",
  parameters: {
    type: "object",
    properties: {
      location: { type: "string", description: "City name" }
    },
    required: ["location"]
  }
) { |args| WeatherAPI.current(args[:location]) }
```

### Tool Execution

When an LLM decides to use a tool:

1. LLM generates a tool call with tool name and arguments
2. `@chat` (RubyLLM) identifies the tool from its registered tools
3. Calls the `execute` method with keyword arguments
4. Result is sent back to the LLM for continued processing
5. Loop repeats until the LLM produces a final text response

### Error Handling

Tool errors are captured and returned to the LLM:

```ruby
def execute(order_id:)
  order = ORDERS[order_id]
  if order
    order
  else
    { error: "Order not found" }
  end
end
```

## Memory

Memory is a reactive key-value store used by robots and networks.

### Standalone vs Network Memory

- **Standalone**: Each robot has its own inherent `Memory` instance (`robot.memory`)
- **In a Network**: All robots share the network's `Memory` instance

```ruby
# Standalone memory
robot.memory[:user_id] = 123
robot.memory[:user_id]  # => 123

# Network memory is passed automatically
network = RobotLab.create_network(name: "pipeline") do
  task :robot_a, robot_a, depends_on: :none
  task :robot_b, robot_b, depends_on: [:robot_a]
end
# Both robot_a and robot_b share network.memory during execution
```

### Reserved Keys

| Key | Type | Description |
|-----|------|-------------|
| `:data` | `StateProxy` | Runtime data (hash-style `memory.data[:key]` and method-style `memory.data.key_name`) |
| `:results` | `Array` | Accumulated robot results |
| `:messages` | `Array` | Conversation history |
| `:session_id` | `String` | Session identifier |
| `:cache` | `Module` | Semantic cache (RubyLLM::SemanticCache) |

### Reactive Features

Memory supports pub/sub semantics for inter-robot communication:

```ruby
# Write a value (notifies subscribers, wakes waiters)
memory.set(:sentiment, { score: 0.8 })

# Read a value (non-blocking)
memory.get(:sentiment)  # => { score: 0.8 } or nil

# Blocking read (waits until value exists)
memory.get(:sentiment, wait: true)    # Blocks indefinitely
memory.get(:sentiment, wait: 30)      # Blocks up to 30s, then raises RobotLab::AwaitTimeout

# Subscribe to changes
memory.subscribe(:sentiment) do |change|
  puts "#{change.key} = #{change.value} (written by #{change.writer})"
end
```

## Message Types

RobotLab uses a type hierarchy for messages:

```mermaid
classDiagram
    Message <|-- TextMessage
    Message <|-- ToolCallMessage
    Message <|-- ToolResultMessage

    class Message {
        +String type
        +String role
        +content
        +String stop_reason
        +text?()
        +tool_call?()
        +tool_result?()
        +stopped?()
    }

    class TextMessage {
        +String content
    }

    class ToolCallMessage {
        +Array~ToolMessage~ tools
    }

    class ToolResultMessage {
        +ToolMessage tool
        +Hash content
        +success?()
        +error?()
    }
```

### Message Roles

| Role | Description |
|------|-------------|
| `user` | Input from the user |
| `assistant` | Response from the LLM |
| `system` | System instructions |
| `tool_result` | Tool execution result |

### Stop Reasons

| Reason | Description |
|--------|-------------|
| `stop` | Natural completion |
| `tool` | Tool call requested |

## RobotResult

The output from a robot execution:

```ruby
result = robot.run("Hello!")

result.robot_name       # => "support_agent"
result.output           # => [TextMessage] built from the final response text
result.tool_calls       # => [] — see note below
result.stop_reason      # => nil — always (see below)
result.created_at       # => Time
result.id               # => UUID string
result.input_tokens     # => Integer
result.output_tokens    # => Integer
result.duration         # => Float, nil (set by Robot#call during pipeline execution)
result.checksum         # => "sha256-hex"
```

`stop_reason` is always `nil` on a `Robot#run` result — `build_result` only copies it when the response responds to `stop_reason`, and `RubyLLM::Message` does not. The table above describes `Message::VALID_STOP_REASONS`, which applies to message objects you construct yourself, not to `RobotResult`. As a consequence `result.stopped?` reduces to `!result.has_tool_calls?`.

`output` is always a single `TextMessage` synthesized from the final response text — it is not a transcript of the turn. `tool_calls` is read off that final assistant message, which no longer carries tool calls once RubyLLM's tool loop has finished, so in practice it is empty; use the `on_tool_call`/`on_tool_result` callbacks or the tool hooks to observe tool usage.

### Accessing Response Content

```ruby
# Get last text response (most common)
text = result.last_text_content

# Check if tools were called
has_tools = result.has_tool_calls?

# Check if execution completed naturally
result.stopped?

# Serialization
result.export     # => Hash (excludes debug fields)
result.to_h       # => Hash (includes debug fields)
result.to_json    # => JSON string
```

## Configuration

Global configuration uses `MywayConfig`. Sources are layered lowest to highest:

1. Bundled defaults (`lib/robot_lab/config/defaults.yml`)
2. Environment-specific overrides (development / test / production)
3. XDG config file (`~/.config/robot_lab/robot_lab.yml` — note the filename repeats the app name; `config.yml` is never read, and this loader does **not** run ERB)
4. Project config (`./config/robot_lab.yml` — ERB is evaluated here)
5. Environment variables (`ROBOT_LAB_*` prefix, double underscore for nesting)
6. Constructor params

The two file layers treat top-level wrappers differently:

- **XDG file** (`~/.config/robot_lab/robot_lab.yml`) — a section named for the current environment **is** honoured. The loader checks `parsed.key?(env)` first (env comes from `Anyway::Settings.current_environment`, then `RAILS_ENV`, then `RACK_ENV`, defaulting to `"development"`) and falls back to the root when no such key exists. So `development:` works, a flat file works, and `production:` is simply skipped while you are in development. Only a `defaults:` wrapper is meaningless — it is not an environment name, so the whole hash is read as flat config and `defaults` is an unknown key.
- **Project file** (`./config/robot_lab.yml`) — outside Rails this must be flat; every wrapper, `defaults:` and environment names alike, is ignored. Inside Rails, `anyway_config` sets `current_environment` to `Rails.env`, which makes this file environmental: a flat project file is then ignored and keys must be nested under `development:` / `test:` / `production:`.

Read via `RobotLab.config`, or set values with the `RobotLab.configure` block, which yields the same `Config` object:

```ruby
RobotLab.config.ruby_llm.model            # => "claude-sonnet-4"
RobotLab.config.ruby_llm.request_timeout  # => 120

RobotLab.configure do |c|
  c.logger = Logger.new($stdout)
end
```

### RunConfig

Global `Config` is distinct from `RunConfig`, the per-run settings object that flows `RobotLab.config → Network → Task → Robot → template front matter → constructor kwargs`. Its fields are:

- **LLM**: `model`, `temperature`, `top_p`, `top_k`, `max_tokens`, `presence_penalty`, `frequency_penalty`, `stop`
- **Capabilities** (`TOOL_FIELDS`): `mcp`, `tools`
- **Callbacks**: `on_tool_call`, `on_tool_result`, `on_content`
- **Infrastructure** (`INFRA_FIELDS`): `bus`, `enable_cache`, `max_tool_rounds`, `token_budget`, `cost_budget`, `ractor_pool_size`, `max_concurrent_robots`, `doom_loop_threshold`, `auto_compact`, `compact_threshold`, `max_tools`

`TOOL_FIELDS` is exactly `[:mcp, :tools]` — those are the two a network propagates. `max_tools` is an infrastructure field, so it is *not* inherited that way.

Per robot, template front matter is the **base**, a `config:` RunConfig merges over it, and constructor kwargs always win. A network-level `config:` propagates only `mcp` and `tools` down to member robots (and only when a robot opts in with `:inherit`); LLM fields and callbacks are never inherited from a network. `max_concurrent_robots` is the one field the network itself consumes.

## Configuration Hierarchy

Tools and MCP servers use a cascading configuration system:

```
RobotLab.config (global)
|
+-- mcp: [server1, server2]
+-- tools: [tool1, tool2]
|
+-- Network config: (RunConfig)
|     |
|     +-- mcp: :inherit | :none | [servers]
|     +-- tools: :inherit | :none | [tools]
|     |
|     +-- Robot (build-time config)
|           |
|           +-- mcp: :inherit | :none | [servers]
|           +-- tools: :inherit | :none | [tools]
|           |
|           +-- Task (per-task) / run() call -- the RUNTIME level
|                 +-- mcp: :none (default) | :inherit | [servers]
|                 +-- tools: :none (default) | :inherit | [tools]
```

Resolution order: **task/runtime > robot build-time > network > global config**.

A `Task`'s `mcp:`/`tools:` are not a separate tier between network and robot. The task injects them into `run_params`, and `Robot#call` pulls them out and passes them to `run` — so they arrive as the *runtime* value and are resolved against the robot's build-time value.

The `:inherit` value pulls from the parent level. `:none` explicitly disables. An explicit array is a **filter over the already-attached tools**, not a local-vs-MCP switch.

Three consequences worth internalizing:

- `run()` defaults both to `:none`, so the runtime level is a deliberate "send nothing this turn" unless you override it. Pass `tools: :inherit` (and `mcp: :inherit`) to use what the robot was built with.
- Build-time `:inherit` depends on there being a parent to inherit from. The parent is recomputed on every run (`network_config&.tools || network_parent_config(network)&.tools || RobotLab.config.tools`), so inside a network whose `config:` sets `tools:`/`mcp:` it is exactly the right way to opt in. For a robot that runs **standalone** the parent is the global `:none`, so build-time `:inherit` matches nothing — leave `tools:` unset there and opt in at run time.
- An explicit array is compared with `tool.name.to_s`, and `Class#name` differs from `RubyLLM::Tool#name`. A tool attached as a class matches `[RefundTool]` (`"RefundTool"`); the same tool attached as an instance matches `%w[refund]`. Both forms work — but the array must be written in the same form the tool was attached in, or it filters everything out. Note that the **build-time** `tools:` kwarg is validated (`validate_tools_filter!`) and accepts only Strings/Symbols; the class form is available only at the task/runtime level, which is not validated. See [Network Orchestration](network-orchestration.md#task-configuration).

## Message Bus

The **Message Bus** provides bidirectional, cyclic communication between robots, independent of the Network pipeline. While Networks enforce DAG-based (acyclic) execution, the bus enables negotiation loops, convergence patterns, and multi-turn dialogues.

### How It Works

Robots connect to a shared `TypedBus::MessageBus` via the `bus:` parameter. Each robot gets a typed channel (accepting only `RobotMessage` objects) named after its `name`. Delivery is routed through a shared `BusPoller`, which runs the handler **in the caller's execution context** (Async fiber or OS thread) rather than on a background thread of its own. A mutex serializes deliveries per robot: if a robot is already processing a message, later ones are queued and drained after the current one returns.

```ruby
bus = TypedBus::MessageBus.new

bob   = RobotLab.build(name: "bob", system_prompt: "You tell jokes.", bus: bus)
alice = RobotLab.build(name: "alice", system_prompt: "You evaluate jokes.", bus: bus)
```

### RobotMessage

`RobotMessage` is an immutable `Data.define` value object used as the typed envelope:

| Field | Type | Description |
|-------|------|-------------|
| `id` | `Integer` | Per-robot sequential counter |
| `from` | `String` | Sender's robot name (= channel name) |
| `content` | `String`, `Hash` | Message payload |
| `in_reply_to` | `String`, `nil` | Composite key of the original message (e.g., `"alice:1"`) |

Methods: `key` returns `"from:id"` composite identity; `reply?` returns true when `in_reply_to` is set.

### Sending and Receiving

```ruby
# Send a message to another robot
alice.send_message(to: :bob, content: "Tell me a joke.")

# Handle incoming messages with auto-ack (1 arg)
bob.on_message do |message|
  joke = bob.run(message.content.to_s).last_text_content
  bob.send_reply(to: message.from.to_sym, content: joke, in_reply_to: message.key)
end
```

Block arity controls delivery handling: 1 argument auto-acks; 2 arguments give manual control over `delivery.ack!`/`delivery.nack!`.

`send_message`/`send_reply` synchronize the per-robot message counter and outbox with an internal mutex, so concurrent sends from multiple threads and reply correlation can't clobber each other — the bus is safe to send on from more than one thread at a time. (There is no poller thread doing the correlating: as described above, `BusPoller#enqueue` processes deliveries inline in the caller's context.)

For the common case of a robot that should simply answer whatever tasks arrive on the bus, `respond_to_tasks`/`serve` do the `on_message` wiring above in one call:

```ruby
bob.serve  # equivalent to the on_message block above, running bob.run and replying automatically
```

`respond_to_tasks` takes a block instead when the reply needs post-processing, and both ignore inbound messages that are themselves replies, so two robots calling `serve` on each other don't loop. See [Auto-Responding to Bus Tasks](../guides/building-robots.md#auto-responding-to-bus-tasks).

### Dynamic Spawning

Robots can create new robots at runtime using `spawn`. The bus is created lazily — no upfront wiring required:

```ruby
dispatcher = RobotLab.build(name: "dispatcher", system_prompt: "You delegate work.")

# spawn creates a child on the same bus (bus created automatically)
helper = dispatcher.spawn(name: "helper", system_prompt: "You answer questions.")

# The child can immediately communicate with the parent
answer = helper.run("What is 2+2?").last_text_content
helper.send_message(to: :dispatcher, content: answer)
```

The spawned robot inherits its parent's `model`/`provider`, so a dispatcher running on a local provider (e.g. Ollama) spawns specialists targeting that same model instead of falling back to the global default (which would fail without cloud credentials). Explicit `model:`/`provider:` passed to `spawn` still override.

Robots can also join a bus after creation using `with_bus`:

```ruby
bot = RobotLab.build(name: "late_joiner", system_prompt: "Hello.")
bot.with_bus(existing_bus)  # now connected to the bus
```

**Fan-out messaging**: Multiple robots with the same name all subscribe to the same channel. Messages sent to that name are delivered to all subscribers:

```ruby
worker1 = dispatcher.spawn(name: "worker", system_prompt: "Worker 1")
worker2 = dispatcher.spawn(name: "worker", system_prompt: "Worker 2")
dispatcher.send_message(to: :worker, content: "Do this task")
# Both worker1 and worker2 receive the message
```

### Bus vs Network

| Feature | Network | Message Bus |
|---------|---------|-------------|
| Execution model | DAG (acyclic) | Cyclic, bidirectional |
| Communication | Sequential pipeline | Pub/sub channels |
| Memory | Shared network memory | Independent per-robot |
| Use case | Linear workflows | Negotiation, convergence |

The bus is purely additive — robots without `bus:` work exactly as before.

## Network

A Network orchestrates multiple robots in a pipeline workflow using SimpleFlow:

```ruby
network = RobotLab.create_network(name: "support") do
  task :classifier, classifier_robot, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
  task :technical, technical_robot, depends_on: :optional
end

result = network.run(message: "I need help with billing")
```

Networks provide:

- **DAG-based execution** via SimpleFlow with `depends_on:` for sequencing
- **Parallel execution** for tasks with the same dependencies
- **Optional tasks** activated dynamically by classifier robots
- **Shared memory** for inter-robot communication
- **Per-task configuration** via the `Task` wrapper
- **Broadcast messaging** for network-wide announcements

Robots can be added to a network without a pipeline task via `add_robot`, and removed again with `remove_robot(name)` (returns the removed robot, or `nil` if absent). `remove_robot` only drops the robot from the crew — it doesn't rewrite the pipeline, so avoid removing a robot that's still referenced by a task's `depends_on`.

## Runnable Protocol

`RobotLab::Runnable` is a shared interface implemented by both `Robot` and `Network`, so callers can treat either uniformly instead of branching on `is_a?(RobotLab::Network)`:

```ruby
def summarize(runnable)
  runnable.crew.each { |r| puts r.name }
  puts "chief: #{runnable.chief.name}"
  puts runnable.network? ? "network of #{runnable.robot_count}" : "single robot"
end

summarize(robot)    # crew: [robot], chief: robot, "single robot"
summarize(network)  # crew: network.robots.values, chief: crew.first, "network of N"
```

| Method | Robot | Network |
|--------|-------|---------|
| `crew` | `[self]` | `robots.values` (pipeline order) |
| `chief` | `self` | `crew.first` |
| `robot_count` | `1` | `crew.size` |
| `network?` | `false` | `true` |
| `single?` | `true` | `false` |
| `run(message = nil, **opts)` | accepts a positional message (already did) | now also accepts a positional message, folded into `message:` — the keyword form still works |

`crew` is the only method implementers must define themselves; `chief`, `robot_count`, and `single?` all derive from it, and `network?` defaults to `false` unless overridden (as `Network` does).

## Next Steps

- [Robot Execution](robot-execution.md) - Detailed execution flow
- [Network Orchestration](network-orchestration.md) - Multi-robot coordination
- [Using Tools](../guides/using-tools.md) - Creating and using tools
