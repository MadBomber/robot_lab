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

An identifier used for routing, logging, and as the key under which a robot's result is stored in a network's `result.context`. If omitted it defaults to the literal string `"robot"` — nothing is auto-generated, so two unnamed robots share the same name.

```ruby
robot = RobotLab.build(name: "support_agent", system_prompt: "...")

RobotLab.build.name  # => "robot"
```

> [!NOTE]
> The default is load-bearing. A robot records whether `name:` was supplied by
> comparing it against `"robot"`; front-matter `robot_name:` is applied **only**
> when the constructor left the name at its default. Passing `name: "robot"`
> explicitly therefore still counts as "not named", and front matter wins.

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

### Provider

For local LLM providers (Ollama, GPUStack, LM Studio, etc.), use the `provider:` parameter. This tells RubyLLM to skip model validation and connect directly:

```ruby
robot = RobotLab.build(
  name: "local_bot",
  model: "llama3.2",
  provider: :ollama,
  system_prompt: "You are a helpful assistant."
)
```

When `provider:` is set, `assume_model_exists: true` is automatically applied. The provider is available via `robot.provider`. This context is preserved across every re-application of the robot's config — including when a template's front matter re-renders mid-run — so a local-provider robot doesn't fall back to RubyLLM's static model registry (and raise a "model not found" error) on later turns.

