# Using Tools

Tools give robots the ability to interact with external systems. RobotLab supports three approaches: `RubyLLM::Tool` subclasses, `RobotLab::Tool` subclasses (with robot access), and `RobotLab::Tool.create` for dynamic tools.

## Defining Tools

### RubyLLM::Tool Subclass

For reusable tools that don't need robot access:

```ruby
class GetWeather < RubyLLM::Tool
  description "Get current weather for a location"

  param :location, type: :string, desc: "City name or zip code"
  param :unit, type: :string, desc: "Temperature unit", required: false

  def execute(location:, unit: "celsius")
    WeatherService.current(location, unit: unit)
  end
end
```

### RobotLab::Tool Subclass

For tools that need access to their owning robot (self-modification, spawning, etc.):

```ruby
class AdjustEnergy < RobotLab::Tool
  description "Adjust the robot's creativity level"

  param :level, type: "number", desc: "Temperature from 0.0 to 1.0"

  def execute(level:)
    robot.with_temperature(level)
    "Temperature adjusted to #{level}"
  end
end
```

Pass `robot: self` when constructing:

```ruby
class MyRobot < RobotLab::Robot
  def initialize
    super(
      name: "creative_bot",
      system_prompt: "You are creative.",
      local_tools: [AdjustEnergy.new(robot: self)]
    )
  end
end
```

### RobotLab::Tool.create (Dynamic Tools)

For quick, inline tools use the `Tool.create` factory:

```ruby
get_time = RobotLab::Tool.create(
  name: "get_time",
  description: "Get the current time"
) { |_args| Time.now.to_s }
```

With parameters:

```ruby
weather_tool = RobotLab::Tool.create(
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

## Built-in Tools

### AskUser

`RobotLab::AskUser` lets a robot ask the user a question via the terminal. The LLM decides when it needs human input and calls the tool with a question, optional choices, and an optional default.

`AskUser` reads its IO from `robot.input` / `robot.output`, and it finds the
robot through its own `robot` accessor — which is only populated when you attach
an **instance constructed with `robot:`**. Build the robot first, then attach:

```ruby
robot = RobotLab.build(
  name: "onboarding",
  system_prompt: "Walk the user through project setup. Ask questions to understand their needs."
)
robot.local_tools << RobotLab::AskUser.new(robot: robot)

robot.run("Help the user set up a new project", tools: :inherit)
```

> [!WARNING]
> Passing the bare class — `local_tools: [RobotLab::AskUser]` — leaves
> `tool.robot` as `nil`. The tool then ignores `robot.input`/`robot.output`,
> reads from the real `$stdin` (blocking your process, and hanging any test
> suite), and labels its prompt `[Robot]` instead of the robot's name.
> Note also the `tools: :inherit` above: a plain `run()` sends **zero** tools,
> so the LLM would never see `AskUser` at all.

The tool displays the robot's name and question, then waits for input:

```
[onboarding] What programming language will you use?
  1. Ruby
  2. Python
  3. Go
>
```

Features:

- **Open-ended**: just a question, free-text response
- **Multiple choice**: numbered options, user types the number or text
- **Default value**: shown in the prompt, used when user presses Enter

Because the IO is sourced from the robot, a `StringIO` pair makes the tool
testable without a terminal:

```ruby
robot.input  = StringIO.new("2\n")
robot.output = StringIO.new

# ... the LLM calls ask_user(question: "Which language?", choices: %w[Ruby Python Go])
robot.output.string
# => "\n[onboarding] Which language?\n  1. Ruby\n  2. Python\n  3. Go\n> "
```

> [!NOTE]
> The name the LLM sees is **`robot_lab--ask_user`**, not `ask_user`. RubyLLM
> derives tool names from the full class name including its namespace, so
> `RobotLab::AskUser` becomes `robot_lab--ask_user`. (A trailing `Tool` is
> stripped: a top-level `WeatherTool` is exposed as `weather`.) These derived
> names are what an allowlist must match **for tools attached as instances** —
> a tool attached as a class matches its class name instead. See
> [Runtime Tool Filtering](#runtime-tool-filtering).

See the [AskUser API reference](../api/core/tool.md#built-in-askuser) for full details.

## Attaching Tools to Robots

### Via Constructor

Pass tools via the `local_tools:` parameter when building a robot:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful assistant with tool access.",
  local_tools: [GetWeather, CalculatorTool]
)
```

