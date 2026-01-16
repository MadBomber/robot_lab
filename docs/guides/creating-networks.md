# Creating Networks

Networks orchestrate multiple robots using [SimpleFlow](https://github.com/MadBomber/simple_flow) pipelines with DAG-based execution and optional step activation.

## Basic Network

Create a network with a sequential pipeline:

```ruby
network = RobotLab.create_network(name: "pipeline") do
  step :analyzer, analyzer_robot, depends_on: :none
  step :writer, writer_robot, depends_on: [:analyzer]
  step :reviewer, reviewer_robot, depends_on: [:writer]
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

## Adding Steps

### Sequential Steps

Each step depends on the previous:

```ruby
network = RobotLab.create_network(name: "pipeline") do
  step :first, robot1, depends_on: :none
  step :second, robot2, depends_on: [:first]
  step :third, robot3, depends_on: [:second]
end
```

### Parallel Steps

Steps with the same dependencies run in parallel:

```ruby
network = RobotLab.create_network(name: "parallel_analysis") do
  step :fetch, fetcher, depends_on: :none

  # These run in parallel after :fetch
  step :sentiment, sentiment_bot, depends_on: [:fetch]
  step :entities, entity_bot, depends_on: [:fetch]
  step :keywords, keyword_bot, depends_on: [:fetch]

  # This waits for all three to complete
  step :merge, merger, depends_on: [:sentiment, :entities, :keywords]
end
```

### Optional Steps

Optional steps only run when explicitly activated:

```ruby
network = RobotLab.create_network(name: "router") do
  step :classifier, classifier_robot, depends_on: :none
  step :billing, billing_robot, depends_on: :optional
  step :technical, technical_robot, depends_on: :optional
  step :general, general_robot, depends_on: :optional
end
```

## Conditional Routing

Use optional steps with custom Robot subclasses for intelligent routing:

```ruby
class ClassifierRobot < RobotLab::Robot
  def call(result)
    robot_result = run(**extract_run_context(result))

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
  step :classifier, classifier, depends_on: :none
  step :billing, billing_robot, depends_on: :optional
  step :technical, technical_robot, depends_on: :optional
  step :general, general_robot, depends_on: :optional
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

### Accessing Step Results

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

result.value      # The final step's output (RobotResult)
result.context    # Hash of all step results and metadata
result.halted?    # Whether execution was halted early
result.continued? # Whether execution continued normally
```

## Patterns

### Classifier Pattern

Route to specialists based on classification:

```ruby
class SupportClassifier < RobotLab::Robot
  def call(result)
    robot_result = run(**extract_run_context(result))
    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    category = robot_result.last_text_content.to_s.strip.downcase
    new_result.activate(category.to_sym)
  end
end

network = RobotLab.create_network(name: "support") do
  step :classifier, SupportClassifier.new(name: "classifier", template: :classifier),
       depends_on: :none
  step :billing, billing_robot, depends_on: :optional
  step :technical, technical_robot, depends_on: :optional
  step :general, general_robot, depends_on: :optional
end
```

### Pipeline Pattern

Process through sequential stages:

```ruby
network = RobotLab.create_network(name: "document_processor") do
  step :extract, extractor, depends_on: :none
  step :analyze, analyzer, depends_on: [:extract]
  step :format, formatter, depends_on: [:analyze]
end
```

### Fan-Out/Fan-In Pattern

Parallel processing with aggregation:

```ruby
network = RobotLab.create_network(name: "multi_analysis") do
  step :prepare, preparer, depends_on: :none

  # Fan-out: parallel analysis
  step :sentiment, sentiment_analyzer, depends_on: [:prepare]
  step :topics, topic_extractor, depends_on: [:prepare]
  step :entities, entity_recognizer, depends_on: [:prepare]

  # Fan-in: aggregate results
  step :aggregate, aggregator, depends_on: [:sentiment, :topics, :entities]
end
```

### Conditional Continuation

A robot can halt execution early:

```ruby
class ValidatorRobot < RobotLab::Robot
  def call(result)
    robot_result = run(**extract_run_context(result))

    if robot_result.last_text_content.include?("INVALID")
      # Stop the pipeline
      result.halt(robot_result)
    else
      # Continue to next step
      result
        .with_context(@name.to_sym, robot_result)
        .continue(robot_result)
    end
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
network.to_h              # => Hash representation
```

## Best Practices

### 1. Keep Robots Focused

Each robot should have a single responsibility:

```ruby
# Good: focused robots
step :classify, classifier, depends_on: :none
step :respond, responder, depends_on: [:classify]

# Bad: one robot doing everything
step :do_everything, mega_robot, depends_on: :none
```

### 2. Use Context for Data Passing

Access previous results via context:

```ruby
class ResponderRobot < RobotLab::Robot
  def call(result)
    # Get classifier's output
    classification = result.context[:classifier]&.last_text_content

    # Use it in this robot's run
    robot_result = run(
      **extract_run_context(result),
      classification: classification
    )

    result.with_context(@name.to_sym, robot_result).continue(robot_result)
  end
end
```

### 3. Handle Missing Results

Guard against missing optional step results:

```ruby
def call(result)
  # Check if optional step ran
  if result.context[:validator]
    # Use validator result
  else
    # Handle missing validation
  end
end
```

## Next Steps

- [Using Tools](using-tools.md) - Add capabilities to robots
- [Memory Guide](memory.md) - Persistent memory across runs
- [API Reference: Network](../api/core/network.md) - Complete API
