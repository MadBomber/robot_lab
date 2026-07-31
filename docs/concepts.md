# Core Concepts

Understanding the fundamental concepts in RobotLab will help you build effective AI applications.

## Robot

A **Robot** is an LLM-powered agent that inherits from `RubyLLM::Agent`. Each robot wraps a persistent chat session created at initialization and provides template-based prompts, tools, memory, and MCP integration. Robots are created using keyword arguments via the `RobotLab.build` factory method.

Each robot has:

- **Name**: An identifier. Nothing is auto-generated — if you omit `name:` the robot is literally named `"robot"`. The value is load-bearing: a robot still named `"robot"` is treated as "unnamed", which is what lets a template's `robot_name:` front matter key take effect. Give every robot an explicit name.
- **Template**: A `.md` file with YAML front matter managed by prompt_manager, referenced by symbol
- **System Prompt**: Inline instructions (can be used alone or combined with a template)
- **Model**: The LLM model to use (defaults to `RobotLab.config.ruby_llm.model`)
- **Provider**: Optional LLM provider for local models (Ollama, GPUStack, etc.)
- **Skills**: Composable template behaviors prepended before the main template
- **Local Tools**: `RubyLLM::Tool` subclasses or `RobotLab::Tool` instances (with automatic error handling)
- **Streaming**: Real-time content via stored `on_content` callback or per-call block
- **Memory**: Persistent key-value store across runs

```ruby
# Robot with template (references prompts/support.md)
robot = RobotLab.build(
  name: "support_agent",
  template: :support,
  context: { tone: "friendly", department: "billing" },
  local_tools: [OrderLookup, RefundProcessor],
  model: "claude-sonnet-4"
)

# Attached tools are only sent when the run asks for them
robot.run("Where is order 4471?", tools: :inherit)

# Robot with inline system prompt
robot = RobotLab.build(
  name: "helper",
  system_prompt: "You are a friendly customer support agent."
)

# Bare robot configured via chaining
robot = RobotLab.build(name: "bot")
robot.with_instructions("Be concise.").with_temperature(0.3).run("Hello")
```

The primary method is `robot.run("message")`, which takes a positional string argument and returns a `RobotResult`:

```ruby
result = robot.run("What is 2 + 2?")
puts result.last_text_content  # => "4"
```

Standalone robots persist their conversation history and memory across runs:

```ruby
robot.run("My name is Alice.")
result = robot.run("What is my name?")
puts result.last_text_content  # => "Your name is Alice."
```

## Configuration

RobotLab uses `MywayConfig` for configuration. Values are loaded automatically from multiple sources in priority order (lowest to highest):

1. Bundled defaults (`lib/robot_lab/config/defaults.yml`)
2. Environment-specific overrides (development, test, production)
3. XDG user config (`~/.config/robot_lab/robot_lab.yml`)
4. Project config (`./config/robot_lab.yml`)
5. Environment variables (`ROBOT_LAB_*` prefix)
6. Constructor parameters

```ruby
# Access configuration values
RobotLab.config.ruby_llm.model            #=> "claude-sonnet-4"
RobotLab.config.ruby_llm.request_timeout  #=> 120

# Set API keys via environment variables
# ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...
# ROBOT_LAB_RUBY_LLM__OPENAI_API_KEY=sk-...

# A configure block also exists, for runtime-only attributes such as the logger
RobotLab.configure do |c|
  c.logger = Logger.new(File::NULL)
end

# Reload configuration
RobotLab.reload_config!
```

> [!IMPORTANT]
> Two easy mistakes. First, the user config file is
> `~/.config/robot_lab/**robot_lab**.yml` — the filename repeats the app name, and
> `config.yml` is never read. Second, the `defaults:` wrapper used inside the gem's
> bundled `defaults.yml` is silently ignored in your own files; write keys flat, or
> under a section named for the current environment. The user file honours a
> `development:` / `test:` / `production:` section; `./config/robot_lab.yml` must be
> flat outside Rails but **must** be environment-sectioned under Rails. See
> [Configuration](getting-started/configuration.md) for the full matrix.

