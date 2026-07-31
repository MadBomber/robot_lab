# Robot

LLM-powered agent with template-based prompts, tools, memory, and MCP integration.

## Class Hierarchy

```
RubyLLM::Agent
  └── RobotLab::Robot
        └── Your custom subclasses (e.g., ClassifierRobot)
```

`Robot` inherits from `RubyLLM::Agent`, which creates a persistent `@chat` on initialization. The robot adds template-based prompts, shared memory, hierarchical MCP configuration, and SimpleFlow pipeline integration on top of the base agent.

`Robot` also includes `RobotLab::Runnable` and the mixins
`Robot::TemplateRendering`, `Robot::MCPManagement`, `Robot::BusMessaging`,
`Robot::HistorySearch`, `Robot::Budget`, and `Robot::Hooking`, and prepends
`Robot::AgentSkillMatching`.

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `Robot::DEFAULT_MAX_TOOLS` | `128` | Ceiling on the number of tools handed to the provider per turn. Override per robot with `RunConfig#max_tools`; a nil, zero, or negative `max_tools` falls back to this default, so the cap cannot be disabled |

## Constructor

```ruby
Robot.new(
  name:,                      # required
  template: nil,
  system_prompt: nil,
  context: {},
  description: nil,
  local_tools: [],
  model: nil,
  provider: nil,
  mcp_servers: [],
  mcp: :none,
  tools: :none,
  on_tool_call: nil,
  on_tool_result: nil,
  on_content: nil,
  enable_cache: true,
  bus: nil,
  skills: nil,
  temperature: nil,
  top_p: nil,
  top_k: nil,
  max_tokens: nil,
  presence_penalty: nil,
  frequency_penalty: nil,
  stop: nil,
  max_tool_rounds: nil,
  token_budget: nil,
  cost_budget: nil,
  doom_loop_threshold: nil,
  mcp_discovery: false,
  config: nil
)
```

!!! warning "The keyword list is closed"
    `Robot#initialize` has no `**rest`. Any keyword not listed above raises
    `ArgumentError`. In particular `auto_compact:`, `compact_threshold:`,
    `ractor_pool_size:`, `max_concurrent_robots:`, and `max_tools:` are
    **`RunConfig` fields only** — pass them via `config:`, not as constructor
    kwargs. There is no `memory:`, `learn:`, or `learn_domain:` keyword.

