# Network Orchestration

Networks coordinate multiple robots using [SimpleFlow](https://github.com/MadBomber/simple_flow) pipelines for DAG-based execution.

## Network Structure

A network is a thin wrapper around `SimpleFlow::Pipeline`:

- **Pipeline**: DAG-based execution engine
- **Robots**: Named collection of step handlers
- **Steps**: Define dependencies and execution order

```ruby
network = RobotLab.create_network(name: "customer_service") do
  step :classifier, classifier_robot, depends_on: :none
  step :billing, billing_robot, depends_on: :optional
  step :technical, technical_robot, depends_on: :optional
end
```

## Execution Model

```mermaid
stateDiagram-v2
    [*] --> Start
    Start --> ExecuteStep: next ready step
    ExecuteStep --> CheckDependents: step complete
    CheckDependents --> ExecuteStep: more steps ready
    CheckDependents --> Complete: all steps done
    ExecuteStep --> Halted: step halts
    Complete --> [*]
    Halted --> [*]
```

### Step Dependency Types

| Type | Description |
|------|-------------|
| `:none` | No dependencies, runs first |
| `[:step1, :step2]` | Waits for listed steps |
| `:optional` | Only runs when activated |

## Robot#call Interface

Each robot implements the SimpleFlow step interface:

```ruby
class Robot
  def call(result)
    # Run the LLM
    robot_result = run(**extract_run_context(result))

    # Return new result with context
    result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)
  end
end
```

### Result Methods

| Method | Description |
|--------|-------------|
| `continue(value)` | Continue to next steps |
| `halt(value)` | Stop pipeline execution |
| `with_context(key, val)` | Add data to context |
| `activate(step_name)` | Enable optional step |

## SimpleFlow::Result

The result object flows through the pipeline:

```ruby
result.value      # Current step's output
result.context    # Accumulated context from all steps
result.halted?    # Whether execution stopped early
result.continued? # Whether execution continues
```

### Context Structure

```ruby
{
  run_params: { message: "...", customer_id: 123 },
  classifier: RobotResult,
  billing: RobotResult,
  # ... other step results
}
```

## Optional Step Activation

Optional steps don't run automatically. They must be activated:

```ruby
class ClassifierRobot < RobotLab::Robot
  def call(result)
    robot_result = run(**extract_run_context(result))

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    # Analyze output and activate appropriate step
    category = robot_result.last_text_content.to_s.downcase

    case category
    when /billing/
      new_result.activate(:billing)
    when /technical/
      new_result.activate(:technical)
    else
      new_result.activate(:general)
    end
  end
end
```

## Parallel Execution

Steps with the same dependencies can run in parallel:

```ruby
network = RobotLab.create_network(name: "analysis", concurrency: :threads) do
  step :fetch, fetcher, depends_on: :none

  # These three run in parallel
  step :sentiment, sentiment_bot, depends_on: [:fetch]
  step :entities, entity_bot, depends_on: [:fetch]
  step :keywords, keyword_bot, depends_on: [:fetch]

  # Waits for all three
  step :merge, merger, depends_on: [:sentiment, :entities, :keywords]
end
```

### Concurrency Modes

| Mode | Description |
|------|-------------|
| `:auto` | SimpleFlow chooses best mode |
| `:threads` | Use Ruby threads |
| `:async` | Use async/fiber |

## Data Flow

1. **Initial Value**: `network.run(**params)` creates initial result
2. **Run Params**: Stored in `result.context[:run_params]`
3. **Step Results**: Each step adds to context
4. **Final Value**: Last step's output becomes `result.value`

```ruby
# Run with context
result = network.run(
  message: "Help with billing",
  customer_id: 123
)

# Access the flow
result.context[:run_params]  # { message: "...", customer_id: 123 }
result.context[:classifier]  # First robot's RobotResult
result.context[:billing]     # Billing robot's RobotResult
result.value                 # Final RobotResult
```

## Visualization

Networks provide visualization methods:

```ruby
# ASCII representation
puts network.visualize

# Mermaid diagram
puts network.to_mermaid

# Execution plan description
puts network.execution_plan
```

## Network Configuration

```ruby
network = RobotLab.create_network(
  name: "support",
  concurrency: :threads  # :auto, :threads, or :async
) do
  step :classifier, classifier, depends_on: :none
  step :handler, handler, depends_on: [:classifier]
end
```

## Next Steps

- [Creating Networks](../guides/creating-networks.md) - Practical patterns
- [Robot Execution](robot-execution.md) - How robots process messages
- [API Reference: Network](../api/core/network.md) - Complete API