`local_tools:` and `tools:` are different mechanisms — don't confuse them. `local_tools:` attaches tool **instances or classes**; `tools:` (see [Runtime Tool Filtering](#runtime-tool-filtering) below) is a **name allowlist** that filters which of the already-attached tools are sent for a given turn. Passing an instance or class to `tools:` raises `ArgumentError` immediately, naming the offending class and pointing you at `local_tools:` instead:

```ruby
RobotLab.build(name: "bot", tools: [GetWeather.new])
# => ArgumentError: `tools:` expects tool names (String/Symbol) to allow, but
#    received GetWeather. To attach tool instances or classes, pass them as
#    `local_tools:` (e.g. RobotLab.build(local_tools: [MyTool.new])).
```

### Via Template Front Matter

Declare tool class names in the template's YAML front matter. RobotLab resolves each string to a Ruby constant via `Object.const_get` and instantiates it:

```markdown title="prompts/weather_bot.md"
---
description: Weather assistant with forecast tools
tools:
  - GetWeather
  - GetForecast
---
You are a weather assistant. Use your tools to look up weather information.
```

```ruby
# Tools are resolved from frontmatter — no local_tools: needed
robot = RobotLab.build(template: :weather_bot)
```

Tool classes must be defined and loaded before building the robot. Unresolvable names are skipped with a warning. Constructor `local_tools:` overrides frontmatter `tools:` when provided.

### Via Chaining

`with_tools` is delegated straight to the underlying `RubyLLM::Chat`, so it
writes tools onto the chat rather than onto the robot's `local_tools`:

```ruby
robot = RobotLab.build(name: "assistant", system_prompt: "...")
robot.with_tools(GetWeather, CalculatorTool)
```

> [!WARNING]
> Chained tools do not survive a `run`. Because `run` defaults to
> `tools: :none`, it replaces the chat's tool list with an empty one before
> asking the LLM — wiping whatever `with_tools` put there:
>
> ```ruby
> robot.with_tools(GetWeather, CalculatorTool)
> robot.chat.tools.keys   # => [:get_weather, :calculator]
> robot.run("Hello")
> robot.chat.tools.keys   # => []   <- cleared by the run
> ```
>
> For tools that should persist across runs, attach them with `local_tools:`
> and pass `tools: :inherit` on each `run`.

## Runtime Tool Filtering

