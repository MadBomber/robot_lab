# Network

Orchestrates multiple robots using SimpleFlow pipelines with DAG-based execution.

## Class: `RobotLab::Network`

```ruby
network = RobotLab.create_network(name: "support", config: config) do
  task :classifier, classifier_robot, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
end
```

`RobotLab.create_network(name:, concurrency: :auto, config: nil, &block)` is the
factory. `Network.new` additionally accepts `memory:` and `parallel_mode:`:

```ruby
RobotLab::Network.new(name:, concurrency: :auto, memory: nil, config: nil, parallel_mode: :async, &block)
```

There is no `router:` and no `robots:` keyword. Routing is done by subclassing
`Robot`, overriding `#call`, and activating optional tasks — see
[Conditional Routing](#conditional-routing).

## Attributes

### name

```ruby
network.name  # => String
```

Network identifier for logging and debugging.

### robots

```ruby
network.robots  # => Hash<String, Robot>
```

Robots keyed by **String**. The key depends on how the robot was registered:

| Registered via | Key |
|----------------|-----|
| `task(:analyzer, robot)` | the **task** name — `"analyzer"` — regardless of `robot.name` |
| `add_robot(robot)` | `robot.name` |

```ruby
n = RobotLab.create_network(name: "n") do
  task :a, RobotLab.build(name: "alpha"), depends_on: :none
end
n.add_robot(RobotLab.build(name: "helper"))

n.robots.keys        # => ["a", "helper"]
n.crew.map(&:name)   # => ["alpha", "helper"]
```

Examples that assume the two coincide only work when you name the robot after
its task. `result.context` is keyed by the **robot's** name (`@name.to_sym`), not
the task name — another reason to keep them identical.

### memory

```ruby
network.memory  # => Memory
```

Shared reactive memory for every robot in the network. It is passed to each robot
on `run()` as `network_memory:`, so in-network robots read and write this instance
instead of their own inherent memory. Created as `Memory.new(network_name: name)`
unless one is supplied to `Network.new(memory:)`.

### config

```ruby
network.config  # => RunConfig
```

Shared operational defaults. Passed to robots during `run()` as `network_config:`.

!!! warning "Only `mcp` and `tools` propagate to member robots"
    LLM fields (`model`, `temperature`, `max_tokens`, …) and callbacks
    (`on_content`, `on_tool_call`, `on_tool_result`) are read from each robot's
    own config at construction time and are **never** inherited from the
    network. A member robot picks up the network's `mcp`/`tools` only when it
    opts in with `:inherit`. `max_concurrent_robots` is the one field the
    network itself consumes (it is passed to `pipeline.call_parallel`).

### parallel_mode

```ruby
network.parallel_mode  # => :async (default) or :ractor
```

Execution strategy for `run`. `:async` uses the SimpleFlow pipeline;
`:ractor` routes through `RactorNetworkScheduler` and **raises
`RobotLab::DependencyError`** unless the `robot_lab-ractor` gem is loaded. Set via
`Network.new(parallel_mode:)`.

### hooks

```ruby
network.hooks  # => RobotLab::HookRegistry
```

The network's own hook registry, populated by [`network.on`](#on). Consulted for
network-run, robot-run, and task hooks alongside `RobotLab.hooks`.

### pipeline

```ruby
network.pipeline  # => SimpleFlow::Pipeline
```

The underlying SimpleFlow pipeline.

## Methods

### run

```ruby
result = network.run(
  message: "Help me",
  customer_id: 123,
  **context
)
# => SimpleFlow::Result

# Runnable protocol: a positional message works too, just like Robot#run
result = network.run("Help me", customer_id: 123)
```

Execute the network pipeline.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `message` | `String`, `nil` | The input message — as the `message:` keyword, or positionally (folded into `message:` when given) |
| `**context` | `Hash` | Additional context passed to all robots |

`run` injects three keys into the run context before executing:
`network_memory:` (the shared `Memory`), `network:` (the network itself), and
`network_config:` (only when the network's `RunConfig` is non-empty). The whole
execution is wrapped in the `:network_run` hook family.

**Returns:** `SimpleFlow::Result` — except under `parallel_mode: :ractor`, where
`RactorNetworkScheduler#run_pipeline` returns its own results structure.

!!! note "Member robots still default to `tools: :none`"
    Task-level `tools:`/`mcp:` default to `:none` just like `Robot#run`. Declare
    the task with `tools: :inherit` (or an explicit name array) for its robot to
    receive any tools.

### task

```ruby
network.task(name, robot,
             context: {}, mcp: :none, tools: :none, memory: nil,
             config: nil, depends_on: :none, poller_group: :default)
# => self
```

Add a task to the pipeline with optional per-task configuration.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `Symbol` | **required** | Task identifier; also the key under which the robot is stored in `network.robots` |
| `robot` | `Robot` | **required** | Robot instance to execute |
| `context` | `Hash` | `{}` | Task-specific context (deep-merged with run params) |
| `mcp` | `Symbol`, `Array` | `:none` | MCP server config for this task |
| `tools` | `Symbol`, `Array` | `:none` | Tools config for this task — tool **names**, not instances |
| `memory` | `Memory`, `Hash`, `nil` | `nil` | Task-specific memory, overriding the network's shared memory |
| `config` | `RunConfig`, `nil` | `nil` | Per-task config, merged on top of the network's RunConfig. Like the network config, only `mcp`/`tools` reach the robot |
| `depends_on` | `:none`, `Array<Symbol>`, `:optional` | `:none` | Task dependencies |
| `poller_group` | `Symbol` | `:default` | Bus-poller group for this robot; the network registers the group on its shared `BusPoller` and assigns it to the robot |

**Dependency Types:**

| Value | Description |
|-------|-------------|
| `:none` | No dependencies, runs first |
| `[:task1, :task2]` | Waits for listed tasks to complete |
| `:optional` | Only runs when explicitly activated via `result.activate(:name)` |

### parallel

```ruby
network.parallel(name = nil, depends_on: :none) { ... }
# => self
```

Declare a named group of steps that run concurrently, then depend on the group as
a unit. Delegates directly to `SimpleFlow::Pipeline#parallel`.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `Symbol`, `nil` | `nil` | Optional name for the group, usable in a later `depends_on:` |
| `depends_on` | `Symbol`, `Array` | `:none` | Dependencies for the group as a whole |

!!! warning "Use `step` inside the block, not `task`"
    The block is `instance_eval`'d by `SimpleFlow::Pipeline::ParallelBlock`,
    whose only DSL methods are `step` and `steps` — **not** `task`. This is an
    inconsistency with the top-level `Network` DSL. Inner entries therefore also
    bypass `Network#task`, so they are not registered in `network.robots`, get no
    per-task `context:`/`tools:`/`memory:`, and are not assigned a poller group.

    ```ruby
    network.parallel :fetch_data, depends_on: :validate do
      step :fetch_orders,   orders_robot
      step :fetch_products, products_robot
    end
    network.task :process, processor, depends_on: :fetch_data
    ```

    Declaring the concurrent robots as ordinary `task`s that share a `depends_on:`
    avoids all of that and is the pattern used throughout these docs.

### broadcast

```ruby
network.broadcast(payload)
# => self
```

Send a network-wide announcement. Wraps `payload` as
`{ payload:, network:, timestamp: }`, dispatches it asynchronously to every
handler registered with [`on_broadcast`](#on_broadcast), and also writes it to
shared memory under `Network::BROADCAST_KEY` (`:_network_broadcast`) so robots can
pick it up with `memory.subscribe(:_network_broadcast)`.

```ruby
network.broadcast(event: :pause, reason: "rate limit hit")
```

### on_broadcast

```ruby
network.on_broadcast { |message| ... }
# => self
```

Register a handler for `broadcast` messages. The block receives the full envelope
(`message[:payload]`, `message[:network]`, `message[:timestamp]`).

**Raises:** `ArgumentError` if no block is given.

```ruby
network.on_broadcast do |message|
  pause_current_work if message[:payload][:event] == :pause
end
```

### reset_memory

```ruby
network.reset_memory
# => self
```

Reset the network's shared memory to its initial state (`Memory#reset`). Useful
between runs. This clears the key-value store only; it does not touch any robot's
chat history.

### on

```ruby
network.on(HandlerClass, context: nil)
```

Register a hook handler on the network's own registry (`network.hooks`). Unlike
`robot.on`, handlers registered here **do** fire for the `:task` hook family,
which resolves against `[RobotLab.hooks, network&.hooks]`.

### to_dot

```ruby
network.to_dot  # => String, or nil
```

Graphviz DOT representation of the pipeline (`pipeline.visualize_dot`).

### add_robot

```ruby
network.add_robot(robot)
# => self
```

Add a robot without creating a pipeline task. Useful for robots referenced by other tasks.

### remove_robot

```ruby
network.remove_robot("billing")
# => Robot, or nil if no robot by that name was present
```

Remove a dynamically-added robot from the crew by name. Complements `add_robot`. Only removes the robot from `@robots` — it does **not** rewrite the pipeline, so don't remove a robot that is a pipeline task (a `depends_on` reference to a removed robot's task name would then fail).

### robot / []

```ruby
network.robot("billing")  # => Robot
network["billing"]        # => Robot (alias)
```

Get robot by name.

### available_robots

```ruby
network.available_robots  # => Array<Robot>
```

Returns all robot instances.

### visualize

```ruby
network.visualize  # => String
```

ASCII visualization of the pipeline.

### to_mermaid

```ruby
network.to_mermaid  # => String
```

Mermaid diagram definition.

### execution_plan

```ruby
network.execution_plan  # => String
```

Human-readable execution plan.

### to_h

```ruby
network.to_h  # => Hash
```

Hash representation of network configuration.

```ruby
{
  name: "support",
  robots: ["classifier", "billing", "technical"],   # keys of network.robots
  tasks: ["classifier", "billing", "technical"],    # task names only
  optional_tasks: [:billing, :technical],
  config: { model: "claude-sonnet-4", temperature: 0.7 }
}
```

The hash is `.compact`ed and `config` is omitted entirely when the network's
`RunConfig` is empty. `config` comes from `RunConfig#to_json_hash`, so the
non-serializable fields (`on_tool_call`, `on_tool_result`, `on_content`, `bus`,
`auto_compact`) are excluded. `robots` includes robots added with `add_robot`;
`tasks` does not.

## SimpleFlow::Result

`Network#run` returns a `SimpleFlow::Result`. This is its **complete** public API
(simple_flow 0.4):

| Method | Description |
|--------|-------------|
| `value` | The final task's output (a `RobotResult`) |
| `context` | Hash of accumulated context, including every task's result |
| `continue?` | `true` while the pipeline is still running steps |
| `continue(value)` | Returns a new Result carrying `value`, still continuing |
| `halt(value)` | Returns a new Result that stops the pipeline |
| `with_context(key, value)` | Returns a new Result with an added context entry |
| `with_error(key, message)` | Returns a new Result with an added error — **both arguments are required** |
| `errors` | Accumulated errors |
| `activate(step_name)` | Marks an `:optional` step to run |
| `activated_steps` | The set of optional steps activated so far |

!!! danger "`halted?`, `continued?`, and `with_value` do not exist"
    They raise `NoMethodError`. The predicate is `continue?` — a halted result
    is one where `continue?` is `false`.

    ```ruby
    result = network.run(message: "Hello")
    puts "stopped early" unless result.continue?
    ```

### Context Structure

```ruby
result.context[:run_params]   # Original run parameters
result.context[:classifier]   # RobotResult from the robot NAMED "classifier"
result.context[:billing]      # RobotResult from the robot NAMED "billing"
```

`Robot#call` writes its result with `result.with_context(@name.to_sym, robot_result)`,
so context keys are **robot names**, not task names. Name each robot after its
task to keep the two aligned.

## Builder DSL

### task

```ruby
network = RobotLab.create_network(name: "pipeline") do
  task :first, robot1, depends_on: :none
  task :second, robot2, depends_on: [:first]
  task :optional, robot3, depends_on: :optional
end
```

### task with context

```ruby
network = RobotLab.create_network(name: "support") do
  task :classifier, classifier_robot, depends_on: :none
  task :billing, billing_robot,
       context: { department: "billing", escalation_level: 2 },
       depends_on: :optional
  task :technical, technical_robot,
       context: { department: "technical" },
       # Entries must match how the robot attached each tool. If technical_robot
       # was built with local_tools: [DebugTool, LogTool] (classes), use the class
       # names; if it attached instances, use %w[debug log] instead.
       tools: %w[DebugTool LogTool],
       depends_on: :optional
end
```

`tools:` here is a **name allowlist**, exactly as on `Robot`. Attach the tool
objects themselves with `local_tools:` when building the robot.

## Examples

### Sequential Pipeline

```ruby
network = RobotLab.create_network(name: "pipeline") do
  task :extract, extractor, depends_on: :none
  task :transform, transformer, depends_on: [:extract]
  task :load, loader, depends_on: [:transform]
end

result = network.run(message: "Process this document")
puts result.value.last_text_content
```

### Parallel Execution

```ruby
network = RobotLab.create_network(name: "analysis", concurrency: :threads) do
  task :fetch, fetcher, depends_on: :none

  # Run in parallel
  task :sentiment, sentiment_bot, depends_on: [:fetch]
  task :entities, entity_bot, depends_on: [:fetch]

  # Wait for both
  task :merge, merger, depends_on: [:sentiment, :entities]
end
```

### Conditional Routing

There is no `Router` class and no `Router::Args`. Conditional routing is done by
subclassing `Robot`, overriding `#call`, and calling `result.activate(:task_name)`
for tasks declared `depends_on: :optional`:

```ruby
class ClassifierRobot < RobotLab::Robot
  def call(result)
    run_context  = extract_run_context(result)
    message      = run_context.delete(:message)   # must be positional
    robot_result = run(message, **run_context)

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    category = robot_result.last_text_content.to_s.downcase
    case category
    when /billing/ then new_result.activate(:billing)
    when /technical/ then new_result.activate(:technical)
    else new_result.activate(:general)
    end
  end
end

network = RobotLab.create_network(name: "support") do
  task :classifier, ClassifierRobot.new(name: "classifier", template: :classifier),
       depends_on: :none
  task :billing, billing_robot, depends_on: :optional
  task :technical, technical_robot, depends_on: :optional
  task :general, general_robot, depends_on: :optional
end

result = network.run(message: "I have a billing question")
puts result.value.last_text_content
```

### Accessing Task Results

```ruby
result = network.run(message: "Hello")

# Access individual task results
classifier_result = result.context[:classifier]
puts "Classification: #{classifier_result.last_text_content}"

# Check which optional task ran
if result.context[:billing]
  puts "Billing handled the request"
elsif result.context[:technical]
  puts "Technical handled the request"
end
```

## Runnable Protocol

`Network` includes `RobotLab::Runnable`, the shared interface it has in common with `Robot` — see [Runnable Protocol](../../architecture/network-orchestration.md#runnable-protocol) for the full picture.

| Method | Returns |
|--------|---------|
| `crew` | `robots.values` — the constituent robots, as an `Array`, in pipeline order |
| `chief` | `crew.first` — the lead robot |
| `robot_count` | `crew.size` |
| `network?` | `true` |
| `single?` | `false` |

```ruby
network.crew.map(&:name)  # => the ROBOTS' names, not the task keys
network.chief             # => the first robot
network.network?          # => true
```

`crew` returns `robots.values` — robot *instances*. So `crew.map(&:name)` yields
`robot.name` for each, which differs from `network.robots.keys` (task names)
unless each robot is named after its task.

## See Also

- [Creating Networks Guide](../../guides/creating-networks.md)
- [Network Orchestration](../../architecture/network-orchestration.md)
- [Robot](robot.md)