### Parameters

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `String` | **required** | Identifier for the robot. `RobotLab.build` defaults it to the literal string `"robot"`; that default is load-bearing — front-matter `robot_name:` is applied only when the constructor name is still `"robot"` |
| `template` | `Symbol`, `nil` | `nil` | Prompt template (e.g., `:assistant` loads `prompts/assistant.md`) |
| `system_prompt` | `String`, `nil` | `nil` | Inline system prompt (appended after template if both given) |
| `context` | `Hash`, `Proc` | `{}` | Variables passed to the template |
| `description` | `String`, `nil` | `nil` | Human-readable description of what the robot does |
| `local_tools` | `Array` | `[]` | Tools defined locally (`RubyLLM::Tool` subclasses or `RobotLab::Tool` instances) |
| `model` | `String`, `nil` | `nil` | LLM model ID (falls back to `RobotLab.config.ruby_llm.model`) |
| `provider` | `String`, `Symbol`, `nil` | `nil` | LLM provider for local providers (e.g., `:ollama`, `:gpustack`). Automatically sets `assume_model_exists: true` |
| `mcp_servers` | `Array` | `[]` | Legacy MCP server configurations |
| `mcp` | `Symbol`, `Array` | `:none` | Hierarchical MCP config (`:none`, `:inherit`, or server array) |
| `tools` | `Symbol`, `Array` | `:none` | Hierarchical tools config (`:none`, `:inherit`, or tool name **array**). Must be tool *names* (String/Symbol) — `validate_tools_filter!` raises `ArgumentError` for an instance or class, telling you to use `local_tools:` instead. **For a standalone robot, leave this unset at build time**: `tools: :inherit` here resolves against the global parent `:none` and yields an allowlist that matches nothing. Inside a network whose `config:` sets `tools:`, build-time `:inherit` is the correct way to opt in. See [Runtime Tool Filtering](../../guides/using-tools.md#runtime-tool-filtering) |
| `on_tool_call` | `Proc`, `nil` | `nil` | Callback invoked when a tool is called |
| `on_tool_result` | `Proc`, `nil` | `nil` | Callback invoked when a tool returns a result |
| `on_content` | `Proc`, `nil` | `nil` | Stored streaming callback invoked with each content chunk (see [Streaming](#streaming)) |
| `enable_cache` | `Boolean` | `true` | Whether to enable semantic caching |
| `bus` | `TypedBus::MessageBus`, `nil` | `nil` | Optional message bus for inter-robot communication |
| `skills` | `Symbol`, `Array<Symbol>`, `nil` | `nil` | Skill templates to prepend (see [Skills](#skills)) |
| `max_tool_rounds` | `Integer`, `nil` | `nil` | Circuit breaker: raise `ToolLoopError` after this many tool calls in one `run()` (see [Tool Loop Circuit Breaker](#tool-loop-circuit-breaker)) |
| `token_budget` | `Integer`, `nil` | `nil` | Raise `InferenceError` if cumulative tokens exceed this limit after a call; raise `BudgetExceeded` up front if already exhausted (see [Budgets](#budgets)) |
| `cost_budget` | `Float`, `nil` | `nil` | Same enforcement as `token_budget`, tracked in cumulative dollar cost instead of tokens (requires provider pricing data) |
| `doom_loop_threshold` | `Integer`, `nil` | `nil` | Tunes the always-on doom-loop detector (default threshold 3). See [Doom Loop Detection](#doom-loop-detection) |
| `mcp_discovery` | `Boolean` | `false` | When true, the first run narrows the configured MCP server list to those `MCP::ServerDiscovery` judges relevant to the message |
| `config` | `RunConfig`, `nil` | `nil` | Shared config merged with explicit kwargs (see [RunConfig](#runconfig)) |
| `temperature` | `Float`, `nil` | `nil` | Controls randomness — applied via `chat.with_temperature` |
| `top_p` | `Float`, `nil` | `nil` | Nucleus sampling threshold — applied via `chat.with_params` |
| `top_k` | `Integer`, `nil` | `nil` | Top-k sampling — applied via `chat.with_params` |
| `max_tokens` | `Integer`, `nil` | `nil` | Maximum tokens in response — applied via `chat.with_params` |
| `presence_penalty` | `Float`, `nil` | `nil` | Penalize based on presence — applied via `chat.with_params` |
| `frequency_penalty` | `Float`, `nil` | `nil` | Penalize based on frequency — applied via `chat.with_params` |
| `stop` | `String`, `Array`, `nil` | `nil` | Stop sequences — applied via `chat.with_params` |

When both `config:` and explicit kwargs (e.g., `temperature:`) are provided, explicit kwargs always win.

`model` and `temperature` are applied to the chat with dedicated `with_model` /
`with_temperature` calls. The remaining six LLM fields (`top_p`, `top_k`,
`max_tokens`, `presence_penalty`, `frequency_penalty`, `stop`) are collected into
a single `chat.with_params(...)` call. This distinction matters for template
front matter — see [Templates](#templates).

## Factory Method

```ruby
robot = RobotLab.build(
  name: "robot",      # Defaults to "robot"
  template: nil,
  system_prompt: nil,
  context: {},
  enable_cache: true,
  bus: nil,           # Optional TypedBus::MessageBus
  skills: nil,        # Optional skill templates
  config: nil,        # Optional RunConfig
  **options           # All other Robot.new parameters
)
# => RobotLab::Robot
```

If `name` is omitted, it defaults to the literal string `"robot"`. `**options`
is forwarded verbatim to `Robot.new`, whose keyword list is closed — an unknown
option raises `ArgumentError`.

## Attributes (Read-Only)

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | `String` | Unique identifier |
| `description` | `String`, `nil` | Human-readable description |
| `template` | `Symbol`, `nil` | Prompt template identifier |
| `system_prompt` | `String`, `nil` | Inline system prompt |
| `skills` | `Array<Symbol>`, `nil` | Constructor-provided skill template IDs (nil if none) |
| `provider` | `String`, `nil` | LLM provider name (e.g., `"ollama"`) — set when using local providers |
| `local_tools` | `Array` | Locally defined tools |
| `mcp_clients` | `Hash<String, MCP::Client>` | Connected MCP clients, keyed by server name |
| `mcp_tools` | `Array<Tool>` | Tools discovered from MCP servers |
| `memory` | `Memory` | Inherent memory (used when standalone, not in network) |
| `bus` | `TypedBus::MessageBus`, `nil` | Message bus instance (nil if not configured) |
| `outbox` | `Hash` | Sent messages tracked by composite key with status and replies |
| `config` | `RunConfig` | Effective RunConfig (merged from constructor kwargs and passed-in config) |
| `mcp_config` | `Symbol`, `Array` | Build-time MCP configuration (raw, unresolved) |
| `tools_config` | `Symbol`, `Array` | Build-time tools configuration (raw, unresolved) |
| `total_input_tokens` | `Integer` | Cumulative input tokens sent across all `run()` calls |
| `total_output_tokens` | `Integer` | Cumulative output tokens received across all `run()` calls |
| `learnings` | `Array<String>` | Accumulated cross-run observations (see [Learning Accumulation](#learning-accumulation)) |
| `budget_ledger` | `RobotLab::Budget::Ledger`, `nil` | Reserve/reconcile ledger backing `token_budget`/`cost_budget`; `nil` when neither is configured (see [Budgets](#budgets)) |
| `hooks` | `RobotLab::HookRegistry` | This robot's own hook registry. Populated by [`robot.on`](#on); consulted alongside `RobotLab.hooks` and the network's registry on every run |

## Attributes (Read-Write)

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `input` | `IO`, `nil` | `nil` | Input stream for user interaction (falls back to `$stdin`) |
| `output` | `IO`, `nil` | `nil` | Output stream for user interaction (falls back to `$stdout`) |

Used by tools like [`AskUser`](tool.md#built-in-askuser) that need terminal IO. Set to `StringIO` for testing.

## Methods

### run

```ruby
result = robot.run(message = nil, network: nil, task: nil,
                   network_memory: nil, network_config: nil, memory: nil,
                   mcp: :none, tools: :none, hooks: nil, **kwargs, &block)
# => RobotResult
```

Primary execution method. Sends a message to the LLM with memory/MCP/tools resolution and returns a `RobotResult`.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `message` | `String`, `nil` | `nil` | The user message to send (positional, optional) |
| `network` | `Network`, `nil` | `nil` | Network context (passed internally by `Network#run`) |
| `task` | `Task`, `nil` | `nil` | Task wrapper for the current pipeline step (passed internally); surfaces on hook contexts |
| `network_memory` | `Memory`, `nil` | `nil` | Shared network memory (passed internally) |
| `network_config` | `RunConfig`, `nil` | `nil` | Network-level config used when resolving `:inherit` for `mcp`/`tools` (passed internally) |
| `memory` | `Memory`, `Hash`, `nil` | `nil` | A `Memory` replaces the active memory for this run; a `Hash` is merged into it |
| `mcp` | `Symbol`, `Array` | `:none` | Runtime MCP override — `:inherit` (all attached servers), `:none`/`[]` (zero this turn), or an explicit array |
| `tools` | `Symbol`, `Array` | `:none` | Runtime tools override — `:inherit` (all attached tools), `:none`/`[]` (zero this turn), or an explicit name array. See [Runtime Tool Filtering](../../guides/using-tools.md#runtime-tool-filtering) |
| `hooks` | `Array`, `nil` | `nil` | Per-run hook handler classes, active only for this call |
| `**kwargs` | `Hash` | `{}` | See below — **not** a passthrough to `Agent#ask` |
| `&block` | `Proc` | `nil` | Per-call streaming block, receives each content chunk |

**What `**kwargs` actually does.** Only `:with` is forwarded to the underlying
`Agent#ask` (`kwargs.slice(:with)`). *Every other* keyword is treated as
template re-render context: `kwargs.except(:with)` is merged over the build-time
context and the template is re-rendered before the call. If the robot has no
`template:`, those extra keywords are simply ignored.

```ruby
robot = RobotLab.build(name: "support", template: :support)
robot.run("Help me", company: "Acme")     # re-renders the template with company: "Acme"
robot.run("Describe this", with: image)   # forwarded to Agent#ask as attachments
```

When both a stored `on_content` callback and a runtime block are provided, both fire (stored first, then runtime block).

!!! warning "`tools:`/`mcp:` default to `:none` here"
    A bare `robot.run(message)` sends **zero** tools and connects **no** MCP
    servers for that call, even when `local_tools:`/`mcp:` were supplied at
    build time. Pass `tools: :inherit` (and/or `mcp: :inherit`) explicitly to
    use what is attached. `mcp: :inherit` triggers the connection attempt;
    `tools: :inherit` is additionally required for the MCP tools to be sent.

Each call's resolved tool set *replaces* the chat's tools rather than accumulating, so a subsequent `:none` call correctly clears whatever a prior call attached, and the fully-resolved set is clamped to `max_tools` (`DEFAULT_MAX_TOOLS = 128` by default) right before being handed to the provider — see [Tool Capping](../../guides/using-tools.md#tool-capping-and-per-turn-filtering).

**Returns:** `RobotResult`

**Examples:**

```ruby
# Simple message — sends no tools, connects no MCP servers
result = robot.run("What is 2+2?")

# Send the tools attached via local_tools:
result = robot.run("What is 15 * 7?", tools: :inherit)

# Connect MCP servers and send their tools
result = robot.run("Search the repo", mcp: :inherit, tools: :inherit)

# Restrict this turn to a named subset
result = robot.run("Look it up", tools: %w[order_lookup])

# With runtime memory
result = robot.run("Summarize the data", memory: { data: report })

# With per-call streaming block
result = robot.run("Tell me a story") { |chunk| print chunk.content }
```

### model

```ruby
robot.model  # => "claude-sonnet-4" or nil
```

Returns the model ID string. Resolves through the underlying chat object.

### effective_config

```ruby
robot.effective_config
# => { model: "claude-sonnet-4-20250514", temperature: 0.7, max_tokens: 4096 }
```

Snapshot of the robot's merged `RunConfig` as a plain Hash, `.compact`ed so unset
fields are omitted. Reports exactly these keys when set: `model`, `temperature`,
`top_p`, `top_k`, `max_tokens`, `presence_penalty`, `frequency_penalty`, `stop`,
`tools`, `mcp`, `max_tool_rounds`, `doom_loop_threshold`, `auto_compact`,
`compact_threshold`, `token_budget`, `cost_budget`.

This is a *view*, not the config object — use `robot.config` for the `RunConfig` itself.

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

The five named parameters are applied directly (`template` re-renders the prompt;
`system_prompt`, `model`, and `temperature` call the corresponding `with_*` on the chat).

!!! warning "`**kwargs` only reaches fields the chat exposes as `with_<key>`"
    Each extra keyword is forwarded as `@chat.with_#{key}(value)` **only if
    `@chat.respond_to?(:"with_#{key}")`**. `RubyLLM::Chat` has no
    `with_max_tokens`, `with_top_p`, `with_top_k`, `with_stop`,
    `with_presence_penalty`, or `with_frequency_penalty` — so
    `robot.update(max_tokens: 4000)` silently does nothing. Use
    `robot.with_params(max_tokens: 4000)` for those fields.

### with_* Methods (Chaining)

`with_*` methods are discovered from `RubyLLM::Chat` at construction time and
defined as singleton methods that delegate to the persistent `@chat` and return
`self` for chaining. This is the **complete** set:

| Method | Description |
|--------|-------------|
| `with_model(model_id)` | Change the LLM model |
| `with_temperature(temp)` | Set temperature |
| `with_instructions(prompt)` | Set system instructions |
| `with_tool(tool)` | Add a single tool |
| `with_tools(*tools)` | Add multiple tools |
| `with_params(**params)` | Set arbitrary provider parameters |
| `with_headers(**headers)` | Set custom headers |
| `with_schema(schema)` | Set output schema |
| `with_context(**ctx)` | Set context |
| `with_thinking(opts)` | Enable extended thinking |

Plus two defined by RobotLab itself:

| Method | Description |
|--------|-------------|
| `with_template(id, **context)` | Apply a prompt_manager template (see below) |
| `with_bus(bus = nil)` | Connect to a message bus (creates one if nil) |

!!! danger "These do not exist"
    `with_max_tokens`, `with_top_p`, `with_top_k`, `with_stop`,
    `with_presence_penalty`, and `with_frequency_penalty` are **not** defined
    and raise `NoMethodError`. Set those fields with a constructor kwarg
    (`max_tokens: 2000`) or with `with_params`:

    ```ruby
    robot.with_params(max_tokens: 2000, top_p: 0.3)
    ```

**Example:**

```ruby
robot = RobotLab.build(name: "bot")
robot
  .with_model("claude-sonnet-4")
  .with_temperature(0.7)
  .with_params(max_tokens: 2000)
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

SimpleFlow step interface. Extracts the message from `result.context[:run_params]`, calls `run`, and wraps the output in a continued `SimpleFlow::Result`. Automatically records `RobotResult#duration` (elapsed seconds).

If the robot raises any exception during execution, the error is caught and wrapped in a `RobotResult` with the error message as content. This ensures one failing robot does not crash the entire network pipeline.

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

Publish a message to another robot's bus channel. Increments the internal message counter, creates a `RobotMessage`, tracks it in the outbox, and publishes to the target channel. The counter and outbox mutation are synchronized with an internal mutex, so concurrent `send_message`/`send_reply` calls from multiple threads and reply correlation never clobber each other.

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

### respond_to_tasks

```ruby
robot.respond_to_tasks(auto_reply: true) { |message| "the reply content" }
# => self
```

Auto-answer inbound (non-reply) bus tasks: run the block to produce a reply, and send it back to the sender. This is the symmetric counterpart to how a `robot_lab-cyborg` Cyborg answers its human — one call makes any bus member a first-class responder without hand-wiring `on_message` yourself.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `auto_reply` | `Boolean` | `true` | Send the block's result back to the sender via `send_reply` |
| `&responder` | `Proc` | **required** | Receives the inbound `message`; return the reply content (`nil` means no reply) |

**Returns:** `self`

Messages that are themselves replies (`message.reply?`) are ignored, so a two-way `respond_to_tasks` conversation between robots does not loop. The responder runs **inline in the caller's context** — `BusPoller` has no background thread; its `enqueue` either processes the delivery immediately or queues it behind the one in flight and drains it when that finishes. Deliveries to a given robot are therefore handled one at a time, and a long-running responder blocks the sender as well as the next inbound message.

```ruby
bob.respond_to_tasks { |message| "handled: #{message.content}" }
alice.send_message(to: :bob, content: "ping")
# bob replies "handled: ping" back to alice automatically
```

### serve

```ruby
robot.serve(auto_reply: true)
# => self
```

The common case of `respond_to_tasks`: run every inbound task through this robot's own `#run` and reply with the result — the one-call way to make a Robot cooperate on the bus the way a Cyborg already does out of the box.

```ruby
bob.serve
alice.send_message(to: :bob, content: "Tell me a joke.")
# bob runs "Tell me a joke." through its LLM and replies with the result
```

Equivalent to `respond_to_tasks(auto_reply: auto_reply) { |message| run(message.content).reply }` (with Hash-content messages flattened to `"key: value"` lines first).

### spawn

```ruby
child = robot.spawn(
  name: "specialist",
  system_prompt: "You are a specialist."
)
# => RobotLab::Robot (connected to same bus)
```

Create a new robot on the same message bus. If the parent has no bus, one is created automatically and the parent is connected to it.

The spawned robot inherits its parent's `model` and `provider` (via `robot.model`/`robot.provider`) so a specialist runs on the same LLM as the robot that spawned it — a robot running on a local Ollama model, for instance, spawns specialists that also target that model rather than falling back to `RobotLab.config.ruby_llm.model` (the global default, typically a cloud model that would fail without credentials). Caller-supplied `model:`/`provider:` in `**options` still override.

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

### connect_mcp!

```ruby
robot.connect_mcp!
# => self
```

Eagerly connect to configured MCP servers and discover tools. Normally MCP connections are lazy (established on first `run`). Call this to connect early, e.g., to display connection status at startup.

**Returns:** `self`

### failed_mcp_server_names

```ruby
robot.failed_mcp_server_names
# => Array<String>
```

Returns server names that failed to connect. Useful for displaying connection status or deciding whether to retry.

### inject_mcp!

```ruby
robot.inject_mcp!(clients: mcp_clients, tools: mcp_tools)
# => self
```

Inject pre-connected MCP clients and their tools into this robot. Used by host applications that manage MCP connections externally and need to pass them to robots without re-connecting.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `clients` | `Hash<String, MCP::Client>` | Connected MCP clients keyed by server name |
| `tools` | `Array<Tool>` | Tools discovered from the MCP servers |

**Returns:** `self`

**Example:**

```ruby
# Host app manages MCP connections
clients = { "github" => github_client }

# There is no Tool.from_mcp — MCP wrappers are built with Tool.create,
# exactly as RobotLab's own discover_mcp_tools does.
tools = github_client.list_tools.map do |tool_def|
  name = tool_def[:name]
  RobotLab::Tool.create(
    name:        name,
    description: tool_def[:description],
    parameters:  tool_def[:inputSchema],
    mcp:         "github"
  ) { |args| github_client.call_tool(name, args) }
end

robot.inject_mcp!(clients: clients, tools: tools)
```

### chat

```ruby
robot.chat
# => RubyLLM::Chat
```

Access the underlying `RubyLLM::Chat` instance. Useful for checkpoint/restore operations that need direct access to conversation state.

### messages

```ruby
robot.messages
# => Array<RubyLLM::Message>
```

Return the conversation messages from the underlying chat.

### clear_messages

```ruby
robot.clear_messages(keep_system: true)
# => self
```

Clear conversation messages, optionally keeping the system prompt.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `keep_system` | `Boolean` | `true` | Whether to preserve the system message |

**Returns:** `self`

### replace_messages

```ruby
robot.replace_messages(messages)
# => self
```

Replace conversation messages with a saved set. Useful for checkpoint/restore workflows.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `messages` | `Array<RubyLLM::Message>` | The messages to restore |

**Returns:** `self`

**Example:**

```ruby
# Save a checkpoint
saved = robot.messages.dup

# ... later, restore it
robot.replace_messages(saved)
```

### compress_history

```ruby
robot.compress_history(
  recent_turns: 3,
  keep_threshold: 0.6,
  drop_threshold: 0.2,
  summarizer: nil
)
# => self
```

Shrink the conversation by scoring each older turn against the most recent
context and dropping or summarizing the least relevant ones. Internally builds a
`RobotLab::HistoryCompressor` and hands the result to `replace_messages`.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `recent_turns` | `Integer` | `3` | Turn pairs at the end that are always kept verbatim |
| `keep_threshold` | `Float` | `0.6` | Cosine score at or above this → kept verbatim |
| `drop_threshold` | `Float` | `0.2` | Cosine score below this → dropped |
| `summarizer` | `#call`, `nil` | `nil` | `callable(text) -> String` applied to the medium tier; `nil` drops the medium tier instead |

**Returns:** `self`

System messages and tool-call/tool-result messages are always preserved.

Scoring uses **term-frequency cosine similarity without IDF** (see
`RobotLab::Convergence`), so it is a lexical overlap measure, not a semantic one.

**Raises:** `RobotLab::DependencyError` when the optional `classifier` gem
(`~> 2.3`) is not installed.

```ruby
robot.compress_history(recent_turns: 5, summarizer: ->(text) { text[0, 200] })
```

`auto_compact: :context_window` on a `RunConfig` calls this automatically before
an LLM call once estimated tokens exceed `compact_threshold` (default `0.80`) of
the model's context window. When the `classifier` gem is missing there, the
`DependencyError` is caught, logged at `:warn`, and compaction is skipped.

### delegate

```ruby
result = robot.delegate(to:, task:, async: false, **run_kwargs)
# => RobotResult (async: false) | DelegationFuture (async: true)
```

Hand a task to another robot and annotate the result with delegation metadata.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `to` | `Robot` | **required** | The robot to delegate to |
| `task` | `String` | **required** | The message to send |
| `async` | `Boolean` | `false` | When true, returns a `DelegationFuture` immediately |
| `**run_kwargs` | `Hash` | `{}` | Forwarded verbatim to the delegatee's `run` — including `tools:`/`mcp:`, which still default to `:none` |

**Synchronous** (default) blocks until the delegatee finishes and returns its
`RobotResult` with `duration` and `delegated_by` set.

**Asynchronous** (`async: true`) runs the delegatee on a new `Thread` and returns
a `RobotLab::DelegationFuture`. Call `future.value` to block, `future.value(timeout: N)`
to block with a deadline (raises `RobotLab::DelegationFuture::DelegationTimeout`),
or `future.resolved?` to poll. An exception in the delegatee is captured and
re-raised from `future.value`.

```ruby
# Synchronous
result = manager.delegate(to: analyst, task: "What are the risks?")
result.reply
result.delegated_by   # => "manager"
result.duration       # => 1.43

# Async fan-out
f1 = manager.delegate(to: summarizer, task: "summarize ...", async: true)
f2 = manager.delegate(to: analyst,    task: "analyze ...",   async: true, tools: :inherit)
summary  = f1.value
analysis = f2.value(timeout: 30)
```

### search_history

```ruby
results = robot.search_history(query, limit: 5)
# => Array<RobotLab::Robot::HistorySearch::HistoryResult>
```

Rank the robot's own conversation messages against a natural-language query
using stemmed term-frequency cosine similarity.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `query` | `String` | **required** | Natural-language search query |
| `limit` | `Integer` | `5` | Maximum results to return |

**Returns:** `Array<HistoryResult>` sorted by score descending. `HistoryResult`
is a `Data` type with members `text`, `role`, `score`, and `index`.

Messages shorter than `MIN_SCORE_LENGTH` (20 characters) are skipped, as are
messages that score zero.

**Raises:** `RobotLab::DependencyError` when the optional `classifier` gem is not installed.

```ruby
robot.search_history("quarterly revenue", limit: 3).each do |r|
  puts "[#{r.role}] (#{r.score.round(3)}) #{r.text}"
end
```

### on

```ruby
robot.on(HandlerClass, context: nil)
# => the registration
```

Register a hook handler on **this robot's** registry (`robot.hooks`). The robot's
registry is consulted on every run alongside `RobotLab.hooks` (global) and the
network's registry, in that order.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `handler_class` | `Class` | **required** | The hook handler class |
| `context` | `Object`, `nil` | `nil` | Optional per-registration context passed to the handler |

!!! note "Task hooks bypass robot registries"
    The `:task` hook family resolves against `[RobotLab.hooks, network&.hooks]`
    only. A handler registered with `robot.on` never fires for task hooks —
    register it with `RobotLab.on` or `network.on` instead.

Handlers can also be scoped to a single call with `robot.run(msg, hooks: [HandlerClass])`.

### chat_provider

```ruby
robot.chat_provider
# => String or nil
```

Return the provider for this robot's chat. Useful for displaying model/provider info without reaching into chat internals.

### mcp_client

```ruby
robot.mcp_client("github")
# => MCP::Client or nil
```

Find an MCP client by server name.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `server_name` | `String` | The MCP server name |

**Returns:** `MCP::Client` or `nil`

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

Returns a hash representation of the robot. Keys, in order: `name`,
`description`, `template`, `skills`, `system_prompt`, `local_tools` (tool names),
`mcp_tools` (tool names), `mcp_config`, `tools_config`, `mcp_servers` (connected
client names), `model`, `config` (the `RunConfig` as a JSON-safe hash, omitted
when the config is empty), and `bus` (`true` if configured, omitted otherwise).
The whole hash is `.compact`ed, so nil values are dropped.

```ruby
RobotLab.build(name: "x", max_tokens: 100).to_h
# => { name: "x", local_tools: [], mcp_tools: [], mcp_config: :none,
#      tools_config: :none, mcp_servers: [], model: "claude-sonnet-4-20250514",
#      config: { max_tokens: 100, enable_cache: true } }
```

The `config` value comes from `RunConfig#to_json_hash`, which omits the
non-serializable fields (`on_tool_call`, `on_tool_result`, `on_content`, `bus`,
`auto_compact`).

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

Front matter supports two categories of keys.

**LLM Config:** `model`, `temperature`, `top_p`, `top_k`, `max_tokens`,
`presence_penalty`, `frequency_penalty`, `stop` are all *parsed* into a
`RunConfig`.

!!! warning "Only `model` and `temperature` actually take effect from front matter"
    Front-matter LLM fields are applied through `RunConfig#apply_to`, which
    dispatches `chat.with_<field>` guarded by `respond_to?`. `RubyLLM::Chat`
    defines only `with_model` and `with_temperature`, so `top_p`, `top_k`,
    `max_tokens`, `presence_penalty`, `frequency_penalty`, and `stop` are parsed
    and **silently dropped**. Set those six as constructor kwargs or on a
    `config:` `RunConfig` instead — that path goes through `with_params` and
    does work.

**Robot Extras:** `robot_name`, `description`, `tools`, `mcp`, `skills` — applied to the robot's identity and capabilities. Constructor-provided values always take precedence.

| Key | Type | Description |
|-----|------|-------------|
| `robot_name` | `String` | Override robot name — applied only when the constructor name is still the default `"robot"` |
| `description` | `String` | Human-readable description; applied only when the constructor passed no `description:` |
| `tools` | `Array` | Tool entries; applied only when `local_tools:` is empty (see below) |
| `mcp` | `Array<Hash>` | MCP server configurations; applied only when the constructor `mcp:` is `:none` |
| `skills` | `Array<Symbol>` | Skill templates to prepend (recursive, with cycle detection) |

Templates render with ERB — write `<%= var %>`. `{{ var }}` is not interpolated
and passes through verbatim.

### Front-matter `tools:` resolution

Front-matter `tools` entries are resolved by `resolve_frontmatter_tools`, and the
result becomes `local_tools` (real tool objects), **not** the `tools_config`
name allowlist. Three entry shapes are accepted:

| Entry | Behavior |
|-------|----------|
| `String` | Resolved with `Object.const_get`. If the constant is a `Class` that is `< RubyLLM::Tool`, it is **instantiated** (`const.new`); any other constant is used as-is |
| `Class` | **Instantiated** (`name.new`) |
| anything else | Used as-is (e.g. an already-built tool instance) |

An unresolvable name does **not** raise. It is logged at `:warn`
(`"Robot '<name>': tool '<X>' not found, skipping"`) and skipped.

```markdown
---
tools:
  - OrderLookup      # instantiated: OrderLookup.new
  - RefundProcessor
---
```

Because `run()` still defaults to `tools: :none`, front-matter tools are sent
only when you pass `tools: :inherit` at run time.

## Skills

Skills compose robot behaviors from reusable templates. Each skill is a standard `.md` template whose prompt body is prepended before the main template. Skills are expanded depth-first with automatic cycle detection.

**Constructor:** `skills:` accepts `Symbol` or `Array<Symbol>`:

```ruby
robot = RobotLab.build(
  name: "support",
  template: :support,
  skills: [:clarifier, :json_responder]
)
```

**Front matter:** templates can declare skills via `skills:` key:

```markdown
---
skills:
  - clarifier
  - json_responder
---
Main template body here.
```

Constructor `skills:` and front matter `skills:` are combined (constructor first, then front matter). Skills can nest (a skill can declare its own `skills:` in front matter).

**Config cascade:** skill config merges in processing order (deepest first). Later values override earlier. Constructor kwargs always win.

**Prompt order:** skill bodies are concatenated in expansion order, followed by the main template body. All are joined with `"\n\n"` and set as system instructions via a single `with_instructions` call.

**Cycle detection:** if skills form a cycle, the duplicate is skipped with a logger warning.

## RunConfig

`RunConfig` provides shared operational defaults that flow through the configuration hierarchy. Pass it via the `config:` parameter on `Robot.new` or `RobotLab.build`.

```ruby
shared = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.7)

robot = RobotLab.build(
  name: "writer",
  system_prompt: "You write creatively.",
  config: shared,
  temperature: 0.9  # explicit kwargs override config
)

robot.config  #=> RunConfig with model: "claude-sonnet-4", temperature: 0.9, ...
```

`RunConfig::FIELDS` is the complete, authoritative list. Passing any other key to
`RunConfig.new` raises `ArgumentError: Unknown RunConfig field: ...`.

| Group | Constant | Fields |
|-------|----------|--------|
| LLM | `LLM_FIELDS` | `model`, `temperature`, `top_p`, `top_k`, `max_tokens`, `presence_penalty`, `frequency_penalty`, `stop` |
| Tools | `TOOL_FIELDS` | `mcp`, `tools` |
| Callbacks | `CALLBACK_FIELDS` | `on_tool_call`, `on_tool_result`, `on_content` |
| Infrastructure | `INFRA_FIELDS` | `bus`, `enable_cache`, `max_tool_rounds`, `token_budget`, `cost_budget`, `ractor_pool_size`, `max_concurrent_robots`, `doom_loop_threshold`, `auto_compact`, `compact_threshold`, `max_tools` |

Five of those infrastructure fields are `RunConfig`-only — they are **not**
`Robot.new` keywords: `ractor_pool_size`, `max_concurrent_robots`,
`auto_compact`, `compact_threshold`, `max_tools`. (`max_concurrent_robots` is
consumed by `Network`, not by `Robot`; `ractor_pool_size` by the
`robot_lab-ractor` extension.)

```ruby
config = RobotLab::RunConfig.new(auto_compact: :context_window, compact_threshold: 0.7, max_tools: 32)
robot  = RobotLab.build(name: "long_runner", system_prompt: "...", config: config)
```

Other `RunConfig` API:

| Method | Description |
|--------|-------------|
| `RunConfig.new(**kwargs) { \|c\| ... }` | Keyword construction plus an optional block DSL (`c.model "..."`) |
| `#merge(other)` | Returns a **new** RunConfig; the other's non-nil values win |
| `#to_h` | The explicitly-set fields |
| `#to_json_hash` | `to_h` minus `NON_SERIALIZABLE_FIELDS` (`on_tool_call`, `on_tool_result`, `on_content`, `bus`, `auto_compact`) |
| `#apply_to(chat, provider: nil, assume_model_exists: false)` | Applies `LLM_FIELDS` via `chat.with_<field>`, guarded by `respond_to?` |
| `#empty?` / `#key?(field)` | Introspection |
| `RunConfig.from_front_matter(metadata)` | Builds a RunConfig from a template's parsed metadata |

!!! note "A network-level `config:` only propagates `mcp` and `tools`"
    LLM fields and callbacks (`on_content`, `on_tool_call`, `on_tool_result`)
    are read from the robot's own config at construction time and are never
    inherited from a network. A member robot picks up the network's `mcp`/`tools`
    only when it opts in with `:inherit`. `max_concurrent_robots` is the one
    field the network itself consumes.

See [Configuration: RunConfig](../../getting-started/configuration.md#runconfig-shared-operational-defaults) for full details.

## Streaming

Robots support two complementary approaches for streaming LLM content in real-time.

### The Chunk Object

Both callbacks and blocks receive a [`RubyLLM::Chunk`](https://rubyllm.com/streaming/#basic-streaming) (subclass of `RubyLLM::Message`). Key accessors:

| Accessor | Type | Description |
|----------|------|-------------|
| `content` | `String`, `nil` | The text delta for this chunk (`nil` on tool-call or usage-only chunks) |
| `role` | `Symbol` | Always `:assistant` |
| `model_id` | `String` | The LLM model ID |
| `tool_calls` | `Array`, `nil` | Tool call deltas (partial JSON arguments) |
| `tool_call?` | `Boolean` | Whether this chunk contains tool call data |
| `thinking` | `Thinking`, `nil` | Extended thinking delta (Anthropic only) |
| `input_tokens` | `Integer`, `nil` | Input token count (populated on final chunk) |
| `output_tokens` | `Integer`, `nil` | Output token count (populated on final chunk) |
| `cached_tokens` | `Integer`, `nil` | Cached prompt tokens (final chunk) |

Most chunks carry only `content` (the text delta). The final chunk(s) carry token usage counts. Tool call chunks have `tool_calls` instead of `content`.

### Stored Callback (`on_content:`)

Wired at build time via constructor or RunConfig. Fires on every `run()` call automatically:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are helpful.",
  on_content: ->(chunk) { broadcast(chunk.content) }
)
robot.run("Tell me a story")  # streams via stored callback
```

The `on_content` callback participates in the RunConfig cascade:

```ruby
config = RobotLab::RunConfig.new(
  on_content: ->(chunk) { log(chunk.content) }
)
robot = RobotLab.build(name: "bot", config: config)
```

Constructor `on_content:` overrides RunConfig `on_content`.

### Per-Call Block

Pass a block to `run()` for one-off streaming:

```ruby
robot.run("Tell me a story") { |chunk| print chunk.content }
```

### Both Together

When both exist, both fire — stored callback first, then runtime block:

```ruby
robot = RobotLab.build(
  name: "bot",
  system_prompt: "You are helpful.",
  on_content: ->(chunk) { log(chunk.content) }
)
robot.run("Tell me a story") { |chunk| stream_to_client(chunk.content) }
# log() fires first, then stream_to_client()
```

## Configuration Hierarchy

Tools and MCP servers use hierarchical resolution: **runtime > robot > task > network > global config**.

```
RobotLab.config (global)
  |
  +-- Network (config:)  -- propagates only mcp/tools to members
  |     |
  |     +-- Task (config:)  -- likewise only mcp/tools
  |     |     |
  |     |     +-- Robot (config: + build-time mcp:, tools:)
  |     |           |
  |     |           +-- run() call (runtime mcp:, tools:)  <- default :none
```

Values at each level:

- `:none` -- no tools/MCP at this level (the default at every level)
- `:inherit` -- inherit from the parent level
- `Array` -- a filter over the already-attached tools, or a list of MCP server configs. Entries are matched against `tool.name.to_s`, so they must be written in the same form the tool was attached in: a class-attached tool matches `"RefundTool"`, an instance-attached one matches `"refund"`. (The constructor's `tools:` accepts only Strings/Symbols; the class form is usable at the task/`run` level, which is not validated.)

!!! danger "For a standalone robot, do not set `tools: :inherit` at build time"
    The parent is recomputed on every run as
    `network_config&.tools || network_parent_config(network)&.tools || RobotLab.config.tools`.
    For a **standalone** robot that resolves to the global `:none`, so a
    build-time `:inherit` produces the allowlist `["none"]`, which matches
    nothing. Leave `tools:` unset on the constructor and pass `tools: :inherit`
    on `run()` instead.

    | build `tools:` | run `tools:` | tools sent |
    |---|---|---|
    | unset | `:none` (default) | none |
    | unset | `:inherit` | all attached — **the correct pattern** |
    | `:inherit` | `:inherit` | none — broken |
    | `:none` | `:inherit` | all attached |

    This does **not** generalize to robots inside a network. When the network's
    `config:` sets `tools:`/`mcp:`, the parent resolved at run time is that
    network value, and a build-time `:inherit` is exactly how the robot opts
    into it. See [MCP in Networks](../mcp/index.md#mcp-in-networks).

### Per-robot config cascade

For a single robot, least- to most-specific:

```
template front matter  ->  config: (RunConfig)  ->  constructor kwargs
```

Front matter is the **base**, not an override. Constructor kwargs always win.

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

# run() defaults to tools: :none — pass :inherit to actually send Calculator
result = robot.run("What is 15 * 7?", tools: :inherit)
```

Note that `param` accepts only `type:`, `desc:`/`description:`, and `required:` —
there is no `enum:` option. See [Tool](tool.md#param).

### Robot with Local Provider

```ruby
robot = RobotLab.build(
  name: "local_bot",
  model: "llama3.2",
  provider: :ollama,
  system_prompt: "You are helpful."
)
result = robot.run("Hello!")
```

`provider:` is threaded through on every re-application of the effective `RunConfig` — including when a template's front matter is re-rendered mid-run — so a local-provider robot (Ollama, GPUStack, LM Studio) doesn't fall back to RubyLLM's static model registry lookup on later turns and raise a spurious "model not found" error.

Some local/thinking-mode models (e.g. `qwen3` on Ollama) route all of their output through reasoning content rather than the normal response text. When `response.content` is `nil`, `result.reply` falls back first to `response.thinking.text` (RubyLLM's extended-thinking text), then to the most recent assistant text from later in *the current turn only* — never a stale reply left over from a previous turn.

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

# mcp: :inherit triggers the connection; tools: :inherit sends the discovered tools
result = robot.run("Search for popular Ruby repos", mcp: :inherit, tools: :inherit)
robot.disconnect
```

`transport:` must be a nested hash. MCP connection failures are logged and
recorded in `robot.failed_mcp_server_names` — they are not raised.

### Robot with Skills

```ruby
robot = RobotLab.build(
  name: "support",
  template: :support,
  skills: [:clarifier, :safety, :json_responder],
  context: { company: "Acme Corp" }
)
result = robot.run("I need help with my order")
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

## Token & Cost Tracking

Every `robot.run()` returns a `RobotResult` with token counts for that call. The robot accumulates running totals across all runs.

### RobotResult Token Fields

| Field | Type | Description |
|-------|------|-------------|
| `input_tokens` | `Integer` | Input tokens sent to the LLM in this run (0 if provider doesn't report usage) |
| `output_tokens` | `Integer` | Output tokens received from the LLM in this run (0 if not reported) |

### Robot Cumulative Totals

| Attribute | Type | Description |
|-----------|------|-------------|
| `total_input_tokens` | `Integer` | Cumulative input tokens across all `run()` calls |
| `total_output_tokens` | `Integer` | Cumulative output tokens across all `run()` calls |

### reset_token_totals

```ruby
robot.reset_token_totals
# => the robot itself (returns self, so it chains)
```

Reset the cumulative accounting counters to zero. Useful when you want to measure cost for a specific task batch while keeping the robot alive for the next batch.

> **Note:** This resets the *accounting counter only* — the underlying chat history keeps growing. The next run's `input_tokens` will reflect the full accumulated chat context sent to the API.

**Example:**

```ruby
robot = RobotLab.build(name: "analyst", system_prompt: "You are helpful.")

result = robot.run("What is a stack?")
puts result.input_tokens    # e.g. 120
puts result.output_tokens   # e.g. 45

result2 = robot.run("And a queue?")
puts result2.input_tokens   # larger — full chat history sent

puts robot.total_input_tokens   # 120 + result2.input_tokens
puts robot.total_output_tokens

# Start a fresh accounting batch
robot.reset_token_totals
puts robot.total_input_tokens   # => 0
```

### Budgets

`token_budget:` and `cost_budget:` turn the counters above into enforceable ceilings, backed by a thread-safe `RobotLab::Budget::Ledger` (`robot.budget_ledger`, `nil` when neither is configured):

```ruby
robot = RobotLab.build(
  name: "capped",
  system_prompt: "...",
  token_budget: 10_000,
  cost_budget: 0.50
)
```

Each `run()` reserves the remaining budget for every configured dimension before the LLM call, and reconciles the reservation with actual usage after:

- **`RobotLab::BudgetExceeded`** — raised up front when a *prior* call already exhausted a dimension; the new call is refused before it spends anything.
- **`RobotLab::InferenceError`** — raised after the call when *this* call's actual usage (from `RobotResult#input_tokens`/`output_tokens`, and the response's reported cost when the provider supports pricing) pushes cumulative usage over budget. This is the same error `token_budget` alone has always raised; `cost_budget` uses the analogous message (`"Cost budget exceeded: $X used, budget is $Y"`).

See [Budgets](../../guides/observability.md#budgets-token-cost) for the full walkthrough.

## Tool Loop Circuit Breaker

Set `max_tool_rounds:` to guard against a robot looping indefinitely through tool calls. After the limit is reached, `RobotLab::ToolLoopError` is raised.

### max_tool_rounds Parameter

```ruby
robot = RobotLab.build(
  name: "runner",
  system_prompt: "Execute every step.",
  local_tools: [StepTool],
  max_tool_rounds: 10
)
```

`max_tool_rounds` can also be set via `RunConfig`:

```ruby
config = RobotLab::RunConfig.new(max_tool_rounds: 10)
robot = RobotLab.build(name: "runner", system_prompt: "...", config: config)
```

### ToolLoopError

`RobotLab::ToolLoopError < RobotLab::InferenceError`

Raised when the number of tool calls in a single `run()` exceeds `max_tool_rounds`. The message reads:

```
Circuit breaker triggered: <N> tool calls exceeded max_tool_rounds (<M>)
```

where `N` is the call count that tripped the breaker and `M` is the configured limit.

### Recovery after ToolLoopError

After a `ToolLoopError`, the chat contains a dangling `tool_use` block with no matching `tool_result`. Anthropic and most providers will reject any subsequent request with that broken history.

**You must call `clear_messages` before reusing the robot:**

```ruby
begin
  robot.run("Execute all steps.")
rescue RobotLab::ToolLoopError => e
  # "Circuit breaker triggered: 11 tool calls exceeded max_tool_rounds (10)"
  puts "Circuit breaker fired: #{e.message}"
end

# Flush the corrupted chat (system prompt is kept)
robot.clear_messages
puts robot.config.max_tool_rounds  # still set — config unchanged

# Robot is healthy again
result = robot.run("Something new.")
```

## Doom Loop Detection

Distinct from the circuit breaker, doom-loop detection is **always on**. Every
`run()` unconditionally installs a `RobotLab::DoomLoopDetector` over the chat's
`execute_tool`, and removes it again when the run ends. `doom_loop_threshold:`
only *tunes* it; it cannot be disabled from the constructor.

```ruby
robot = RobotLab.build(name: "worker", system_prompt: "...", doom_loop_threshold: 5)
```

| | |
|---|---|
| Default threshold | `RobotLab::DoomLoopDetector::DEFAULT_THRESHOLD` (3) |
| Set via | `doom_loop_threshold:` constructor kwarg or `RunConfig#doom_loop_threshold` |

When a consecutive or cyclic repetition of the same tool name exceeds the
threshold, the detector does **not** raise. It appends a self-correction warning
to that tool's result so the model can change strategy: a `String` result gets
`"\n\n⚠️ <warning>"` appended, and a `Hash` result gains a `:_doom_loop_warning`
key. The detector then resets.

## Learning Accumulation

`robot.learn(text)` records a cross-run observation. On each subsequent `run()`,
**all** accumulated learnings are prepended to the user message as a
`LEARNINGS FROM PREVIOUS RUNS:` block. There is no active/inactive distinction —
every entry in `robot.learnings` is injected.

### learn

```ruby
robot.learn(text)
# => self
```

Add a learning to the robot's accumulated observations. Learnings are automatically deduplicated:

- If the new text is a substring of an existing learning, it is dropped (the existing broader learning already covers it).
- If an existing learning is a substring of the new text, the narrower one is replaced.

Learnings are written to the robot's own memory under `memory[:learnings]`.

!!! note "Learnings do not survive process restart on their own"
    `initialize_memory` always constructs a fresh `Memory.new`, and there is no
    `memory:` constructor keyword, so a newly built robot starts with an empty
    `:learnings` key. `learn` reads back whatever is already in `memory[:learnings]`
    at construction, which means persistence requires an external store — for
    example the `robot_lab-durable` extension — to repopulate it.

`learn` runs inside the `:learn` hook family (`before_learn` / `around_learn` /
`after_learn`, plus `on_learn`), so a hook handler can observe or veto the write.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `text` | `String` | The observation or insight to record |

**Returns:** `self`

### learnings

```ruby
robot.learnings
# => Array<String>
```

Returns the list of accumulated learning strings in insertion order.

### How Learnings Are Injected

When learnings are present, each `run(message)` prepends them to the message before sending to the LLM:

```
LEARNINGS FROM PREVIOUS RUNS:
- This codebase prefers map/collect over manual array accumulation
- Explicit nil comparisons appear frequently here

<original user message>
```

**Example:**

```ruby
reviewer = RobotLab.build(
  name: "reviewer",
  system_prompt: "You are a Ruby code reviewer."
)

# Run 1 — no learnings yet
reviewer.run("Review snippet A")
reviewer.learn("Prefer map/collect over manual accumulation")

# Run 2 — learning injected automatically
reviewer.run("Review snippet B")
reviewer.learn("Avoid explicit nil comparisons")

# Run 3 — both learnings injected
reviewer.run("Review snippet C")

puts reviewer.learnings.size  # => 2
```

### Deduplication Example

```ruby
robot.learn("avoid using puts")
robot.learn("avoid using puts and p in production code")
# => broader learning replaces narrower; robot.learnings.size == 1
```

## Runnable Protocol

`Robot` includes `RobotLab::Runnable`, the shared interface it has in common with `Network` — see [Runnable Protocol](../../architecture/core-concepts.md#runnable-protocol) for the full picture. For a single robot:

| Method | Returns |
|--------|---------|
| `crew` | `[self]` — a robot is a crew of one |
| `chief` | `self` |
| `robot_count` | `1` |
| `network?` | `false` |
| `single?` | `true` |

## See Also

- [Building Robots Guide](../../guides/building-robots.md) (includes [Composable Skills](../../guides/building-robots.md#composable-skills))
- [Tool](tool.md)
- [Network](network.md)
