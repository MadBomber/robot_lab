# Creating Networks

Networks orchestrate multiple robots using [SimpleFlow](https://github.com/MadBomber/simple_flow) pipelines with DAG-based execution and optional task activation.

## Basic Network

Create a network with a sequential pipeline:

```ruby
network = RobotLab.create_network(name: "pipeline") do
  task :analyzer, analyzer_robot, depends_on: :none
  task :writer, writer_robot, depends_on: [:analyzer]
  task :reviewer, reviewer_robot, depends_on: [:writer]
end

result = network.run(message: "Analyze this document")
```

## Network Properties

### Name

Identifies the network for logging and debugging:

```ruby
network = RobotLab.create_network(name: "customer_service") do
  # ...
end
```

### Concurrency

Control parallel execution mode:

```ruby
network = RobotLab.create_network(name: "parallel", concurrency: :threads) do
  # :auto (default), :threads, or :async
end
```

### Shared Memory

Networks provide a shared memory accessible to all robots:

```ruby
network = RobotLab.create_network(name: "pipeline") do
  task :first, robot1, depends_on: :none
end

# Pre-populate shared memory
network.memory[:project] = "Q4 Report"
network.memory[:user_id] = 123
```

## Adding Tasks

### Sequential Tasks

Each task depends on the previous:

```ruby
network = RobotLab.create_network(name: "pipeline") do
  task :first, robot1, depends_on: :none
  task :second, robot2, depends_on: [:first]
  task :third, robot3, depends_on: [:second]
end
```

### Parallel Tasks

Tasks with the same dependencies run in parallel:

```ruby
network = RobotLab.create_network(name: "parallel_analysis") do
  task :fetch, fetcher, depends_on: :none

  # These run in parallel after :fetch
  task :sentiment, sentiment_bot, depends_on: [:fetch]
  task :entities, entity_bot, depends_on: [:fetch]
  task :keywords, keyword_bot, depends_on: [:fetch]

  # This waits for all three to complete
  task :merge, merger, depends_on: [:sentiment, :entities, :keywords]
end
```

This shared-`depends_on` form is the supported way to fan out.

### The `parallel` Block

`Network#parallel(name = nil, depends_on: :none, &block)` forwards to the underlying SimpleFlow pipeline's parallel group.

> [!WARNING]
> **`parallel` cannot currently register robot tasks.** Its block is
> `instance_eval`'d by `SimpleFlow::Pipeline::ParallelBlock`, which defines
> `step`, not `task` — writing `task :a, robot` inside raises
> `NoMethodError: undefined method 'task' for an instance of
> SimpleFlow::Pipeline::ParallelBlock`. And `step` bypasses `Network#task`, so
> the robot is never added to `network.robots`, never wired to the bus poller,
> and never wrapped in a `Task`. Use the shared-`depends_on` form above instead;
> it produces the same parallel execution through the supported path.

### Concurrency Cap

When a network fans out to many parallel robots, each makes a simultaneous LLM API call. With no limit this can exhaust API rate-limit quotas or database connection pools under load. Set `max_concurrent_robots:` on a `RunConfig` to cap how many robot tasks run at once — the rest queue behind an `Async::Semaphore` and start as slots open:

```ruby
config = RobotLab::RunConfig.new(max_concurrent_robots: 4)

network = RobotLab.create_network(name: "launch_assessment", config: config) do
  # All six declared parallel, but at most 4 LLM calls in-flight simultaneously
  task :market,     market_robot,     depends_on: :none
  task :competitive, comp_robot,      depends_on: :none
  task :tech,       tech_robot,       depends_on: :none
  task :risk,       risk_robot,       depends_on: :none
  task :financial,  financial_robot,  depends_on: :none  # queues until a slot opens
  task :legal,      legal_robot,      depends_on: :none  # queues until a slot opens

  task :director, director_robot, depends_on: [:market, :competitive, :tech,
                                               :risk, :financial, :legal]
end
```

`nil` (the default) means unlimited — identical to pre-existing behavior. For Rails deployments, size the cap to match your database connection pool and API rate tier. See [examples/31_launch_assessment.rb](https://github.com/MadBomber/robot_lab/blob/main/examples/31_launch_assessment.rb) for a working demo.

> [!WARNING]
> The cap is enforced by an `Async::Semaphore`, so it only applies on the **async
> execution path** — `concurrency: :async`, or `concurrency: :auto` when the
> `async` gem is available (both the default). With
> `concurrency: :threads` the value is accepted but **ignored**: every parallel
> task starts immediately. Do not rely on `max_concurrent_robots:` for rate
> limiting in a thread-mode network.

### Optional Tasks

Optional tasks only run when explicitly activated by a preceding robot:

```ruby
network = RobotLab.create_network(name: "router") do
  task :classifier, classifier_robot, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
  task :technical, technical_robot, depends_on: :optional
  task :general, general_robot, depends_on: :optional
end
```

## Per-Task Configuration

Tasks can have individual context and configuration that is deep-merged with the network's run parameters:

```ruby
# technical_robot was built with local_tools: [DebugTool, LogTool, TraceTool] —
# attached as classes, so the task's allowlist names them as classes too.
network = RobotLab.create_network(name: "support") do
  task :classifier, classifier_robot, depends_on: :none
  task :billing, billing_robot,
       context: { department: "billing", escalation_level: 2 },
       depends_on: :optional
  task :technical, technical_robot,
       context: { department: "technical" },
       tools: [DebugTool, LogTool],
       depends_on: :optional
end
```

### Task Options

| Option | Description |
|--------|-------------|
| `context` | Hash merged with run params (task values override) |
| `mcp` | MCP servers for this task (`:none`, `:inherit`, or array) |
| `tools` | Tools available to this task (`:none`, `:inherit`, or array) |
| `memory` | Task-specific memory |
| `config` | Per-task `RunConfig` (merged on top of network's config) |
| `depends_on` | `:none`, `[:task1]`, or `:optional` |
| `poller_group` | Bus delivery group label (`:default`, `:slow`, etc.) |

> [!IMPORTANT]
> `tools:` and `mcp:` both default to `:none`, and `:none` means "send zero tools
> this turn" — not "fall back to whatever the robot was built with". A task that
> omits `tools:` runs its robot with **no tools at all**, even if the robot was
> constructed with `local_tools:`. Write `tools: :inherit` on the task to send the
> robot's attached tools.
>
> One exception: a non-`:none` `tools:`/`mcp:` set by an **earlier** task carries
> forward through the shared run params to later tasks — see
> [Network-Wide Tool and MCP Defaults](#network-wide-tool-and-mcp-defaults).
>
> An explicit array is an **allowlist over the tools the robot already has** —
> it selects, it does not add. `tools: [DebugTool, LogTool]` on a robot built
> without those tools resolves to an empty set. Attach the tools with
> `local_tools:` at build time and use the task's `tools:` to narrow.
>
> **Entries must match how the tool was attached.** The filter compares each
> entry against `tool.name`, and `Class#name` is not `RubyLLM::Tool#name`. A tool
> attached as a **class** (`local_tools: [DebugTool]`) is named `"DebugTool"`; the
> same tool attached as an **instance** (`local_tools: [DebugTool.new]`) is named
> `"debug"`. Verified:
>
> | attached as | allowlist entry | result |
> |---|---|---|
> | class | `[DebugTool]` | matches |
> | class | `%w[debug]` | no match |
> | instance | `%w[debug]` | matches |
> | instance | `[DebugTool]` | no match |
>
> Mixing the two forms is the usual cause of a task that silently ends up with
> zero tools. `tools: :inherit` sidesteps the question entirely — it sends every
> attached tool without filtering.
>
> MCP needs both values: `mcp: :inherit` triggers the connection, and
> `tools: :inherit` is additionally required for the MCP tools to reach the model.

## Conditional Routing

Use optional tasks with custom Robot subclasses for intelligent routing:

```ruby
class ClassifierRobot < RobotLab::Robot
  def call(result)
    context = extract_run_context(result)
    message = context.delete(:message)
    robot_result = run(message, **context)

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    # Activate appropriate specialist based on classification
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
  system_prompt: "Classify as: billing, technical, or general. Respond with one word."
)

network = RobotLab.create_network(name: "support") do
  task :classifier, classifier, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
  task :technical, technical_robot, depends_on: :optional
  task :general, general_robot, depends_on: :optional
end
```

## Poller Groups

Each network maintains a shared `BusPoller` that serializes TypedBus deliveries on a per-robot basis: if a robot is already processing a message, new deliveries are queued and drained after the current one completes. This prevents re-entrancy without blocking other robots.

> [!NOTE]
> Despite the name, `BusPoller` runs **no background thread**. `start` and `stop`
> are no-ops, `running?` is hard-coded `true`, and `enqueue` processes and drains
> inline in the caller's own execution context (Async fiber or OS thread). All it
> owns is a mutex plus a per-robot queue. Don't expect deliveries to make
> progress on their own while the calling fiber is parked.

Named **poller groups** let you label tasks so slow robots are identifiable in logs and monitoring without needing separate infrastructure:

```ruby
network = RobotLab.create_network(name: "mixed_speed") do
  # Fast robots on the default group
  task :fetcher,   fetcher_robot,   depends_on: :none
  task :summarize, summarizer,      depends_on: [:fetcher]

  # Slow robots with expensive LLM calls — label them :slow
  task :analyst,   analyst_robot,   depends_on: [:fetcher],  poller_group: :slow
  task :writer,    writer_robot,    depends_on: [:analyst],  poller_group: :slow
end
```

Group labels are informational — there is no separate queue per group. In Async execution, robots naturally yield during LLM HTTP calls, so fast and slow robots interleave without explicit isolation.

## Running Networks

### Basic Run

```ruby
result = network.run(message: "Help me with my order")

# Get the final response
puts result.value.last_text_content
```

### With Additional Context

```ruby
result = network.run(
  message: "Check my order status",
  customer_id: 123,
  order_id: "ORD-456"
)
```

### Accessing Task Results

```ruby
result = network.run(message: "Process this")

# Access individual robot results — keyed by the ROBOT's name
classifier_result = result.context[:classifier]
billing_result = result.context[:billing]

# Original run parameters
original_params = result.context[:run_params]
```

> [!IMPORTANT]
> `result.context` is keyed by the **robot's `name:`**, not by the task label.
> The default `Robot#call` writes `result.with_context(@name.to_sym, robot_result)`.
> The lookups above only work because each task label matches its robot's name —
> `task :classifier, RobotLab.build(name: "classifier", ...)`. If they differ, you
> must index by the robot name. Keeping the two identical is the simplest way to
> avoid the mismatch. (`network.robots`, by contrast, *is* keyed by task name.)

## SimpleFlow::Result

Networks return a `SimpleFlow::Result` object:

```ruby
result = network.run(message: "Hello")

result.value            # The final task's output (RobotResult)
result.context          # Hash of all robot results and metadata
result.continue?        # true while execution is proceeding; false once a robot called halt
result.activated_steps  # Symbols of the :optional tasks that were activated
result.errors           # Accumulated errors
```

The full public API is exactly `activate`, `activated_steps`, `context`, `continue`, `continue?`, `errors`, `halt`, `value`, `with_context`, `with_error`.

> [!WARNING]
> `result.halted?` and `result.continued?` **do not exist** — calling either
> raises `NoMethodError`. There is a single predicate, `continue?`; a halted
> result is simply `continue? == false`.
>
> `result.with_value` is **private** (`public_method_defined?(:with_value)` is
> `false`), so calling it from a robot raises `NoMethodError` too. Use
> `continue(new_value)` to carry a new value forward.

## Broadcasting

Networks support a broadcast channel for network-wide announcements:

```ruby
# Register a broadcast handler
network.on_broadcast do |message|
  case message[:payload][:event]
  when :pause
    puts "Pausing: #{message[:payload][:reason]}"
  when :phase_complete
    puts "Phase complete: #{message[:payload][:phase]}"
  end
end

# Send broadcasts during execution
network.broadcast(event: :phase_complete, phase: "analysis")
```

## Patterns

### Classifier Pattern

Route to specialists based on classification:

```ruby
class SupportClassifier < RobotLab::Robot
  def call(result)
    context = extract_run_context(result)
    message = context.delete(:message)
    robot_result = run(message, **context)

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    category = robot_result.last_text_content.to_s.strip.downcase
    new_result.activate(category.to_sym)
  end
end

network = RobotLab.create_network(name: "support") do
  task :classifier, SupportClassifier.new(name: "classifier", template: :classifier),
       depends_on: :none
  task :billing, billing_robot, depends_on: :optional
  task :technical, technical_robot, depends_on: :optional
  task :general, general_robot, depends_on: :optional
end
```

### Pipeline Pattern

Process through sequential stages:

```ruby
network = RobotLab.create_network(name: "document_processor") do
  task :extract, extractor, depends_on: :none
  task :analyze, analyzer, depends_on: [:extract]
  task :format, formatter, depends_on: [:analyze]
end
```

### Fan-Out/Fan-In Pattern

Parallel processing with aggregation:

```ruby
network = RobotLab.create_network(name: "multi_analysis") do
  task :prepare, preparer, depends_on: :none

  # Fan-out: parallel analysis
  task :sentiment, sentiment_analyzer, depends_on: [:prepare]
  task :topics, topic_extractor, depends_on: [:prepare]
  task :entities, entity_recognizer, depends_on: [:prepare]

  # Fan-in: aggregate results
  task :aggregate, aggregator, depends_on: [:sentiment, :topics, :entities]
end
```

### Pipeline Error Resilience

When a robot raises an exception during pipeline execution, the error is caught and wrapped in a `RobotResult` with the error message as content. This ensures one failing robot does not crash the entire network:

```ruby
# If billing_robot raises an error, the network continues
# The error is available in the result context, keyed by the robot's name:
result = network.run(message: "Process this")
billing_result = result.context[:billing]

if billing_result&.last_text_content&.start_with?("Error:")
  puts "Billing failed: #{billing_result.last_text_content}"
  puts "Took: #{billing_result.duration}s"
end
```

Each robot's `RobotResult` includes a `duration` field (elapsed seconds) that is set automatically during pipeline execution, even for errored results.

### Conditional Continuation

A robot can halt execution early:

```ruby
class ValidatorRobot < RobotLab::Robot
  def call(result)
    context = extract_run_context(result)
    message = context.delete(:message)
    robot_result = run(message, **context)

    if robot_result.last_text_content.include?("INVALID")
      # Stop the pipeline
      result.halt(robot_result)
    else
      # Continue to next task
      result
        .with_context(@name.to_sym, robot_result)
        .continue(robot_result)
    end
  end
end
```

### Data Passing Between Tasks

Access previous task results via context:

```ruby
class ResponderRobot < RobotLab::Robot
  def call(result)
    # Get classifier's output — the key is the classifier ROBOT's name
    classification = result.context[:classifier]&.last_text_content

    context = extract_run_context(result)
    message = context.delete(:message)

    # Use classification in the message or context
    robot_result = run(
      "Classification: #{classification}\n\nUser message: #{message}",
      **context
    )

    result.with_context(@name.to_sym, robot_result).continue(robot_result)
  end
end
```

## Visualization

### ASCII Visualization

```ruby
puts network.visualize
# => ASCII representation of the pipeline
```

### Mermaid Diagram

```ruby
puts network.to_mermaid
# => Mermaid graph definition
```

### DOT Format (Graphviz)

```ruby
puts network.to_dot
# => Graphviz DOT format
```

### Execution Plan

```ruby
puts network.execution_plan
# => Description of execution order
```

## Network Introspection

```ruby
network.name              # => "support"
network.robots            # => Hash of key => Robot (see the key caveat below)
network.robot(:billing)   # => Robot instance
network["billing"]        # => Robot instance (alias)
network.available_robots  # => Array of Robot instances
network.crew              # => Array of Robot instances (Runnable protocol)
network.memory            # => Memory instance (shared)
network.to_h              # => Hash representation

network.add_robot(extra_robot)      # add without a pipeline task -> self
network.remove_robot(:extra_robot)  # remove by name -> the removed Robot, or nil
```

> [!WARNING]
> `network.robots` uses **two different key conventions**. `task :alpha, bot`
> registers the robot under the **task** name (`"alpha"`), while
> `network.add_robot(bot)` registers it under **`bot.name`**. `network.robot(...)`
> and `network[...]` inherit the same split. When task label and robot name
> differ, a lookup by robot name will miss a task-registered robot.
>
> `add_robot` also raises `ArgumentError` if the key is already taken:
> `Robot 'x' already exists in network 'n'`. Because the key conventions differ,
> adding a robot whose `name` matches an existing *task label* collides, while
> adding one whose name matches a task-registered robot's `name` does not.

`remove_robot` only drops the robot from the crew — it doesn't touch the pipeline, so don't remove a robot that's still a `depends_on` target of a task.

## Configuration Inheritance

Networks accept a `config:` parameter, but its reach is much narrower than a general "network-wide defaults" mechanism.

> [!WARNING]
> A network-level (or per-task) `RunConfig` propagates **only `mcp` and `tools`**
> to member robots, and only for robots that opt in with `:inherit`. LLM fields
> (`model`, `temperature`, `top_p`, `max_tokens`, …) and callbacks (`on_content`,
> `on_tool_call`, `on_tool_result`) are **never** inherited from a network —
> each robot reads those from its own config at construction time. Setting
> `model:` on a network config has no effect on any robot.
>
> Verified: a robot in a network configured with
> `RunConfig.new(model: "claude-haiku-4-5-20251001", temperature: 0.11)` still runs
> with the global default model and a `nil` temperature.

The one field the network consumes for itself is `max_concurrent_robots` (see [Concurrency Cap](#concurrency-cap)).

### Network-Wide Tool and MCP Defaults

Reaching a robot from a network `config:` takes **two** opt-ins, because
resolution runs in two passes — first the robot's build-time value against the
network config, then the task's runtime value against that result:

1. the robot is built with `tools: :inherit` (and/or `mcp: :inherit`), which is
   what pulls the network config's list down to the robot level, and
2. the task passes `tools: :inherit` (and/or `mcp: :inherit`), which is what
   actually sends them for that turn.

```ruby
shared = RobotLab::RunConfig.new(
  tools: [SearchTool, CalculatorTool],
  mcp:   [{ name: "fs", transport: { type: "stdio", command: "mcp-server-filesystem" } }]
)

# Build-time :inherit is the opt-in to `shared`. The robot must still *attach*
# the tools — the network list narrows what it already has, it cannot add.
analyzer_robot = RobotLab.build(
  name: "analyzer",
  system_prompt: "...",
  local_tools: [SearchTool, CalculatorTool, DraftTool],
  tools: :inherit,
  mcp:   :inherit
)

network = RobotLab.create_network(name: "pipeline", config: shared) do
  task :analyzer, analyzer_robot, depends_on: :none, tools: :inherit, mcp: :inherit
  task :writer,   writer_robot,   depends_on: [:analyzer]
end
```

Verified outcomes for the `:analyzer` task above:

| robot build `tools:` | task `tools:` | tools sent |
|---|---|---|
| `:inherit` | `:inherit` | `[:search, :calculator]` — `shared` applied, `DraftTool` filtered out |
| unset | `:inherit` | `[:search, :calculator, :draft]` — `shared` never reached the robot |
| `:inherit` | omitted (`:none`) | `[]` |

Same for MCP: with `mcp: :inherit` at build time the `fs` server connection is
attempted (it shows up in `robot.failed_mcp_server_names` if it fails); without
it, the network's `mcp:` list never reaches the robot and nothing is attempted.

> [!IMPORTANT]
> A task's `tools:`/`mcp:` **carries forward to later tasks**. `Task` writes them
> into the shared `run_params`, and the next task deep-merges that hash as its
> base — so `:writer` above ends up with `tools: :inherit` too, inherited from
> `:analyzer`, even though its own `task` line says nothing about tools. Verified:
> put `:writer` *first* in the pipeline and it resolves to `[]`; put it after an
> `:analyzer` that passes `tools: :inherit` and it resolves to
> `[:search, :calculator]`.
>
> Writing `tools: :none` on the downstream task does **not** undo it — `Task`
> skips writing `:none` into `run_params` (`run_params[:tools] = @tools unless
> @tools == :none`), so the inherited value survives untouched. Use an empty
> array instead, which *is* written and is treated as an explicit zero:
>
> ```ruby
> task :writer, writer_robot, depends_on: [:analyzer], tools: []   # verified -> []
> task :writer, writer_robot, depends_on: [:analyzer], tools: :none # verified -> still [:search, :calculator]
> ```

> [!NOTE]
> This is the one place where build-time `:inherit` is correct. For a
> **standalone** robot the parent level is the global `:none`, so build-time
> `:inherit` there resolves to an allowlist of `["none"]` and matches nothing —
> see [Building Robots: Adding Tools](building-robots.md#adding-tools).

To give every robot the same model, set it on each robot at construction:

```ruby
MODEL = "claude-sonnet-4"

analyzer_robot = RobotLab.build(name: "analyzer", system_prompt: "...", model: MODEL, temperature: 0.5)
writer_robot   = RobotLab.build(name: "writer",   system_prompt: "...", model: MODEL, temperature: 0.5)
```

### Per-Task `config:`

A per-task `config:` is merged into the network config that reaches the robot, so it carries the same `mcp`/`tools`-only limitation:

```ruby
# writer_robot built with local_tools: [SearchTool, CalculatorTool, DraftTool]
# and tools: :inherit — the same two opt-ins as above.
network = RobotLab.create_network(name: "pipeline", config: shared) do
  task :analyzer, analyzer_robot, depends_on: :none, tools: :inherit
  task :writer, writer_robot,
       config: RobotLab::RunConfig.new(tools: [DraftTool]),  # tools/mcp only
       tools: :inherit,
       depends_on: [:analyzer]
end
```

The task `config:` replaces the network's list for that task, so `:writer`
resolves to `[:draft]` while `:analyzer` resolves to `[:search, :calculator]`.

### Inheritance Chain

Per robot, the cascade runs least- to most-specific — note that template front matter is the **base**, not an override:

```
template front matter          (lowest — the starting point)
  -> config: RunConfig
    -> constructor kwargs      (highest — always wins)
```

Constructor kwargs always win. Network and task `config:` sit *outside* this chain and contribute only `mcp`/`tools`, and only where a robot or task asks for `:inherit`.

Two further front-matter caveats: only `model` and `temperature` are actually applied from front matter — `top_p`, `top_k`, `max_tokens`, `presence_penalty`, `frequency_penalty`, and `stop` are parsed and silently dropped. The same six *do* work as constructor kwargs.

## Best Practices

### 1. Keep Robots Focused

Each robot should have a single responsibility:

```ruby
# Good: focused robots
task :classify, classifier, depends_on: :none
task :respond, responder, depends_on: [:classify]

# Bad: one robot doing everything
task :do_everything, mega_robot, depends_on: :none
```

### 2. Use Per-Task Context

Pass task-specific configuration through context:

```ruby
task :billing, billing_robot,
     context: { department: "billing", max_refund: 500 },
     depends_on: :optional
```

### 3. Handle Missing Results

Guard against missing optional task results:

```ruby
def call(result)
  # Check if the optional task ran (key = that robot's name)
  if result.context[:validator]
    # Use validator result
  else
    # Handle missing validation
  end
end
```

### 4. Reset Memory Between Runs

If reusing a network, reset shared memory between runs:

```ruby
network.reset_memory
result = network.run(message: "New request")
```

## Next Steps

- [Using Tools](using-tools.md) - Add capabilities to robots
- [Memory Guide](memory.md) - Shared memory patterns
- [API Reference: Network](../api/core/network.md) - Complete API
