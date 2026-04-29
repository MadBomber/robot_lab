# RobotLab

> [!INFO]
> See the [CHANGELOG](CHANGELOG.md) for the latest changes.  The [examples directory has a good cross section  of demo apps](examples/README.md) that show-off the various capabilities of the RobotLab library.

<br>
<table>
<tr>
<td width="50%" align="center" valign="top">
<img src="docs/assets/images/robot_lab.jpg" alt="RobotLab"><br>
<em>"Build robots. Solve problems."</em>
</td>
<td width="50%" valign="top">
<strong>Key Features</strong><br>

- <strong>Multi-Robot Architecture</strong> - Build with specialized AI agents<br>
- <strong>Network Orchestration</strong> - Connect robots with flexible routing<br>
- <strong>Prompt Templates</strong> - Self-contained .md files with YAML front matter<br>
- <strong>Composable Skills</strong> - Mix reusable prompt behaviors into any robot<br>
- <strong>Extensible Tools</strong> - Custom capabilities with graceful error handling<br>
- <strong>Human-in-the-Loop</strong> - AskUser tool for interactive prompting<br>
- <strong>Content Streaming</strong> - Stored callbacks, per-call blocks, or both<br>
- <strong>MCP Integration</strong> - Connect to external tool servers with timeouts and retry<br>
- <strong>Local LLM Providers</strong> - Ollama, GPUStack, LM Studio via provider passthrough<br>
- <strong>Shared Memory</strong> - Reactive key-value store with subscriptions<br>
- <strong>Message Bus</strong> - Bidirectional robot communication via TypedBus<br>
- <strong>Dynamic Spawning</strong> - Robots create new robots at runtime<br>
- <strong>Layered Configuration</strong> - Cascading YAML, env vars, and RunConfig<br>
- <strong>Rails Integration</strong> - Generators, background jobs, Turbo Stream broadcasting<br>
- <strong>Token &amp; Cost Tracking</strong> - Per-run and cumulative token counts on every robot<br>
- <strong>Tool Loop Circuit Breaker</strong> - <code>max_tool_rounds:</code> guards against runaway tool call loops<br>
- <strong>Learning Accumulation</strong> - <code>robot.learn()</code> builds up cross-run observations with deduplication<br>
- <strong>Context Window Compression</strong> - <code>robot.compress_history()</code> prunes irrelevant old turns via TF cosine scoring<br>
- <strong>Convergence Detection</strong> - <code>RobotLab::Convergence</code> detects when independent agents agree, enabling reconciler fast-path<br>
- <strong>Structured Delegation</strong> - <code>robot.delegate(to:, task:)</code> sync or async inter-robot calls with duration and token metadata; async fan-out via <code>DelegationFuture</code>
</td>
</tr>
</table>