Some local models route their entire response through reasoning/thinking content instead of the normal response text (e.g. `qwen3` on Ollama). When that happens, `result.reply` falls back to the thinking text automatically — see [Robot with Local Provider](../api/core/robot.md#robot-with-local-provider) for details.

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

| Key | Description | Applied from front matter? |
|-----|-------------|----------------------------|
| `model` | Override the LLM model | Yes |
| `temperature` | Controls randomness (0.0 - 1.0) | Yes |
| `top_p` | Nucleus sampling threshold | **No — silently dropped** |
| `top_k` | Top-k sampling | **No — silently dropped** |
| `max_tokens` | Maximum tokens in response | **No — silently dropped** |
| `presence_penalty` | Penalize based on presence | **No — silently dropped** |
| `frequency_penalty` | Penalize based on frequency | **No — silently dropped** |
| `stop` | Stop sequences | **No — silently dropped** |

> [!WARNING]
> Only `model` and `temperature` take effect from front matter. The other six are
> parsed into the robot's `RunConfig` and then dropped: `RunConfig#apply_to`
> dispatches `chat.with_<field>` guarded by `respond_to?`, and `RubyLLM::Chat`
> only implements `with_model` and `with_temperature`. A template declaring all
> eight leaves the chat's params hash empty — no warning, no error.
>
> The same six **do** work as constructor kwargs or via a `config:` `RunConfig`,
> which route through `with_params`:
>
> ```ruby
> RobotLab.build(name: "w", system_prompt: "...", top_p: 0.5, max_tokens: 1200)
> # chat params => {top_p: 0.5, max_tokens: 1200}
> ```

**Robot Identity and Capabilities:**

| Key | Description |
|-----|-------------|
| `robot_name` | Override the robot's name (when constructor uses the default) |
| `description` | Human-readable description of the robot |
| `tools` | Array of tool class names (resolved via `Object.const_get`) |
| `mcp` | Array of MCP server configurations |
| `skills` | Array of skill template symbols to prepend (see [Composable Skills](#composable-skills)) |

Constructor-provided values always take precedence over frontmatter values.

### Rendering a Template to a String

`RobotLab.render_template` renders a named template directly to a `String` — using the same configured template library (`prompts_dir` / `ROBOT_LAB_TEMPLATE_PATH`) as `template:` on `RobotLab.build` — without constructing a robot. Front-matter parameters are supplied as keyword arguments:

```ruby
RobotLab.render_template(:objective, topic: "commit messages")
# => "<rendered body of prompts/objective.md, with topic substituted>"
```

Unlike `template:` on `build` (which renders a template as a robot's *system prompt*), this returns the plain text — useful as a one-off task message, an evaluation rubric, or any other place you want a parameterized `.md` template's body without the overhead of a robot.

### Self-Contained Templates

Templates can declare everything a robot needs — identity, tools, MCP servers, and LLM config — making the `.md` file a complete robot definition:

```markdown title="prompts/my_github_assistant.md"
---
description: GitHub assistant with MCP tool access
robot_name: github_bot
mcp:
  - name: github
    transport:
      type: stdio
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
robot = RobotLab.build(template: :my_github_assistant)

# MCP still has to be requested at run time — see the warning below
robot.run("What are the open issues?", mcp: :inherit, tools: :inherit)
```

> [!WARNING]
> `transport:` **must be a nested hash**. The shipped
> `examples/prompts/github_assistant.md` uses the flat form
> (`transport: stdio` with sibling `command:`/`args:` keys), which raises
> `NoMethodError: undefined method 'transform_keys' for an instance of String`
> internally. The error is swallowed and logged as a warning, the server lands in
> `robot.failed_mcp_server_names`, and the robot builds with **zero tools**. That
> shipped template also declares no `model:` or `temperature:`, so it does not
> demonstrate the full self-contained pattern shown here.

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

# ...but they are only sent to the model when the run asks for them
robot.run("Where is order 12345?", tools: :inherit)
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
    transport:
      type: stdio
      command: mcp-server-filesystem
      args: ["--root", "/home/user/projects"]
---
You are a developer assistant with filesystem access.
```

```ruby
robot = RobotLab.build(template: :developer)
robot.run("List the files in lib/", mcp: :inherit, tools: :inherit)
```

Constructor `mcp:` overrides frontmatter `mcp:` when provided.

> [!WARNING]
> `transport:` takes a nested hash — `type:` plus the transport's own keys. A flat
> `transport: stdio` with sibling `command:`/`args:` keys fails silently (the
> `transform_keys` NoMethodError is swallowed) and the robot ends up with no MCP
> tools. Valid `type:` values are `stdio`, `sse`, `ws`, `websocket`,
> `streamable-http`, and `http`; the underscored `streamable_http` raises
> `ArgumentError`.

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

## Composable Skills

Skills let you compose robot behaviors from reusable templates without creating a dedicated template for every combination. A skill is just a regular template whose prompt body gets prepended before the main template's body.

### Why Skills?

Consider a support agent that needs to:

- Ask clarifying questions before acting
- Detect customer sentiment
- Respond in structured JSON

Without skills, you'd create a single monolithic template or copy-paste shared instructions across templates. With skills, each behavior is a standalone template that can be mixed into any robot.

### Defining a Skill

A skill is a standard `.md` template file. There is no special syntax — any template can be used as a skill:

```markdown title="prompts/clarifier.md"
---
description: Ask clarifying questions before acting
---
Before answering, consider whether the user's request is ambiguous.
If so, ask one focused clarifying question before proceeding.
```

```markdown title="prompts/json_responder.md"
---
description: Respond in structured JSON
temperature: 0.2
---
Always respond with valid JSON. Use this structure:
{"answer": "...", "confidence": 0.0-1.0, "sources": [...]}
```

### Using Skills via Constructor

Pass `skills:` as a symbol or array of symbols:

```ruby
# Single skill
robot = RobotLab.build(
  name: "bot",
  template: :support,
  skills: :clarifier
)

# Multiple skills
robot = RobotLab.build(
  name: "bot",
  template: :support,
  skills: [:clarifier, :json_responder],
  context: { company: "Acme Corp" }
)
```

The resulting system prompt is composed in order: clarifier body, then json_responder body, then the main support template body.

### Using Skills via Front Matter

Templates can declare skills directly in their front matter:

```markdown title="prompts/smart_support.md"
---
description: Support agent with built-in skills
skills:
  - clarifier
  - json_responder
parameters:
  company: null
---
You are a support agent for <%= company %>.
Help customers with their inquiries.
```

```ruby
# Skills are loaded from front matter automatically
robot = RobotLab.build(
  template: :smart_support,
  context: { company: "Acme Corp" }
)
```

Constructor `skills:` and front matter `skills:` are combined — constructor skills are processed first, then front matter skills.

### Nested Skills

Skills can reference other skills, enabling layered composition:

```markdown title="prompts/safety.md"
---
description: Safety guidelines
skills:
  - content_filter
  - pii_redactor
---
Follow all safety guidelines when responding.
```

Nested skills are expanded depth-first. For the example above, the prompt order would be: content_filter, pii_redactor, safety, then the main template.

### Cycle Detection

If skills form a cycle (A references B, B references A), RobotLab detects it automatically, logs a warning, and skips the duplicate. This prevents infinite loops.

### Config Cascade

Skills can include LLM configuration in their front matter. Config cascades in processing order — later values override earlier ones:

```markdown title="prompts/creative_mode.md"
---
description: Enable creative responses
temperature: 0.9
---
Be creative and imaginative in your responses.
```

```ruby
robot = RobotLab.build(
  name: "writer",
  template: :article_writer,
  skills: [:creative_mode]
)
# temperature is 0.9 from the skill (unless the main template or constructor overrides it)
```

> [!NOTE]
> Skill front matter is subject to the same limitation as template front matter:
> only `model` and `temperature` reach the chat. Adding `top_p: 0.95` to
> `creative_mode.md` would be parsed and then silently discarded. Set it as a
> constructor kwarg (`top_p: 0.95`) instead.

The precedence order (highest wins):

1. Constructor kwargs (`temperature: 0.3`)
2. Main template front matter
3. Later skills override earlier skills
4. First skill in the list

### Skills Without a Main Template

Skills work without a main template — useful for quick composition:

```ruby
robot = RobotLab.build(
  name: "safe_bot",
  skills: [:safety, :json_responder],
  system_prompt: "You answer questions about our product."
)
```

### Shared Context

All skills and the main template render with the same `context:` hash. Define parameters in each skill's front matter and pass values through the shared context:

```markdown title="prompts/branded.md"
---
description: Brand-aware responses
parameters:
  company_name: null
---
You represent <%= company_name %>. Always maintain brand voice.
```

```ruby
robot = RobotLab.build(
  template: :support,
  skills: [:branded],
  context: { company_name: "Acme Corp" }  # shared with all skills
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

result = robot.run("Where is order 12345?", tools: :inherit)
```

> [!WARNING]
> **`run` defaults to `tools: :none` and `mcp: :none`.** Attaching tools at build
> time is not enough — a plain `robot.run("...")` sends the model **zero** tools,
> because an explicit `:none` means "send no tools this turn" rather than "fall
> back to the attached set". Pass `tools: :inherit` on the call to send the
> attached tools, and `mcp: :inherit, tools: :inherit` to connect MCP servers and
> send their tools.
>
> For a **standalone** robot, do not pass `tools: :inherit` at *build* time: the
> parent level is the global config's `:none`, so it resolves to an allowlist of
> `["none"]`, which matches nothing. Leave `tools:` unset in the constructor.
>
> | build `tools:` | run `tools:` | tools sent |
> |---|---|---|
> | unset | `:none` (default) | none |
> | unset | `:inherit` | all attached — **the correct pattern** |
> | `:inherit` | `:inherit` | none — the standalone trap |
> | `:none` | `:inherit` | all attached |
>
> This table is for a robot run on its own. Inside a **network** whose `config:`
> sets `tools:`/`mcp:`, build-time `:inherit` is not a trap — it is exactly how a
> robot opts in to the network-level list, and the parent is that list rather
> than `:none`. See
> [Network-Wide Tool and MCP Defaults](creating-networks.md#network-wide-tool-and-mcp-defaults).
>
> An explicit array (`tools: [OrderLookup]`) is an **allowlist** over the attached
> tools; it selects from them and cannot add new ones. Entries must match how the
> tool was attached — a tool attached as a class matches its class name
> (`[OrderLookup]`), one attached as an instance matches RubyLLM's derived name
> (`%w[order_lookup]`). The two forms do not cross-match.

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

`run` also defaults to `mcp: :none`, so the servers configured above are not connected by a plain `run`:

```ruby
robot.run("Read config/database.yml", mcp: :inherit, tools: :inherit)
```

`robot.connect_mcp!` connects eagerly if you want the handshake to happen up front, but a later plain `run()` still sends no tools — `tools: :inherit` is what puts the MCP tools in the request. Connection failures are logged and recorded in `robot.failed_mcp_server_names`; they are never raised.

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

This is the complete set — the LLM-facing methods are delegated dynamically from `RubyLLM::Chat`, and `with_template` / `with_bus` are RobotLab's own:

| Method | Description |
|--------|-------------|
| `with_model(id)` | Change the LLM model |
| `with_instructions(text)` | Set system instructions |
| `with_temperature(val)` | Set temperature |
| `with_params(**params)` | Set arbitrary provider params (`top_p`, `max_tokens`, …) |
| `with_context(ctx)` | Set the RubyLLM context |
| `with_headers(**headers)` | Set extra request headers |
| `with_tool(tool)` | Add a single tool |
| `with_tools(*tools)` | Add multiple tools |
| `with_schema(schema)` | Set structured output schema |
| `with_thinking(config)` | Enable extended thinking |
| `with_template(id, **ctx)` | Apply a prompt template |
| `with_bus(bus)` | Connect to a message bus (creates one if nil) |

> [!WARNING]
> `with_top_p`, `with_top_k`, `with_max_tokens`, `with_presence_penalty`,
> `with_frequency_penalty`, and `with_stop` **do not exist** — calling any of them
> raises `NoMethodError`. `RubyLLM::Chat` exposes those knobs through
> `with_params`, so use either the constructor kwarg or `with_params`:
>
> ```ruby
> robot.with_params(max_tokens: 2000, top_p: 0.3).run("...")
> # or
> RobotLab.build(name: "bot", system_prompt: "...", max_tokens: 2000, top_p: 0.3)
> ```

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
result.reply              # => alias for last_text_content
result.output             # => [TextMessage] built from the final response text
result.tool_calls         # => Array of tool call results (see note)
result.robot_name         # => "assistant"
result.stop_reason        # => always nil (see note)
result.input_tokens       # => Integer
result.output_tokens      # => Integer
result.duration           # => Float (elapsed seconds, set in pipeline execution)
result.raw                # => raw LLM response object
```

> [!NOTE]
> `result.tool_calls` is effectively always empty. It is read from the *final*
> assistant message, and by the time ruby_llm's tool loop has finished that
> message carries no tool calls. Use `:tool_call` [hooks](hooks.md) or the
> `on_tool_call:` / `on_tool_result:` callbacks to observe tool activity.
> Similarly, `result.output` holds only the final response text, not the full
> turn. There is no `result.content` and no `result.text?`.

> [!WARNING]
> `result.stop_reason` is **always `nil`**. `RubyLLM::Message` does not define
> `stop_reason`, and `build_result` fills the field with
> `response.respond_to?(:stop_reason) ? response.stop_reason : nil` — so no
> provider value ever lands there, and `.compact` drops the key from
> `result.export` entirely. Do not branch on `"end_turn"`, `"tool_use"`, or
> `"stop"`. Consequently `result.stopped?` is simply "this result has no tool
> calls".
>
> (`RobotLab::Message::VALID_STOP_REASONS` is `["tool", "stop"]`, but that
> constant governs the `Message` classes you build yourself, not `RobotResult`.)

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

Stream LLM content in real-time using a stored callback, a per-call block, or both. Each receives a [`RubyLLM::Chunk`](https://rubyllm.com/streaming/#basic-streaming) object — use `chunk.content` for the text delta. Chunks also carry `model_id`, `tool_calls`, `thinking`, and token usage on the final chunk. See the [Streaming API reference](../api/core/robot.md#streaming) for the full chunk interface.

**Stored callback** — wired at build time, fires on every `run()`:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are helpful.",
  on_content: ->(chunk) { print chunk.content }
)
robot.run("Tell me a story")  # streams automatically
```

**Per-call block** — passed to `run()`:

```ruby
robot.run("Tell me a story") { |chunk| print chunk.content }
```

**Both together** — stored fires first, then the block:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are helpful.",
  on_content: ->(chunk) { log_chunk(chunk.content) }
)
robot.run("Tell me a story") { |chunk| stream_to_client(chunk.content) }
```

`on_content` is also a `RunConfig` field, so it can be supplied through a `config:` on the robot itself rather than as a constructor kwarg:

```ruby
config = RobotLab::RunConfig.new(
  on_content: ->(chunk) { broadcast(chunk.content) }
)
robot = RobotLab.build(name: "bot", system_prompt: "...", config: config)
```

> [!WARNING]
> This only works for the robot's **own** config. A network-level `config:` does
> **not** supply `on_content` (or any other callback or LLM field) to its member
> robots — a network propagates only `mcp` and `tools`. Each robot reads
> `on_content` from its own config at construction time, so streaming callbacks
> must be set per robot.

You can also monitor tool activity via callbacks:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "...",
  on_tool_call: ->(tool_call) { puts "Calling: #{tool_call.name}" },
  on_tool_result: ->(result) { puts "Result: #{result}" }
)
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

billing_specialist.run("Refund order 12345", tools: :inherit)
```

In a network, the equivalent opt-in is on the task: `task :billing, billing_specialist, tools: :inherit, depends_on: :optional`.

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

### Auto-Responding to Bus Tasks

The `Comedian`/`ComedyCritic` example above hand-wires `on_message` to run and reply. For the common case — run every inbound task through the robot and reply with the result — `respond_to_tasks`/`serve` do it in one call:

```ruby
bob = RobotLab.build(name: "bob", template: :comedian, bus: bus)
bob.serve  # every inbound task runs through bob.run and replies automatically

alice.send_message(to: :bob, content: "Tell me a funny robot joke.")
```

`serve` is shorthand for `respond_to_tasks(auto_reply: true) { |message| run(bus_task_content(message)).reply }`.

`bus_task_content` flattens the message payload for `run`: a `String` content is passed through via `to_s`, while a `Hash` content becomes one `"key: value"` line per entry. So a task sent as `{ topic: "robots", style: "dry" }` reaches the LLM as:

```
topic: robots
style: dry
```

Use `respond_to_tasks` directly when the reply shouldn't just be `run(...).reply` — e.g. to build the prompt yourself, or to post-process the result:

```ruby
bob.respond_to_tasks do |message|
  joke = run(message.content.to_s).reply.strip
  joke.end_with?("!") ? joke : "#{joke}!"
end
```

Both ignore messages that are themselves replies (`message.reply?`), so two robots calling `serve`/`respond_to_tasks` on each other don't loop.

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
- The child inherits the parent's `model`/`provider` (caller-supplied `model:`/`provider:` still override) — a dispatcher running on a local Ollama model spawns specialists that also target that model, instead of falling back to the global default model/provider

Robots can also join a bus after creation:

```ruby
bot = RobotLab.build(name: "latecomer", system_prompt: "Hello.")
bot.with_bus(existing_bus)  # now connected and can send/receive messages
```

## Context Window Compression

Long-running robots accumulate conversation history that can grow to fill the context window. `compress_history` prunes old turns using stemmed term-frequency cosine similarity (term frequencies only — no IDF weighting) against the most recent context, keeping turns that are still relevant and discarding or summarizing those that aren't.

```ruby
# Default settings: protect 3 most-recent turn pairs, drop anything below 0.2
robot.compress_history

# Tune all thresholds
robot.compress_history(
  recent_turns:   5,    # number of recent user+assistant pairs to always keep
  keep_threshold: 0.6,  # turns with score >= this are kept verbatim (default 0.6)
  drop_threshold: 0.2   # turns with score < this are dropped (default 0.2)
)
```

Medium-relevance turns (between thresholds) are dropped by default. Pass a `summarizer:` callable to replace them with a one-sentence summary instead:

```ruby
summarizer = RobotLab.build(name: "summarizer", system_prompt: "Summarize concisely in one sentence.")

robot.compress_history(
  summarizer: ->(text) { summarizer.run("Summarize: #{text}").reply }
)
```

**What is always preserved regardless of score:**
- System messages
- Tool call/result message pairs (dropping half would corrupt the conversation)
- The most recent `recent_turns` user+assistant pairs

Requires the `classifier` gem (`~> 2.3`):

```ruby
gem "classifier", "~> 2.3"
```

## Convergence Detection

`RobotLab::Convergence` uses stemmed term-frequency cosine similarity (not TF-IDF — on a two-document corpus, IDF suppresses exactly the shared terms that signal agreement) to detect when two independent agents have reached the same conclusion. The primary use case is skipping an expensive reconciler robot when two verifiers already agree. Texts shorter than 30 characters always score `0.0`.

```ruby
# Check the similarity score directly (returns Float 0.0..1.0)
score = RobotLab::Convergence.similarity(result_a.reply, result_b.reply)

# Boolean convergence check (default threshold: 0.85)
RobotLab::Convergence.detected?(result_a.reply, result_b.reply)

# Custom threshold
RobotLab::Convergence.detected?(text_a, text_b, threshold: 0.75)
```

Wire it into a network for the reconciler fast-path. There is no router object in RobotLab — the reconciler is declared `depends_on: :optional` and a gate robot activates it only when the verifiers disagree:

```ruby
verifier_a = RobotLab.build(name: "verifier_a", system_prompt: "Verify the answer.")
verifier_b = RobotLab.build(name: "verifier_b", system_prompt: "Independently verify the answer.")
reconciler = RobotLab.build(name: "reconciler", system_prompt: "Reconcile conflicting answers.")

class ConvergenceGate < RobotLab::Robot
  def call(result)
    a = result.context[:verifier_a]&.reply.to_s   # keyed by ROBOT name
    b = result.context[:verifier_b]&.reply.to_s

    return result if RobotLab::Convergence.detected?(a, b)  # agree — skip reconciler

    result.activate(:reconciler)
  end
end

network = RobotLab.create_network(name: "verify") do
  task :verifier_a, verifier_a, depends_on: :none
  task :verifier_b, verifier_b, depends_on: :none
  task :gate,       ConvergenceGate.new(name: "gate"), depends_on: %i[verifier_a verifier_b]
  task :reconciler, reconciler, depends_on: :optional
end

network.run(message: "Is the deployment healthy?").activated_steps
# => [] when they agreed, [:reconciler] when they diverged
```

> [!WARNING]
> `RobotLab.create_network` accepts only `name:`, `concurrency:`, `config:`, and a
> block. There are no `router:` or `robots:` keyword arguments — passing them
> raises `ArgumentError: unknown keywords: :robots, :router` — and no `Router` or
> `Router::Args` class exists anywhere in the library.

Requires the `classifier` gem (`~> 2.3`).

## Structured Delegation

A robot can delegate a task to another robot using `delegate(to:, task:)`. The result is a `RobotResult` annotated with `delegated_by`, `duration`, and token counts.

### Synchronous Delegation

The default: blocks the calling robot until the delegatee finishes.

```ruby
analyst = RobotLab.build(name: "analyst", system_prompt: "Analyze data.")
manager = RobotLab.build(name: "manager", system_prompt: "Coordinate work.")

result = manager.delegate(to: analyst, task: "Summarize the Q3 report.")
puts result.reply
puts "Completed in %.2fs using %d tokens" % [result.duration, result.output_tokens]
puts result.delegated_by  # => "manager"
```

### Asynchronous Delegation (Fan-out)

Pass `async: true` to get a `DelegationFuture` back immediately. Call `.value` to block for the result when you need it.

```ruby
writer  = RobotLab.build(name: "writer",  system_prompt: "Write clearly.")
analyst = RobotLab.build(name: "analyst", system_prompt: "Analyze data.")
manager = RobotLab.build(name: "manager", system_prompt: "Coordinate.")

# Fan out — both start immediately
f1 = manager.delegate(to: analyst, task: "Analyze Q3 numbers", async: true)
f2 = manager.delegate(to: writer,  task: "Draft the intro paragraph", async: true)

# ... do other work here ...

# Collect results (blocks if not yet done)
analysis = f1.value
draft    = f2.value

# With a timeout (raises DelegationFuture::DelegationTimeout)
result = f1.value(timeout: 30)
```

`DelegationFuture` API:

| Method | Description |
|--------|-------------|
| `resolved?` | Non-blocking poll — true if completed or errored |
| `value(timeout: nil)` | Block until done; re-raises any error from the delegatee |
| `wait` | Alias for `value` |
| `robot_name` | Name of the robot that was delegated to |
| `delegated_by` | Name of the robot that created this future |

## Configuration

RobotLab uses `MywayConfig` for configuration. Read values off the config object directly:

```ruby
RobotLab.config.ruby_llm.model            # => "claude-sonnet-4"
RobotLab.config.ruby_llm.request_timeout  # => 120
```

`RobotLab.configure` also exists, and yields the config object for imperative setup:

```ruby
RobotLab.configure do |config|
  config.logger = Logger.new($stdout)
end
```

Configuration is layered, lowest precedence first:

1. Bundled defaults (`lib/robot_lab/config/defaults.yml`)
2. Environment-specific overrides (development, test, production)
3. XDG user config (`~/.config/robot_lab/robot_lab.yml`)
4. Project config (`./config/robot_lab.yml`)
5. Environment variables (`ROBOT_LAB_*` prefix; `__` for nesting)
6. Constructor parameters

> [!WARNING]
> The XDG file is `~/.config/robot_lab/**robot_lab.yml**` — the filename repeats
> the app name. `~/.config/robot_lab/config.yml` is never read.
>
> A top-level `defaults:` wrapper is **always** ignored — that key means
> something only inside the gem's own bundled `defaults.yml`. Write
> `max_tool_rounds: 12`, not `defaults:\n  max_tool_rounds: 12`.
>
> An **environment-named** wrapper is a different story, and the two config
> files behave differently:
>
> | File | flat keys | `development:` / `test:` / `production:` wrapper |
> |---|---|---|
> | `~/.config/robot_lab/robot_lab.yml` | honored | **honored** for the current environment |
> | `./config/robot_lab.yml` (no Rails) | honored | ignored |
> | `./config/robot_lab.yml` (in Rails) | ignored | **required** — keys must be nested under `Rails.env` |
>
> The XDG loader checks for a section named for the current environment and only
> falls back to the file root when there is none. Outside Rails the environment
> defaults to `development` (or `RAILS_ENV` / `RACK_ENV` when set), so a
> `development:` section in the XDG file takes effect while `test:` and
> `production:` sections sit dormant. Verified with a `max_iterations: 777`
> XDG file: flat → 777, `development:` → 777, `production:` → 10 (until
> `RACK_ENV=production`, then 777), `defaults:` → 10.
>
> Inside Rails, `anyway_config` sets the current environment to `Rails.env`,
> which makes the **project** file environmental too — a flat
> `./config/robot_lab.yml` is then ignored.
>
> ERB is evaluated only in `./config/robot_lab.yml`. The XDG loader uses
> `YAML.safe_load` with no ERB pass, so `<%= ENV['KEY'] %>` there stays a literal
> string. Nested env vars also arrive as strings
> (`ROBOT_LAB_RUBY_LLM__REQUEST_TIMEOUT=180` yields `"180"`); top-level keys are
> type-coerced.

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

### 2. Compose Behaviors with Skills

Instead of creating monolithic templates, break behaviors into composable skills:

```ruby
robot = RobotLab.build(
  name: "support",
  template: :support,
  skills: [:clarifier, :safety, :json_responder]
)
```

### 3. Use Templates for Reusable Prompts

Templates keep prompts in version-controlled files and allow parameterization:

```ruby
robot = RobotLab.build(
  name: "support",
  template: :support,
  context: { company: "TechCo", language: "English" }
)
```

### 4. Handle Tool Errors Gracefully

`RobotLab::Tool` automatically catches exceptions and returns plain-text errors to the LLM. For domain-specific error handling, catch known exceptions in `execute` and return structured data. See [Using Tools: Error Handling](using-tools.md#error-handling) for details.

## Next Steps

- [Creating Networks](creating-networks.md) - Orchestrate multiple robots
- [Message Bus](../architecture/core-concepts.md#message-bus) - Bidirectional robot communication
- [Dynamic Spawning](../architecture/core-concepts.md#dynamic-spawning) - Robots creating robots at runtime
- [Using Tools](using-tools.md) - Advanced tool patterns
- [Memory Guide](memory.md) - Share data between runs and robots
- [API Reference: Robot](../api/core/robot.md) - Complete API documentation
