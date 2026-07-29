# Network

Orchestrates multiple robots using SimpleFlow pipelines with DAG-based execution.

## Class: `RobotLab::Network`

```ruby
network = RobotLab.create_network(name: "support", config: config) do
  task :classifier, classifier_robot, depends_on: :none
  task :billing, billing_robot, depends_on: :optional
end
```

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

Hash of robots keyed by name.

### config

```ruby
network.config  # => RunConfig
```

Shared operational defaults for all robots in the network. Passed to robots during `run()` so they can inherit network-wide LLM settings. See [RunConfig](../../getting-started/configuration.md#runconfig-shared-operational-defaults).

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

**Returns:** `SimpleFlow::Result`

### task

```ruby
network.task(name, robot, context: {}, mcp: :none, tools: :none, memory: nil, config: nil, depends_on: :none)
# => self
```

Add a task to the pipeline with optional per-task configuration.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `name` | `Symbol` | Task identifier |
| `robot` | `Robot` | Robot instance to execute |
| `context` | `Hash` | Task-specific context (deep-merged with run params) |
| `mcp` | `:none`, Array | MCP server config (`:none` or array of servers) |
| `tools` | `:none`, Array | Tools config (`:none` or array of tools) |
| `memory` | `Memory`, `nil` | Task-specific memory |
| `config` | `RunConfig`, `nil` | Per-task config (merged on top of network's RunConfig) |
| `depends_on` | `:none`, `Array<Symbol>`, `:optional` | Task dependencies |

**Dependency Types:**

| Value | Description |
|-------|-------------|
| `:none` | No dependencies, runs first |
| `[:task1, :task2]` | Waits for listed tasks to complete |
| `:optional` | Only runs when explicitly activated |

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
  robots: ["classifier", "billing", "technical"],
  tasks: ["classifier", "billing", "technical"],
  optional_tasks: [:billing, :technical],
  config: { model: "claude-sonnet-4", temperature: 0.7 }  # if set
}
```

## SimpleFlow::Result

When `run` is called, a `SimpleFlow::Result` is returned:

### Attributes

```ruby
result.value      # Final task's output (RobotResult)
result.context    # Hash of all task results
result.halted?    # Whether execution stopped early
result.continued? # Whether execution continues
```

### Context Structure

```ruby
result.context[:run_params]   # Original run parameters
result.context[:classifier]   # Classifier robot's RobotResult
result.context[:billing]      # Billing robot's RobotResult (if activated)
```

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
       tools: [DebugTool, LogTool],
       depends_on: :optional
end
```

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

```ruby
class ClassifierRobot < RobotLab::Robot
  def call(result)
    robot_result = run(**extract_run_context(result))

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
network.crew.map(&:name)  # => ["classifier", "billing", "technical"]
network.chief             # => the first robot
network.network?          # => true
```

## See Also

- [Creating Networks Guide](../../guides/creating-networks.md)
- [Network Orchestration](../../architecture/network-orchestration.md)
- [Robot](robot.md)