<p>RobotLab enables sophisticated AI applications using multiple specialized robots (LLM agents) that work together to accomplish complex tasks. Each robot has its own instructions, skills, tools, and capabilities.  Review the [full documentation website](https://madbomber.github.io/robot_lab) snd explore the [many examples](examples/README.md) available as working demo applications.</p>

## Installation

```bash
bundle add robot_lab
```

Or install it directly:

```bash
gem install robot_lab
```

### Requirements

- Ruby >= 3.2
- [One or more API Keys for LLM providers supported by RubyLLM](https://rubyllm.com/configuration/#provider-configuration)

For comprehensive guides and API documentation, visit **[https://madbomber.github.io/robot_lab](https://madbomber.github.io/robot_lab)**

## Getting Started

The simplest way to create a robot is with an inline `system_prompt`. This approach is ideal for development, testing, and quick prototyping:

```ruby
require "robot_lab"

# Create a robot with an inline system prompt
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful assistant. Be concise and friendly."
)

# Run the robot
result = robot.run("What is the capital of France?")

puts result.last_text_content
# => "The capital of France is Paris."
```

### Local LLM Providers

For local LLM providers (Ollama, GPUStack, LM Studio, etc.), use the `provider:` parameter:

```ruby
robot = RobotLab.build(
  name: "local_bot",
  model: "llama3.2",
  provider: :ollama,
  system_prompt: "You are a helpful assistant."
)
```

### Configuration

RobotLab uses [MywayConfig](https://github.com/MadBomber/myway_config) for layered configuration. There is no `configure` block. Configuration is loaded automatically from multiple sources in priority order:

1. Bundled defaults (`lib/robot_lab/config/defaults.yml`)
2. Environment-specific overrides (development, test, production)
3. XDG user config (`~/.config/robot_lab/config.yml`)
4. Project config (`./config/robot_lab.yml`)
5. Environment variables (`ROBOT_LAB_*` prefix)

```bash
# Set API keys via environment variables (double underscore for nesting)
export ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...
export ROBOT_LAB_RUBY_LLM__OPENAI_API_KEY=sk-...
export ROBOT_LAB_RUBY_LLM__MODEL=claude-sonnet-4
```

```ruby
# Access configuration values
RobotLab.config.ruby_llm.model            #=> "claude-sonnet-4"
RobotLab.config.ruby_llm.request_timeout  #=> 120
RobotLab.config.streaming_enabled         #=> true
```

Or create a project config file at `./config/robot_lab.yml`:

```yaml
ruby_llm:
  model: claude-sonnet-4
  anthropic_api_key: sk-ant-...
  request_timeout: 180
```

### Using Templates

For production applications, RobotLab supports a template system built on [PromptManager](https://github.com/MadBomber/prompt_manager). Templates allow you to:

- **Compose prompts** from reusable Markdown files
- **Inject dynamic context** at build-time
- **Version control** your prompts alongside your code
- **Share prompts** across multiple robots

Each template is a `.md` file with YAML front matter for metadata and parameters:

```
prompts/
  assistant.md
  classifier.md
  billing.md
```

Create a template at `prompts/assistant.md`:

```markdown
---
description: A helpful assistant
parameters:
  company_name: null
  tone: friendly
---
You are a helpful assistant for <%= company_name %>.

Your communication style should be <%= tone %>.

Your responsibilities:
- Answer questions accurately and concisely
- Be friendly and professional
- Admit when you don't know something
```

Reference the template by symbol:

```ruby
robot = RobotLab.build(
  name: "assistant",
  template: :assistant,
  context: { company_name: "Acme Corp", tone: "professional" }
)
```

### Self-Contained Templates

Templates can declare tools, MCP servers, name, and description in front matter, making the `.md` file a complete robot definition:

```markdown
---
description: GitHub assistant with MCP tool access
robot_name: github_bot
tools:
  - CodeSearchTool
mcp:
  - name: github
    transport: stdio
    command: npx
    args: ["-y", "@modelcontextprotocol/server-github"]
model: claude-sonnet-4
---
You are a GitHub assistant. Use available tools to help with repository tasks.
```

```ruby
# Template provides everything — minimal constructor call
robot = RobotLab.build(template: :github_assistant)
```

Front matter supports: `description`, `robot_name`, `tools`, `mcp`, `skills`, `parameters`, and LLM config keys (`model`, `temperature`, `top_p`, `top_k`, `max_tokens`, `presence_penalty`, `frequency_penalty`, `stop`). Constructor-provided values always take precedence over front matter.

### Composable Skills

Skills let you compose robot behaviors from reusable templates. A skill is just a template whose prompt body is prepended before the main template. Use skills to mix in capabilities like "ask clarifying questions", "respond in JSON", or "follow safety guidelines" without creating a dedicated template for every combination.

```ruby
# Compose a support robot from reusable skills
robot = RobotLab.build(
  name: "support",
  template: :support_agent,
  skills: [:clarifier, :sentiment_aware, :json_responder],
  context: { company: "Acme Corp" }
)
```

Skills can also be declared in template front matter:

```markdown
---
description: Support agent with built-in skills
skills:
  - clarifier
  - sentiment_aware
---
You are a support agent for <%= company %>.
```

Skills are expanded depth-first and can reference other skills (with automatic cycle detection). Config cascades through skills in order — later values override earlier ones, and constructor kwargs always win.

### Combining Templates with System Prompts

The `system_prompt` parameter can also be used alongside a template. When both are provided, the template renders first and the `system_prompt` is appended. This is particularly useful during development and testing when you want to add temporary instructions or context to an existing template:

```ruby
robot = RobotLab.build(
  name: "assistant",
  template: :assistant,
  context: { company_name: "Acme Corp", tone: "friendly" },
  system_prompt: "DEBUG MODE: Log all tool calls. Today's date is #{Date.today}."
)
```

### Shared Configuration with RunConfig

`RunConfig` lets you define operational defaults that flow through the hierarchy: Network -> Robot -> Template -> Task -> Runtime. Use it to share LLM settings across multiple robots or an entire network.

```ruby
# Create a shared config
shared = RobotLab::RunConfig.new(
  model: "claude-sonnet-4",
  temperature: 0.7,
  max_tokens: 2000
)

# Apply to individual robots
robot = RobotLab.build(
  name: "writer",
  system_prompt: "You are a creative writer.",
  config: shared
)

# Apply to an entire network (all robots inherit these defaults)
network = RobotLab.create_network(name: "pipeline", config: shared) do
  task :analyzer, analyzer_robot, depends_on: :none
  task :writer, writer_robot, depends_on: [:analyzer]
end

# Robot-specific kwargs always override the shared config
robot = RobotLab.build(
  name: "fast_bot",
  system_prompt: "Be brief.",
  config: shared,
  temperature: 0.3  # overrides shared config's 0.7
)
```

RunConfig supports keyword construction, block DSL, and merge semantics:

```ruby
# Block DSL
config = RobotLab::RunConfig.new do |c|
  c.model "claude-sonnet-4"
  c.temperature 0.7
end

# Merge (more-specific wins)
network_config = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.5)
robot_config   = RobotLab::RunConfig.new(temperature: 0.9)
effective      = network_config.merge(robot_config)
effective.temperature  #=> 0.9
effective.model        #=> "claude-sonnet-4"
```

### Chaining Configuration

Robots support method chaining to adjust configuration after creation:

```ruby
robot = RobotLab.build(name: "writer", system_prompt: "You are a creative writer.")

result = robot
  .with_temperature(0.9)
  .with_model("claude-sonnet-4")
  .with_max_tokens(2000)
  .run("Write a haiku about Ruby programming")
```

## Graceful Tool Error Handling

`RobotLab::Tool` automatically catches exceptions in `execute` and returns a plain-text error to the LLM instead of crashing the run. The LLM can then reason about the error and try an alternative approach.

```ruby
tool = RobotLab::Tool.create(name: "fetch_data") do |args|
  raise IOError, "connection refused"
end

result = tool.call({})
# => "Error (fetch_data): connection refused"
```

This applies to all tools — subclasses, factory tools, and MCP tools. For critical tools where you want exceptions to propagate, opt out per class:

```ruby
class CriticalTool < RobotLab::Tool
  self.raise_on_error = true
  # ...
end
```

## Creating a Robot with Tools

```ruby
# Define tools using RubyLLM::Tool
class Magic8Ball < RubyLLM::Tool
  description "Consult the mystical Magic 8-Ball for guidance on yes/no questions"

  param :question, type: "string", desc: "A yes/no question to ask the oracle"

  RESPONSES = [
    { answer: "It is certain", certainty: 0.95, vibe: "positive" },
    { answer: "Ask again later", certainty: 0.10, vibe: "evasive" },
    { answer: "Don't count on it", certainty: 0.85, vibe: "negative" },
    { answer: "Signs point to yes", certainty: 0.75, vibe: "positive" },
    { answer: "Reply hazy, try again", certainty: 0.05, vibe: "evasive" },
    { answer: "My sources say no", certainty: 0.80, vibe: "negative" },
    { answer: "Outlook good", certainty: 0.70, vibe: "positive" },
    { answer: "Cannot predict now", certainty: 0.00, vibe: "evasive" }
  ].freeze

  def execute(question:)
    response = RESPONSES.sample
    { question: question, **response }
  end
end

# Create robot with tools via local_tools: parameter
robot = RobotLab.build(
  name: "oracle",
  system_prompt: "You are a mystical oracle. Use the Magic 8-Ball to answer questions about the future.",
  local_tools: [Magic8Ball]
)

result = robot.run("Should I start learning Rust?")
```

## Orchestrating Multiple Robots

Networks use [SimpleFlow](https://github.com/MadBomber/simple_flow) pipelines with optional task activation for intelligent routing:

```ruby
# Custom classifier that activates the appropriate specialist
class ClassifierRobot < RobotLab::Robot
  def call(result)
    context = extract_run_context(result)
    message = context.delete(:message)

    robot_result = run(message, **context)

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    # Route based on classification
    category = robot_result.last_text_content.to_s.strip.downcase
    case category
    when /billing/ then new_result.activate(:billing)
    when /technical/ then new_result.activate(:technical)
    else new_result.activate(:general)
    end
  end
end

# Create specialized robots
classifier = ClassifierRobot.new(
  name: "classifier",
  template: :classifier
)

billing_robot = RobotLab.build(name: "billing", template: :billing)
technical_robot = RobotLab.build(name: "technical", template: :technical)
general_robot = RobotLab.build(name: "general", template: :general)

# Create network with optional task routing
network = RobotLab.create_network(name: "support") do
  task :classifier, classifier, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
  task :technical, technical_robot, depends_on: :optional
  task :general, general_robot, depends_on: :optional
end

# Run the network
result = network.run(message: "I was charged twice for my subscription")
puts result.value.last_text_content
```

## Memory

Both robots and networks have inherent memory that persists across runs:

```ruby
# Standalone robot with inherent memory
robot = RobotLab.build(name: "assistant", system_prompt: "You are helpful.")

robot.run("My name is Alice")
robot.run("What's my name?")  # Memory persists automatically

# Access robot's memory
robot.memory[:user_id] = 123
robot.memory.data[:category] = "billing"

# Runtime memory injection
robot.run("Help me", memory: { session_id: "abc123", tier: "premium" })

# Reset memory when needed
robot.reset_memory
```

Networks pass context through SimpleFlow::Result:

```ruby
# Create network with specialized robots
network = RobotLab.create_network(name: "support") do
  task :classifier, classifier, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
end

# Run with context - available to all robots
result = network.run(
  message: "I have a billing question",
  customer_id: 456,
  ticket_id: "TKT-123"
)

# Access results from specific robots
classifier_result = result.context[:classifier]
billing_result = result.context[:billing]

# The final value is the last robot's output
puts result.value.last_text_content
```

## MCP Integration

Connect to external tool servers via Model Context Protocol:

```ruby
# Configure MCP server (with optional timeout)
filesystem_server = {
  name: "filesystem",
  transport: {
    type: "stdio",
    command: "mcp-server-filesystem",
    args: ["/path/to/allowed/directory"]
  },
  timeout: 30  # seconds (default: 15)
}

# Create robot with MCP server - tools are auto-discovered
robot = RobotLab.build(
  name: "developer",
  template: :developer,
  mcp: [filesystem_server]
)

# Optionally connect eagerly (default is lazy on first run)
robot.connect_mcp!

# Check connection status
puts "Failed: #{robot.failed_mcp_server_names}" if robot.failed_mcp_server_names.any?

# Robot can now use filesystem tools
result = robot.run("List the files in the current directory")
```

MCP connections are resilient: failed servers are automatically retried on subsequent `run()` calls, and one failing server does not prevent others from connecting.

## Message Bus

Robots can communicate bidirectionally via an optional message bus, independent of the Network pipeline. This enables negotiation loops, convergence patterns, and cyclic workflows.

Connect robots to a bus at construction time with `bus:`, or after creation with `with_bus`:

```ruby
require "robot_lab"

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
      verdict = run("Evaluate this joke:\n\n#{message.content}").last_text_content.strip
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

Key features:

- **Typed channels** — only `RobotMessage` objects are accepted (type enforcement via `typed_bus`)
- **Auto-ACK** — `on_message { |message| }` auto-acknowledges; use `|delivery, message|` for manual ACK/NACK
- **Reply correlation** — `send_reply(to:, content:, in_reply_to:)` tracks conversation threads
- **Outbox tracking** — sent messages tracked in `robot.outbox` with status and replies
- **Independent of Network** — bus communication works without a Network pipeline

## Dynamic Robot Spawning

Robots can create new robots at runtime using `spawn`. The bus is created lazily — no upfront wiring required:

```ruby
require "robot_lab"

class Dispatcher < RobotLab::Robot
  attr_reader :spawned

  def initialize(bus: nil)
    super(name: "dispatcher", system_prompt: "Decide which specialist to create.", bus: bus)
    @spawned = {}

    on_message do |message|
      puts "Got reply from #{message.from}: #{message.content.to_s.lines.first&.strip}"
    end
  end

  def dispatch(question)
    # Spawn a specialist (reuse if already spawned)
    specialist = @spawned["helper"] ||= spawn(
      name: "helper",
      system_prompt: "You answer questions concisely."
    )

    # Have the specialist work and reply
    answer = specialist.run(question).last_text_content.strip
    specialist.send_message(to: :dispatcher, content: answer)
  end
end

dispatcher = Dispatcher.new
dispatcher.dispatch("What is the capital of France?")
```

Key features:

- **`spawn`** — creates a child robot on the same bus; creates a bus lazily if none exists
- **`with_bus`** — connect a robot to a bus after creation (`bot.with_bus(existing_bus)`)
- **Fan-out** — multiple robots with the same name all receive messages sent to that name
- **No setup required** — bus and channels are created automatically on first use

## Streaming

Stream LLM content in real-time using a stored callback, a per-call block, or both. Each receives a [`RubyLLM::Chunk`](https://rubyllm.com/streaming/#basic-streaming) — use `chunk.content` for the text delta. Chunks also carry `model_id`, `tool_calls`, `thinking`, and token usage on the final chunk.

### Stored Callback (`on_content:`)

Wire streaming at build time. The callback fires on every `run()` call automatically:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are helpful.",
  on_content: ->(chunk) { print chunk.content }
)

robot.run("Tell me a story")  # streams automatically
```

### Per-Call Block

Pass a block to `run()` for one-off streaming:

```ruby
robot = RobotLab.build(name: "assistant", system_prompt: "You are helpful.")

robot.run("Tell me a story") { |chunk| print chunk.content }
```

### Both Together

When both a stored callback and a runtime block are provided, both fire (stored first):

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are helpful.",
  on_content: ->(chunk) { log_chunk(chunk.content) }
)

robot.run("Tell me a story") { |chunk| stream_to_client(chunk.content) }
```

The `on_content:` callback participates in the RunConfig cascade, so it can be set at the network or config level and inherited by robots.

## Token & Cost Tracking

Every `robot.run()` returns a `RobotResult` that carries token usage for that call. The robot itself accumulates running totals across all runs.

```ruby
robot = RobotLab.build(name: "analyst", system_prompt: "You are helpful.")

result = robot.run("What is a stack?")
puts result.input_tokens   # tokens sent to the LLM this run
puts result.output_tokens  # tokens generated this run

puts robot.total_input_tokens   # cumulative across all runs
puts robot.total_output_tokens
```

To start a fresh cost batch without rebuilding the robot, call `reset_token_totals`. This resets the **accounting counter only** — the chat history keeps accumulating, so subsequent `input_tokens` will reflect the full context window sent to the API:

```ruby
robot.reset_token_totals
puts robot.total_input_tokens  # => 0
```

Token counts are zero for providers that do not return usage data.

## Tool Loop Circuit Breaker

Set `max_tool_rounds:` to prevent a robot from looping indefinitely through tool calls. When the limit is exceeded, `RobotLab::ToolLoopError` is raised.

```ruby
robot = RobotLab.build(
  name: "runner",
  system_prompt: "Execute every step.",
  local_tools: [StepTool],
  max_tool_rounds: 10
)

begin
  robot.run("Run all steps.")
rescue RobotLab::ToolLoopError => e
  puts e.message  # "Tool call limit of 10 exceeded"
end
```

After a `ToolLoopError` the chat contains a dangling `tool_use` block with no matching `tool_result`. Most providers (including Anthropic) will reject any subsequent request with that history. Call `clear_messages` before reusing the robot:

```ruby
robot.clear_messages   # flushes broken history; system prompt is kept
result = robot.run("Something new.")  # robot is healthy again
```

## Learning Accumulation

`robot.learn(text)` records a cross-run observation. On each subsequent `run()`, active learnings are automatically prepended to the user message as a `LEARNINGS FROM PREVIOUS RUNS:` block so the LLM can incorporate prior context without needing a persistent chat:

```ruby
reviewer = RobotLab.build(
  name: "reviewer",
  system_prompt: "You are a Ruby code reviewer."
)

reviewer.run("Review snippet A")
reviewer.learn("This codebase prefers map/collect over manual array accumulation")

reviewer.run("Review snippet B")  # learning is injected automatically
```

Learnings deduplicate bidirectionally: if a broader learning is added that contains an existing narrower one, the narrower one is dropped. Learnings are persisted to the robot's `Memory` and survive a robot rebuild when the same `Memory` object is reused.

```ruby
reviewer.learnings          # => ["This codebase prefers map/collect..."]
reviewer.learn("new fact")  # deduplicates before storing
```

## Context Window Compression

`robot.compress_history` prunes old conversation turns using TF-IDF cosine similarity, keeping only turns that are relevant to the most recent context. System messages and tool call/result pairs are always preserved.

```ruby
# Basic compression: protect the 3 most recent turns, drop unrelated old turns
robot.compress_history

# Tune the thresholds
robot.compress_history(
  recent_turns:   5,    # protect this many recent user+assistant pairs
  keep_threshold: 0.6,  # turns scoring >= this are kept verbatim
  drop_threshold: 0.2   # turns scoring < this are dropped
)

# Summarize medium-relevance turns instead of dropping them
summarizer_bot = RobotLab.build(name: "summarizer", system_prompt: "Summarize concisely.")
robot.compress_history(
  summarizer: ->(text) { summarizer_bot.run("One sentence: #{text}").reply }
)
```

Requires the optional `classifier` gem (`~> 2.3`). Add it to your Gemfile:

```ruby
gem "classifier", "~> 2.3"
```

## Convergence Detection

`RobotLab::Convergence` detects when two independent agents have reached the same conclusion using TF-IDF cosine similarity. Use it as a router fast-path to skip an expensive reconciler LLM call when verifiers already agree.

```ruby
# Check similarity directly
score = RobotLab::Convergence.similarity(result_a.reply, result_b.reply)
# => 0.92

# Boolean check against a threshold (default: 0.85)
RobotLab::Convergence.detected?(result_a.reply, result_b.reply)
# => true

# Use a custom threshold
RobotLab::Convergence.detected?(text_a, text_b, threshold: 0.75)
```

A common pattern is wiring convergence into a network router to skip reconciliation:

```ruby
router = ->(args) do
  a = args.context[:verifier_a]&.reply.to_s
  b = args.context[:verifier_b]&.reply.to_s
  RobotLab::Convergence.detected?(a, b) ? nil : ["reconciler"]
end

network = RobotLab.create_network(name: "verify", router: router) do
  # ...
end
```

Requires the `classifier` gem (`~> 2.3`).

## Structured Delegation

`robot.delegate(to:, task:)` dispatches work to another robot and returns the result, with duration and token metadata attached. Pass `async: true` for non-blocking fan-out.

```ruby
analyst  = RobotLab.build(name: "analyst",  system_prompt: "Analyze data.")
writer   = RobotLab.build(name: "writer",   system_prompt: "Write reports.")
manager  = RobotLab.build(name: "manager",  system_prompt: "Coordinate work.")

# Synchronous delegation — blocks until done
result = manager.delegate(to: analyst, task: "Analyze Q3 sales data")
puts result.reply
puts "%.2fs, %d tokens" % [result.duration, result.output_tokens]

# Asynchronous fan-out — returns immediately
f1 = manager.delegate(to: analyst, task: "Analyze Q3 sales", async: true)
f2 = manager.delegate(to: writer,  task: "Draft Q3 summary", async: true)

# Do other work here while both run in parallel...

analysis = f1.value           # blocks until resolved
summary  = f2.value           # blocks until resolved

# With a timeout
result = f1.value(timeout: 30)  # raises DelegationFuture::DelegationTimeout if too slow
```

`DelegationFuture` attributes:

```ruby
future.resolved?      # => true/false (non-blocking poll)
future.robot_name     # => "analyst"
future.delegated_by   # => "manager"
```

## Ractor Parallelism

RobotLab supports true CPU parallelism via Ruby Ractors — isolated execution contexts that bypass the GVL. Two modes are available:

**CPU-bound tools** — mark a tool `ractor_safe true` and RobotLab automatically routes its calls through a global `RactorWorkerPool` instead of running inline:

```ruby
class TranscribeAudio < RubyLLM::Tool
  ractor_safe true
  description "Transcribe an audio file"
  param :path, type: :string, desc: "Path to audio file"

  def execute(path:)
    AudioTranscriber.run(path)  # pure computation, no shared mutable state
  end
end
```

**Parallel robot networks** — pass `parallel_mode: :ractor` when creating a network to dispatch independent robots across hardware threads simultaneously:

```ruby
network = RobotLab.create_network(name: "analysis", parallel_mode: :ractor) do
  task :fetch,     fetcher_robot,    depends_on: :none
  task :sentiment, sentiment_robot,  depends_on: [:fetch]
  task :entities,  entity_robot,     depends_on: [:fetch]   # runs in parallel with sentiment
  task :summarize, summary_robot,    depends_on: [:sentiment, :entities]
end

results = network.run(message: "Analyze customer feedback")
# => { "fetch" => "...", "sentiment" => "positive", "entities" => "...", "summarize" => "..." }
```

See the [Ractor Parallelism guide](https://madbomber.github.io/robot_lab/guides/ractor-parallelism) for constraints, the frozen-data contract, and `RactorMemoryProxy` for shared state.

## Rails Integration

```bash
rails generate robot_lab:install
rails db:migrate
```

This creates:
- `config/initializers/robot_lab.rb` - Configuration
- `app/robots/` - Directory for your robots
- Database tables for conversation history

### Background Jobs

RobotLab ships with `RobotLab::Job`, an `ActiveJob::Base` subclass that handles the full robot-run lifecycle: robot class resolution, Turbo Stream wiring, thread-record persistence, and completion/error broadcasting.

**Generic job** (robot class supplied at enqueue time):

```bash
rails generate robot_lab:install   # creates app/jobs/robot_run_job.rb
```

```ruby
# app/jobs/robot_run_job.rb  (generated)
class RobotRunJob < RobotLab::Job
  queue_as :default
end

# Enqueue from a controller:
RobotRunJob.perform_later(
  robot_class: "SupportRobot",
  message:     params[:message],
  thread_id:   session_id
)
```

**Dedicated job** (robot class bound at the class level via DSL):

```bash
rails generate robot_lab:job Support            # binds to SupportRobot, queue: default
rails generate robot_lab:job Support --queue ai # custom queue
```

```ruby
# app/jobs/support_job.rb  (generated)
class SupportJob < RobotLab::Job
  queue_as :default
  robot_class SupportRobot
end

# Enqueue (no robot_class: needed):
SupportJob.perform_later(message: params[:message], thread_id: session_id)
```

When `thread_id` is provided and [turbo-rails](https://github.com/hotwired/turbo-rails) is installed, `RobotLab::Job` automatically:

- Wires `on_content` / `on_tool_call` Turbo Stream callbacks so the UI updates in real time
- Broadcasts a **completion** event to `"robot_lab_thread_#{thread_id}"` when the run finishes
- Broadcasts an **error** event (HTML-escaped) if the job raises

Omitting `thread_id` runs the robot in fire-and-forget mode — no persistence, no broadcasting.

## Documentation

Full documentation is available at **[https://madbomber.github.io/robot_lab](https://madbomber.github.io/robot_lab)**

## License

MIT License - Copyright (c) 2025 Dewayne VanHoozer

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/MadBomber/robot_lab.