## Network

A **Network** is a collection of robots orchestrated using [SimpleFlow](https://github.com/MadBomber/simple_flow) pipelines. Networks provide:

- **Task-Based Orchestration**: Define tasks with dependencies and routing
- **Parallel Execution**: Tasks with the same dependencies run concurrently
- **Optional Task Activation**: Dynamic routing based on robot output
- **Per-Task Configuration**: Each task can have its own context, tools, and MCP servers
- **Shared Memory**: All robots in a network share a reactive memory instance

```ruby
network = RobotLab.create_network(name: "customer_service") do
  task :classifier, classifier_robot, depends_on: :none
  task :billing, billing_robot,
       context: { department: "billing" },
       depends_on: :optional
  task :technical, technical_robot,
       context: { department: "technical" },
       depends_on: :optional
end

result = network.run(message: "I was charged twice for my subscription.")
```

## Task

A **Task** wraps a robot for use in a network pipeline with per-task configuration:

- **Context**: Task-specific context deep-merged with network run params
- **MCP**: MCP servers available to this task (`:none`, `:inherit`, or a name array)
- **Tools**: Tools available to this task (`:none`, `:inherit`, or a name array)
- **Memory**: Task-specific memory
- **Dependencies**: `:none`, `[:task1, :task2]`, or `:optional`
- **Config**: a `RunConfig` — but see the caveat below
- **Poller group**: `poller_group:` (defaults to `:default`)

```ruby
# The robot must already have the tools ATTACHED...
billing_robot = RobotLab.build(
  name: "billing",
  system_prompt: "You handle billing.",
  local_tools: [RefundTool, InvoiceTool, AuditTool]   # attached as CLASSES
)

task :billing, billing_robot,
     context: { department: "billing", escalation_level: 2 },
     tools: [RefundTool, InvoiceTool],   # ...and this SELECTS from them
     depends_on: :optional
```

> [!WARNING]
> An explicit `tools:` array is a **name allowlist** over tools the robot already
> has attached — it is not a way to attach new tools, and it is not a
> local-vs-MCP switch. Attach tools with `local_tools:` when building the robot,
> then filter here.
>
> **The allowlist entries must match the form the tool was attached in.** Matching
> is a string comparison against each attached tool's `name`, and `Class#name`
> differs from `RubyLLM::Tool#name`:
>
> | Attached as | Matching allowlist entry | Does not match |
> |---|---|---|
> | `local_tools: [RefundTool]` (class) | `[RefundTool]` or `%w[RefundTool]` | `%w[refund]` |
> | `local_tools: [RefundTool.new]` (instance) | `%w[refund]` | `[RefundTool]` |
>
> A task-level `config:` is merged into the network config, so like a
> network-level config it propagates **only `mcp` and `tools`** — not `model`,
> `temperature`, or callbacks.

## SimpleFlow::Result

Networks use `SimpleFlow::Result` for data flow between tasks:

```ruby
result.value      # Current task's output (RobotResult)
result.context    # Accumulated context, keyed by ROBOT name
result.continue?  # Whether the pipeline is still continuing
result.errors     # Accumulated errors
```

> [!NOTE]
> There is no `halted?` and no `continued?` — both raise `NoMethodError`. The
> predicate is `continue?`. Note also that `result.context` is keyed by each
> robot's `name:`, not by its task name.

### Result Methods

The complete public API is `activate`, `activated_steps`, `context`, `continue`,
`continue?`, `errors`, `halt`, `value`, `with_context`, and `with_error`.

| Method | Purpose |
|--------|---------|
| `continue(value)` | Continue to next tasks |
| `halt(value)` | Stop pipeline execution |
| `with_context(key, val)` | Add data to context |
| `with_error(key, message)` | Record an error |
| `activate(task_name)` | Enable optional task |
| `activated_steps` | Tasks activated so far |

## Tool

**Tools** give robots the ability to interact with external systems. `RobotLab::Tool` extends `RubyLLM::Tool` with graceful error handling — if `execute` raises a `StandardError`, the error is caught and returned as a plain-text string (`"Error (tool_name): message"`) so the LLM can reason about it. Critical tools can opt out with `self.raise_on_error = true`.

There are two patterns for defining tools:

### RubyLLM::Tool Subclass (Preferred)

```ruby
class Calculator < RubyLLM::Tool
  description "Performs basic arithmetic operations"

  param :operation, type: "string", desc: "The operation (add, subtract, multiply, divide)"
  param :a, type: "number", desc: "First operand"
  param :b, type: "number", desc: "Second operand"

  def execute(operation:, a:, b:)
    case operation
    when "add" then a + b
    when "subtract" then a - b
    when "multiply" then a * b
    when "divide" then a.to_f / b
    else "Unknown operation: #{operation}"
    end
  end
end

robot = RobotLab.build(
  name: "math_bot",
  system_prompt: "You can do math.",
  local_tools: [Calculator]
)

# tools: :inherit is required -- run() sends no tools by default
robot.run("What is 17 * 23?", tools: :inherit)
```

> [!WARNING]
> `Robot#run` defaults to `mcp: :none, tools: :none`, and an explicit `:none`
> means "send zero tools this turn". Attaching tools with `local_tools:` does
> **not** by itself make them available — a plain `robot.run("...")` sends the
> model no tools at all. Pass `tools: :inherit` on the run (and
> `mcp: :inherit, tools: :inherit` for MCP servers).
>
> For a **standalone** robot, do not pass `tools: :inherit` to `RobotLab.build`.
> Build-time `:inherit` resolves against the parent level, which for a standalone
> robot is the global `:none` — that produces an allowlist matching nothing and
> suppresses the tools even when the run asks for them. Leave `tools:` unset.
>
> Inside a **network** it means the opposite: build-time `tools: :inherit` is
> exactly how a robot opts into the allowlist carried by the network's `config:`.
> With `RunConfig.new(tools: %w[RefundTool])` on the network and `tools: :inherit`
> on both the robot and its task, the robot sends only `refund`; leaving the
> robot's `tools:` unset sends everything it has attached instead.

### RobotLab::Tool.create Factory

```ruby
tool = RobotLab::Tool.create(
  name: "get_weather",
  description: "Get current weather for a location",
  parameters: {
    type: "object",
    properties: {
      location: { type: "string", description: "City name" }
    },
    required: ["location"]
  }
) { |args| WeatherService.current(args[:location]) }
```

## RobotResult

`RobotResult` captures the output of a single `robot.run(...)` call:

```ruby
result = robot.run("Hello!")

result.last_text_content  # => "Hi there!" (String or nil)
result.reply              # => alias for last_text_content
result.output             # => [TextMessage] built from the final response text
result.tool_calls         # => [] (see note below -- effectively always empty)
result.robot_name         # => "assistant"
result.stop_reason        # => nil (always -- see note below)
result.has_tool_calls?    # => false
result.checksum           # => "a1b2c3d4..." (for dedup)
result.duration           # => Float or nil (elapsed seconds, set in pipeline execution)
result.raw                # => raw LLM response object
```

> [!NOTE]
> `result.tool_calls` and `result.has_tool_calls?` read the **final** assistant
> message. By the time `run` returns, ruby_llm's tool loop has already completed
> and that message carries no tool calls — so in practice `tool_calls` is always
> empty and `has_tool_calls?` is always `false`. To observe tool activity, use
> the `on_tool_call` / `on_tool_result` callbacks instead. Likewise
> `result.output` is a single-element array built from the final response text,
> not a transcript of the whole turn.
>
> `result.stop_reason` is likewise **always `nil`**: `RubyLLM::Message` does not
> define `stop_reason`, and `RobotResult` only populates the field when the
> response responds to it. It is dropped from `result.export` for the same reason.
> Because `stopped?` is derived from the absence of tool calls, it is
> correspondingly always `true`. Do not branch on `"end_turn"` / `"tool_use"`.

## Memory

**Memory** is a reactive key-value store that provides persistent storage across robot executions. Standalone robots use their own inherent memory; robots in a network share the network's memory.

```ruby
# Standalone robot with inherent memory
robot = RobotLab.build(name: "assistant", system_prompt: "You are helpful.")
robot.run("My name is Alice")
robot.run("What's my name?")  # Memory persists across runs

# Access robot's memory directly
robot.memory[:user_id] = 123
robot.memory.data[:category] = "billing"
robot.memory.data.category  # => "billing" (method-style access)

# Runtime memory injection
robot.run("Help me", memory: { session_id: "abc123" })

# Reset the key-value store (does NOT clear chat history)
robot.reset_memory

# Clear chat history (does NOT touch the key-value store)
robot.clear_messages(keep_system: true)
```

> [!NOTE]
> `reset_memory` and `clear_messages` are independent. A robot's conversation
> history and its key-value memory are two separate stores; clearing one leaves
> the other intact.

### Reserved Memory Keys

| Key | Purpose |
|-----|---------|
| `:data` | Runtime data (StateProxy for method-style access) |
| `:results` | Accumulated robot results |
| `:messages` | Conversation history |
| `:session_id` | Session identifier for history persistence |
| `:cache` | Semantic cache instance (RubyLLM::SemanticCache) |

### Reactive Memory in Networks

In a network, shared memory supports pub/sub semantics for inter-robot communication:

```ruby
# Robot A writes to shared memory
network.memory.set(:sentiment, { score: 0.8 })

# Robot B reads (blocking until available)
result = network.memory.get(:sentiment, wait: true)
result = network.memory.get(:sentiment, wait: 30)  # timeout in seconds

# Multiple keys -- the timeout applies PER MISSING KEY, not to the call as a whole
results = network.memory.get(:sentiment, :entities, :keywords, wait: 60)

# Subscribe to changes
network.memory.subscribe(:status) do |change|
  puts "#{change.key} changed by #{change.writer}: #{change.value}"
end
```

> [!WARNING]
> A blocking `get` that times out **raises `RobotLab::AwaitTimeout`** — it does
> not return `nil`. Wrap it in a `rescue` if a missing key is an acceptable
> outcome. With several keys, the timeout is applied to each missing key in turn,
> so `get(:a, :b, :c, wait: 60)` can block for up to 180 seconds.

## MCP (Model Context Protocol)

**MCP** allows robots to connect to external tool servers:

```ruby
robot = RobotLab.build(
  name: "developer",
  system_prompt: "You are a developer assistant.",
  mcp: [
    { name: "filesystem", transport: { type: "stdio", command: "mcp-server-filesystem" } },
    { name: "github", transport: { type: "stdio", command: "mcp-server-github" } }
  ]
)

# Connect the servers AND expose their tools for this run
robot.run("List the Ruby files in ./lib", mcp: :inherit, tools: :inherit)
```

> [!IMPORTANT]
> `transport:` must be a **nested hash** — `transport: { type: "stdio", command: ..., args: [...] }`.
> A flat `transport: stdio` with sibling `command:`/`args:` keys raises
> `NoMethodError: undefined method 'transform_keys' for an instance of String`,
> and that exception is **swallowed** rather than raised: the robot builds
> successfully with zero tools. It is not silent, though — a line is logged at
> `WARN` through `RobotLab.config.logger` (`Robot 'dev' error connecting to MCP
> server 'fs': undefined method 'transform_keys' for an instance of String`) and
> the server name lands in `robot.failed_mcp_server_names`. An *invalid* transport
> type is swallowed the same way; only a direct `MCP::Server.new` raises
> `ArgumentError`. Valid transport types are `stdio`, `sse`, `ws`,
> `websocket`, `streamable-http`, and `http` (`streamable_http` with an
> underscore is invalid).
>
> `mcp:` also defaults to `:none` on `run`. `mcp: :inherit` triggers the
> connection attempt; `tools: :inherit` is additionally required for the MCP
> tools to reach the model. MCP connection failures are logged and recorded in
> `robot.failed_mcp_server_names` — they are not raised.

MCP configuration follows a hierarchical resolution: `runtime > robot > network > global config`. Values can be `:none`, `:inherit`, or explicit arrays.

## Execution Flow

```mermaid
sequenceDiagram
    participant User
    participant Network
    participant Pipeline
    participant Task
    participant Robot
    participant LLM
    participant Tool

    User->>Network: run(message: "...", **context)
    Network->>Pipeline: call_parallel(initial_result)
    Pipeline->>Task: call(result)
    Task->>Robot: call(enhanced_result)
    Robot->>Robot: extract_run_context(result)
    Robot->>LLM: ask(message)

    alt Tool Call
        LLM-->>Robot: tool_call
        Robot->>Tool: execute(params)
        Tool-->>Robot: result
        Robot->>LLM: continue with result
    end

    LLM-->>Robot: response
    Robot-->>Task: RobotResult
    Task-->>Pipeline: result.continue(robot_result)

    alt Optional Task Activated
        Pipeline->>Task: call activated task
    end

    Pipeline-->>Network: final result
    Network-->>User: SimpleFlow::Result
```

## Conditional Routing with ClassifierRobot

Use a custom Robot subclass to implement intelligent routing. Override `call(result)` to inspect the LLM output and activate optional tasks:

```ruby
class ClassifierRobot < RobotLab::Robot
  def call(result)
    # Extract context and message from the pipeline result
    context = extract_run_context(result)
    message = context.delete(:message)

    # Run the robot to classify the input
    robot_result = run(message, **context)

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    # Activate the appropriate specialist based on classification
    category = robot_result.last_text_content.to_s.strip.downcase
    case category
    when /billing/ then new_result.activate(:billing)
    when /technical/ then new_result.activate(:technical)
    else new_result.activate(:general)
    end
  end
end

# Build the classifier (uses a .md template with YAML front matter)
classifier = ClassifierRobot.new(
  name: "classifier",
  template: :classifier,
  model: "claude-sonnet-4"
)

# Build specialist robots
billing_robot = RobotLab.build(name: "billing", template: :billing)
technical_robot = RobotLab.build(name: "technical", template: :technical)
general_robot = RobotLab.build(name: "general", template: :general)

# Create network with optional task routing
network = RobotLab.create_network(name: "support_network") do
  task :classifier, classifier, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
  task :technical, technical_robot, depends_on: :optional
  task :general, general_robot, depends_on: :optional
end

result = network.run(message: "I was charged twice for my subscription.")
puts result.value.last_text_content
```

## Message Bus

The **Message Bus** enables bidirectional, cyclic communication between robots via `typed_bus`. While Networks enforce DAG-based execution, the bus supports negotiation loops, convergence patterns, and multi-turn dialogues.

```ruby
bus = TypedBus::MessageBus.new

bob   = RobotLab.build(name: "bob", system_prompt: "You tell jokes.", bus: bus)
alice = RobotLab.build(name: "alice", system_prompt: "You evaluate jokes.", bus: bus)

# Register handlers
bob.on_message do |message|
  joke = bob.run(message.content.to_s).last_text_content
  bob.send_reply(to: message.from.to_sym, content: joke, in_reply_to: message.key)
end

alice.on_message do |message|
  verdict = alice.run("Is this funny? #{message.content}").last_text_content
  # Send another request if not satisfied
  alice.send_message(to: :bob, content: "Try again.") unless verdict.start_with?("FUNNY")
end

# Start the conversation
alice.send_message(to: :bob, content: "Tell me a robot joke.")
```

Key features:

- **Typed channels** — only `RobotMessage` objects accepted per channel
- **Auto-ACK** — 1-arg `on_message` blocks auto-acknowledge; 2-arg blocks give manual control
- **Reply correlation** — `send_reply(to:, content:, in_reply_to:)` tracks threads via `in_reply_to`
- **Independent of Network** — bus works without a Network pipeline

### Dynamic Spawning

Robots can create new robots at runtime using `spawn`. The bus is created lazily:

```ruby
dispatcher = RobotLab.build(name: "dispatcher", system_prompt: "You delegate work.")

# spawn creates a child on the same bus (bus created automatically)
helper = dispatcher.spawn(name: "helper", system_prompt: "You answer questions.")
answer = helper.run("What is 2+2?").last_text_content
helper.send_message(to: :dispatcher, content: answer)
```

Robots can also join a bus after creation with `with_bus`:

```ruby
bot = RobotLab.build(name: "latecomer", system_prompt: "Hello.")
bot.with_bus(existing_bus)
```

Multiple robots with the same name enable fan-out — messages sent to that name are delivered to all subscribers.

## Templates

Templates are `.md` files with YAML front matter, managed by the prompt_manager gem. They live in the configured template path (default: `./prompts/` or `app/prompts/` in Rails).

```markdown
---
description: Customer support classifier
model: claude-sonnet-4
temperature: 0.3
---
You are a request classifier. Analyze the user's request and classify it
as either "billing", "technical", or "general".

Respond with ONLY the category name, nothing else.
```

Reference templates by symbol when building robots:

```ruby
robot = RobotLab.build(
  name: "classifier",
  template: :classifier,           # loads prompts/classifier.md
  context: { tone: "professional" } # variables passed to the template
)
```

### Front Matter Keys

Templates support two categories of front matter keys:

**LLM Config:** only `model` and `temperature` take effect.

**Robot Extras:** `robot_name`, `description`, `tools`, `mcp`, `skills`, `parameters` — applied to the robot's identity and capabilities. These make templates self-contained: reading the `.md` file tells you everything about the robot.

> [!WARNING]
> Front matter is parsed into a `RunConfig` and then applied by dispatching
> `chat.with_<field>` for each field the chat responds to. The chat object only
> has `with_model` and `with_temperature`, so **`top_p`, `top_k`, `max_tokens`,
> `presence_penalty`, `frequency_penalty`, and `stop` are parsed and silently
> dropped** when declared in front matter. A template declaring all eight yields
> a chat with empty params.
>
> Those six *do* work as constructor keyword arguments or via a `config:`
> `RunConfig`, because that path goes through `with_params`:
>
> ```ruby
> RobotLab.build(name: "bot", template: :writer, max_tokens: 2000, top_p: 0.3)
> ```

```markdown
---
description: GitHub assistant with MCP tool access
robot_name: github_bot
tools:
  - CodeSearchTool
mcp:
  - name: github
    transport:
      type: stdio
      command: npx
      args: ["-y", "@modelcontextprotocol/server-github"]
model: claude-sonnet-4
---
You are a GitHub assistant. Use available tools to help with repository tasks.
```

> [!IMPORTANT]
> Note the **nested** `transport:` mapping above. A flat
> `transport: stdio` with sibling `command:`/`args:` keys raises a `NoMethodError`
> that is swallowed rather than propagated, leaving you with a robot that has no
> tools. Look for the `WARN` line on `RobotLab.config.logger` and check
> `robot.failed_mcp_server_names` — both record the failure.

```ruby
# Template provides everything — minimal constructor
robot = RobotLab.build(template: :github_assistant)

# ...but the tools and MCP servers it declares still have to be requested per run
robot.run("Open issues in MadBomber/robot_lab?", mcp: :inherit, tools: :inherit)
```

Constructor-provided values (`local_tools:`, `mcp:`, `name:`, `description:`) always take precedence over front matter values. In the cascade, front matter is the **base**: template front matter → `config:` RunConfig → constructor keyword arguments, with constructor arguments always winning.

## Next Steps

- [Quick Start Guide](getting-started/quick-start.md) - Build your first robot
- [Building Robots](guides/building-robots.md) - Detailed robot creation guide
- [Creating Networks](guides/creating-networks.md) - Network orchestration patterns