`tools:` (and `mcp:`) also work as a **per-run** override, passed to `run()` itself, on top of the build-time/network/global hierarchy described in [Hierarchical MCP and Tools](../getting-started/configuration.md#hierarchical-mcp-and-tools):

```ruby
robot.run("What's the weather?", tools: :inherit)        # every attached tool
robot.run("Just chat, no tools needed.", tools: :none)    # zero tools this turn
# Allowlist. This robot attached its tools as CLASSES, so match the class names:
robot.run("Only use the calculator.", tools: %w[CalculatorTool])
```

| Value | Meaning |
|-------|---------|
| `:inherit` | Propagate the parent level's allowlist (build-time / network / global) |
| `:none`, `[]` | Send **zero** tools this turn |
| `nil` | No filter at all — every attached tool, **discarding** any parent allowlist |
| `["name", ...]` | Only these tools, matched against how each was attached |

> [!CAUTION]
> `tools: nil` does **not** send zero tools, and it is **not** the same as
> `:inherit`. `:inherit` carries the parent's allowlist down; `nil` throws the
> filter away entirely. With a robot built `tools: %w[GetWeather]` holding
> `GetWeather` and `CalculatorTool`:
>
> ```
> run(tools: :inherit)  -> [:get_weather]                  # parent allowlist honored
> run(tools: nil)       -> [:get_weather, :calculator]     # allowlist discarded
> ```
>
> If you mean zero tools, write `:none`.

> [!IMPORTANT]
> An allowlist entry must match **how the tool was attached**, because the
> comparison uses `tool.name` and `Class#name` differs from `RubyLLM::Tool#name`:
>
> | Attached as | Allowlist that matches |
> |---|---|
> | `local_tools: [CalculatorTool]` (class) | `[CalculatorTool]` or `%w[CalculatorTool]` |
> | `local_tools: [CalculatorTool.new]` (instance) | `%w[calculator]` |
>
> Note the constructor's `tools:` is validated and **rejects** classes and
> instances outright (`ArgumentError`); only task-level and `run()` values accept
> them.

An explicit `:none`/`[]` is useful for a relevance filter that decided no tool is useful for the current message — it now genuinely sends zero tools for that turn (previously an empty allowlist was silently treated as "all tools," which could overflow small-context local models with the full tool set). Each turn's resolved tool set fully **replaces** the chat's tools rather than accumulating, so a later `:none` turn correctly clears whatever a prior turn attached.

> [!CAUTION]
> **Watch the default.** Both `Robot.new`'s and `run()`'s `tools:`/`mcp:`
> parameters default to `:none`, not `:inherit`. If you build a robot with
> `local_tools:` and then call `robot.run(message)` with no `tools:` override at
> all, the runtime default takes the explicit-`:none` path above — sending no
> tools for that turn. **Pass `tools: :inherit` on the `run()` call** (or on the
> network `task`, which is forwarded to `run()`) anywhere you need the robot's
> attached tools available.

> [!WARNING]
> For a **standalone** robot, do not pass `tools: :inherit` at *build* time as a
> way to turn tools on. Build-time `:inherit` resolves against the level above
> it, which for a standalone robot is the global `:none` — producing an
> allowlist of `["none"]` that matches nothing, and the empty result then
> carries into the runtime pass. Leave build-time `tools:` unset:
>
> ```ruby
> # build tools: unset      + run(tools: :inherit)  -> [:t1]   correct
> # build tools: :inherit   + run(tools: :inherit)  -> []      the standalone trap
> # build tools: :none      + run(tools: :inherit)  -> [:t1]   also fine
> ```
>
> This applies to a robot run on its own. Inside a **network** whose `config:`
> supplies `tools:`/`mcp:`, the parent level is that network list rather than
> `:none`, and build-time `:inherit` is *required* — it is the robot's opt-in to
> the network value. See
> [Network-Wide Tool and MCP Defaults](creating-networks.md#network-wide-tool-and-mcp-defaults).

### Tool Capping and Per-Turn Filtering

Most LLM providers reject a tool array longer than 128 entries and fail the whole turn. RobotLab clamps the fully-resolved tool list to a ceiling right before handing it to the chat provider — the definitive choke point regardless of how the tools were configured, filtered, or MCP-connected:

```ruby
robot = RobotLab.build(
  name: "power_user",
  system_prompt: "...",
  local_tools: many_tools,       # say, 150 tools
  config: RobotLab::RunConfig.new(max_tools: 50)  # override the default ceiling
)
```

- Default ceiling: **128** tools per turn (`RobotLab::Robot::DEFAULT_MAX_TOOLS`)
- Override with a **positive** `max_tools:` on `RunConfig` (or the `max_tools:` cascade field — see [Available Fields](../getting-started/configuration.md#available-fields))
- When a turn's resolved tools exceed the cap, RobotLab logs a warning naming how many were dropped and sends the first `max_tools` entries

> [!WARNING]
> The cap **cannot be disabled.** `max_tools: nil`, `0`, or a negative number
> all fall back to the 128 default — only a positive integer changes the
> ceiling. If you attach more than 128 tools and set `max_tools: 0` expecting
> "unlimited", you get the first 128.
>
> The truncation is not silent, though — `cap_tools` logs it at `WARN` through
> `RobotLab.config.logger` every time it fires:
>
> ```
> [power_user] tool list (150) exceeds max_tools (128); sending 128, dropping 22
> ```

## Skill Scripts and Sandboxing

A skill bundle (a directory with a `SKILL.md` plus `scripts/`, discovered via `AgentSkill`) can expose its scripts as tools (`ScriptTool`). Because those scripts run as real OS processes, each `SKILL.md` can declare the capabilities its scripts need directly in front matter, alongside `name`/`description`:

```markdown title="skills/deploy-checker/SKILL.md"
---
name: deploy-checker
description: Verifies a deployment's health before promoting it.
fs_read: ["./data", "/etc/hosts"]
fs_write: ["./out"]
network: true
timeout: 30
trust: external   # or "core" for trusted, always-unconfined skills
---
```

Sandboxing itself is **opt-in and off by default** — see the [`sandbox:` config section](../getting-started/configuration.md#skill-script-sandboxing-sandbox-section). When disabled, scripts run exactly as they always have, unconfined. When enabled:

- The global `sandbox:` config is a **ceiling** (`fs_read`, `fs_write`, `network`, `timeout`); each skill's front matter is its **declared** request. The script actually runs under the **intersection** of the two — a path outside the ceiling's roots is dropped even if the skill declares it, `network` requires both sides to allow it, and `timeout` is the smaller of the two.
- On macOS, confinement is enforced with a generated `sandbox-exec` (Seatbelt) profile: deny-by-default, with narrow allowances for the interpreter to boot, the granted read/write paths, and (optionally) the network. Notably, `$HOME` is never implicitly readable — SSH keys and cloud credentials stay out of reach unless a path under `$HOME` is explicitly granted.
- Off macOS, or for any skill declaring `trust: core`, sandboxing is a passthrough — confinement is currently macOS-only and is always skipped for trusted "core" skills regardless of platform.
- A script that runs past its `timeout` is killed (its whole process group) and reported back to the LLM as a timed-out error rather than hanging the turn.

## Parameter Types

Define parameters on `RubyLLM::Tool` subclasses using `param`:

### String

```ruby
param :name, type: :string, desc: "User's full name"
```

### Integer

```ruby
param :count, type: :integer, desc: "Number of results"
```

### Number (Float)

```ruby
param :price, type: :number, desc: "Price in dollars"
```

### Boolean

```ruby
param :active, type: :boolean, desc: "Whether the user is active"
```

### Array

```ruby
param :tags, type: :array, desc: "List of tags"
```

### Enumerated Values

`param` has **no `enum:` option**. Its full signature is
`param(name, type: "string", desc: nil, description: nil, required: true)` —
anything else raises `ArgumentError: unknown keyword: :enum`. Express the
allowed values in the description instead, and validate in `execute`:

```ruby
STATUSES = %w[pending active completed].freeze

param :status, type: :string, desc: "Order status — one of: pending, active, completed"

def execute(status:)
  return { error: "status must be one of #{STATUSES.join(', ')}" } unless STATUSES.include?(status)
  # ...
end
```

### Required vs Optional

Parameters are required by default. Mark optional with `required: false`:

```ruby
param :query, type: :string, desc: "Search query"                    # required
param :limit, type: :integer, desc: "Max results", required: false   # optional
```

## Tool Patterns

### Database Lookup

```ruby
class FindUser < RubyLLM::Tool
  description "Find user by email or ID"

  param :identifier, type: :string, desc: "Email address or user ID"

  def execute(identifier:)
    user = User.find_by(id: identifier) || User.find_by(email: identifier)
    user ? user.to_h : { error: "User not found" }
  end
end
```

### API Integration

```ruby
class GetStockPrice < RubyLLM::Tool
  description "Get current stock price for a ticker symbol"

  param :symbol, type: :string, desc: "Stock ticker symbol (e.g. AAPL)"

  def execute(symbol:)
    response = HTTP.get("https://api.stocks.example/quote/#{symbol}")
    JSON.parse(response.body)
  rescue HTTP::Error => e
    { error: "Failed to fetch stock price: #{e.message}" }
  end
end
```

### File Operations

```ruby
class ReadFile < RubyLLM::Tool
  description "Read contents of a file"

  param :path, type: :string, desc: "Absolute path to the file"

  def execute(path:)
    if File.exist?(path) && File.readable?(path)
      { content: File.read(path), size: File.size(path) }
    else
      { error: "File not found or not readable" }
    end
  end
end
```

### Multi-Step Operations

```ruby
class ProcessOrder < RubyLLM::Tool
  description "Validate and process a customer order"

  param :order_id, type: :string, desc: "The order ID to process"

  def execute(order_id:)
    order = Order.find(order_id)

    # Validate
    return { error: "Invalid order" } unless order.valid?

    # Process payment
    result = PaymentProcessor.charge(order)
    return { error: result[:error] } unless result[:success]

    # Update status
    order.update!(status: "paid")

    { success: true, order_id: order.id, amount: order.total }
  end
end
```

## Tool Return Values

### Structured Data

Return hashes with consistent structure:

```ruby
def execute(user_id:)
  user = User.find(user_id)
  {
    id: user.id,
    name: user.name,
    email: user.email,
    created_at: user.created_at.iso8601
  }
end
```

### Simple Values

```ruby
def execute(**_)
  Time.now.to_s
end
```

### Lists

```ruby
def execute(query:)
  results = Search.query(query)
  results.map { |r| { id: r.id, title: r.title, score: r.score } }
end
```

## Error Handling

### Automatic Error Handling

`RobotLab::Tool` automatically catches `StandardError` exceptions from `execute` and returns a plain-text error string to the LLM. The LLM can then reason about the failure and try an alternative approach — without crashing the run.

```ruby
class FetchResource < RobotLab::Tool
  description "Fetch a resource from an external API"
  param :id, type: :string, desc: "Resource ID"

  def execute(id:)
    ExternalAPI.fetch(id)
  end
end

tool = FetchResource.new
result = tool.call({ "id" => "missing" })
# If ExternalAPI.fetch raises, result is:
# => "Error (fetch_resource): connection refused"
```

This applies to all `RobotLab::Tool` variants — subclasses, `Tool.create` factory tools, and MCP tools.

### RobotLab::ToolError and Retryability

`RobotLab::ToolError` is handled on a separate path from ordinary
`StandardError`s. Raising one with `retryable: true` appends `" (retryable)"`
to the text the LLM sees, hinting that another attempt may succeed:

```ruby
class FetchResource < RobotLab::Tool
  description "Fetch a resource from an external API"
  param :id, type: :string, desc: "Resource ID"

  def execute(id:)
    raise RobotLab::ToolError.new("upstream 503", retryable: true)
  end
end

FetchResource.new.call({ "id" => "1" })
# => "Error (fetch_resource): upstream 503 (retryable)"

# Without retryable:, no suffix is appended:
#   raise RobotLab::ToolError, "bad input"
#   => "Error (fetch_resource): bad input"
```

> [!WARNING]
> Only the ordinary `StandardError` path writes to the log
> (`RobotLab.config.logger.warn("Tool 'name' error: RuntimeError: …")`).
> A `RobotLab::ToolError` is turned into text for the LLM and logged
> **nowhere** — if you rely on `ToolError` for expected failures, add your own
> logging inside `execute`, or those failures leave no trace outside the
> transcript.

### Critical Tools (Opt-Out)

For tools where you want exceptions to propagate (e.g., a tool whose failure should abort the run), set `raise_on_error` on the class:

```ruby
class CriticalPayment < RobotLab::Tool
  self.raise_on_error = true

  description "Process a payment"
  param :amount, type: :number, desc: "Payment amount"

  def execute(amount:)
    PaymentGateway.charge(amount)
  end
end
```

`raise_on_error` is per-class and defaults to `false`. Setting it on one class does not affect others.

> [!WARNING]
> `raise_on_error` does **not** walk the inheritance chain. A subclass of a
> class that set it silently reverts to `false`:
>
> ```ruby
> class CriticalBase < RobotLab::Tool
>   self.raise_on_error = true
> end
>
> class ChargeCard < CriticalBase; end
>
> CriticalBase.raise_on_error?   # => true
> ChargeCard.raise_on_error?     # => false   <- NOT inherited
> ```
>
> Set `self.raise_on_error = true` on every class that needs it. (This differs
> from `ractor_safe`, below, which *does* consult the superclass.)

### Manual Error Handling

You can still handle specific errors inside `execute` for domain-specific responses:

```ruby
class FetchResource < RobotLab::Tool
  description "Fetch a resource from an external API"
  param :id, type: :string, desc: "Resource ID"

  def execute(id:)
    result = ExternalAPI.fetch(id)
    { success: true, data: result }
  rescue ExternalAPI::NotFound
    { success: false, error: "Resource not found", id: id }
  rescue ExternalAPI::RateLimited => e
    { success: false, error: "Rate limited", retry_after: e.retry_after }
  end
  # Any other StandardError is still caught by the automatic handler
end
```

## Ractor-Safe Tools

A tool class can declare itself safe to run inside a Ractor. When it is, and the
[`robot_lab-ractor`](https://github.com/MadBomber/robot_lab-ractor) extension
gem is loaded, `call` dispatches the work to `RobotLab.ractor_pool` instead of
running it inline on the calling thread — giving real CPU parallelism for
compute-bound tools.

```ruby
class Fibonacci < RobotLab::Tool
  ractor_safe true

  description "Compute the nth Fibonacci number"
  param :n, type: :integer, desc: "Which Fibonacci number to compute"

  def execute(n:)
    a, b = 0, 1
    n.times { a, b = b, a + b }
    a
  end
end

Fibonacci.ractor_safe?   # => true
```

Dispatch to the pool happens only when **all three** hold:

1. `ractor_safe?` is true
2. the class has a resolvable name — anonymous classes (including every tool
   built by `Tool.create`) fall back to the inline path
3. the `robot_lab-ractor` extension is loaded

Otherwise `execute` runs inline, exactly as an ordinary tool would. Pool size
comes from the `ractor_pool_size` `RunConfig` field (`:auto` when unset).

> [!WARNING]
> A Ractor-safe tool must be genuinely stateless: it is instantiated **fresh
> inside the Ractor worker** for every call, so `robot`, captured closures, and
> mutable class-level state are not available to it, and the result comes back
> frozen. Do not set `ractor_safe true` on a tool that touches its robot.

Unlike `raise_on_error`, `ractor_safe` **does** walk the inheritance chain — a
subclass of a Ractor-safe tool is Ractor-safe unless it says otherwise.

## Tool Callbacks

Robots support `on_tool_call` and `on_tool_result` callbacks for monitoring tool usage. Each receives exactly **one** argument — `on_tool_result` gets the result only, not the originating call:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "...",
  local_tools: [GetWeather],
  on_tool_call: ->(tool_call) { puts "Calling: #{tool_call.name}" },
  on_tool_result: ->(result) { puts "Result: #{result}" }
)

robot.run("What's the weather in Tokyo?", tools: :inherit)
```

See [Streaming](streaming.md#tool-callbacks) for details, including the RubyLLM deprecation warning these emit.

## RobotLab::Tool.create with Schema

For dynamic tools via `Tool.create`, pass parameters as a JSON Schema hash:

```ruby
tool = RobotLab::Tool.create(
  name: "search",
  description: "Search for items",
  parameters: {
    type: "object",
    properties: {
      query: { type: "string", description: "Search query" },
      limit: { type: "integer", description: "Max results" }
    },
    required: ["query"]
  }
) { |args| Search.query(args[:query], limit: args[:limit] || 10) }
```

## Best Practices

### 1. Clear Descriptions

Write descriptions that help the LLM understand when and how to use the tool:

```ruby
# Good: Specific and actionable
class SearchOrders < RubyLLM::Tool
  description "Search customer orders by date range, status, or customer email. Returns up to 50 matching orders sorted by date."
  # ...
end

# Bad: Vague
class Search < RubyLLM::Tool
  description "Searches stuff"
  # ...
end
```

### 2. Validate Inputs

```ruby
def execute(email:)
  unless email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
    return { error: "Invalid email format" }
  end
  # ... rest of logic
end
```

### 3. Return Structured Data

```ruby
# Good: Structured and consistent
def execute(**_)
  {
    success: true,
    data: { id: 1, name: "Item" },
    metadata: { fetched_at: Time.now.iso8601 }
  }
end

# Bad: Unstructured
def execute(**_)
  "Found item with id 1 named Item"
end
```

### 4. Keep Tools Focused

Each tool should do one thing well. Prefer multiple focused tools over one tool that does everything.

## Next Steps

- [MCP Integration](mcp-integration.md) - External tool servers
- [Building Robots](building-robots.md) - Robot creation patterns
- [API Reference: Tool](../api/core/tool.md) - Complete API
