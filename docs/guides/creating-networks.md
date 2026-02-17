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

# Access individual robot results
classifier_result = result.context[:classifier]
billing_result = result.context[:billing]

# Original run parameters
original_params = result.context[:run_params]
```

## SimpleFlow::Result

Networks return a `SimpleFlow::Result` object:

```ruby
result = network.run(message: "Hello")

result.value      # The final task's output (RobotResult)
result.context    # Hash of all task results and metadata
result.halted?    # Whether execution was halted early
result.continued? # Whether execution continued normally
```

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
    # Get classifier's output
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
network.robots            # => Hash of name => Robot
network.robot(:billing)   # => Robot instance
network["billing"]        # => Robot instance (alias)
network.available_robots  # => Array of Robot instances
network.memory            # => Memory instance (shared)
network.to_h              # => Hash representation
```

## Configuration Inheritance

Networks accept a `config:` parameter that establishes default LLM settings for all member robots. This is useful when you want consistent behavior across a pipeline without configuring each robot individually.

### Network-Wide Defaults

```ruby
# All robots in this network use the same model and temperature
shared = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.5)

network = RobotLab.create_network(name: "pipeline", config: shared) do
  task :analyzer, analyzer_robot, depends_on: :none
  task :writer, writer_robot, depends_on: [:analyzer]
  task :reviewer, reviewer_robot, depends_on: [:writer]
end
```

### Per-Task Overrides

Individual tasks can override the network's config with their own `config:`:

```ruby
creative_config = RobotLab::RunConfig.new(temperature: 0.9)

network = RobotLab.create_network(name: "pipeline", config: shared) do
  task :analyzer, analyzer_robot, depends_on: :none
  task :writer, writer_robot,
       config: creative_config,  # writer gets higher temperature
       depends_on: [:analyzer]
  task :reviewer, reviewer_robot, depends_on: [:writer]
end
```

### Inheritance Chain

The full configuration hierarchy (most-specific wins):

```
RobotLab.config (global)
  -> Network config
    -> Task config
      -> Robot config (from constructor)
        -> Template front matter
          -> Constructor kwargs (model:, temperature:, etc.)
```

Each layer only overrides values it explicitly sets. Unset values pass through from the parent.

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
  # Check if optional task ran
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
