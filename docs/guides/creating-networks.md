# Creating Networks

Networks orchestrate multiple robots to accomplish complex workflows.

## Basic Network

Create a network with robots:

```ruby
network = RobotLab.create_network do
  name "customer_service"

  add_robot support_robot
  add_robot billing_robot
  add_robot technical_robot
end
```

## Network Properties

### Name

Identifies the network for logging and debugging:

```ruby
name "order_processing"
```

### Default Model

Model for robots that don't specify one:

```ruby
default_model "claude-sonnet-4"
```

### Max Iterations

Limit robot executions per run:

```ruby
max_iterations 10  # Default: 10
```

## Adding Robots

### Single Robot

```ruby
add_robot my_robot
```

### Multiple Robots

```ruby
add_robot classifier
add_robot handler_a
add_robot handler_b
add_robot summarizer
```

### Inline Robot Definition

```ruby
add_robot RobotLab.build {
  name "inline_helper"
  template "You help with simple tasks."
}
```

## Routing

The router determines which robot runs at each step.

### Simple Router

Run one robot:

```ruby
router ->(args) {
  args.call_count.zero? ? :assistant : nil
}
```

### Sequential Router

Run robots in order:

```ruby
SEQUENCE = [:intake, :process, :respond]

router ->(args) {
  idx = args.call_count
  idx < SEQUENCE.length ? SEQUENCE[idx] : nil
}
```

### Conditional Router

Route based on results:

```ruby
router ->(args) {
  case args.call_count
  when 0
    :classifier
  when 1
    # Route based on classification
    result = args.last_result&.output&.first&.content&.strip
    case result
    when "BILLING" then :billing_agent
    when "TECHNICAL" then :tech_agent
    when "SALES" then :sales_agent
    else :general_agent
    end
  when 2
    :summarizer  # Always summarize at end
  else
    nil
  end
}
```

### Router Arguments

```ruby
router ->(args) {
  args.call_count   # Number of router invocations
  args.network      # The NetworkRun
  args.context      # Run context (includes :message)
  args.stack        # Robots already scheduled
  args.last_result  # Previous robot's RobotResult
  args.message      # Shortcut for context[:message]
}
```

## Network-Level Configuration

### MCP Servers

```ruby
network = RobotLab.create_network do
  name "dev_tools"

  mcp [
    {
      name: "github",
      transport: { type: "stdio", command: "mcp-server-github" }
    },
    {
      name: "filesystem",
      transport: { type: "stdio", command: "mcp-server-fs", args: ["--root", "."] }
    }
  ]
end
```

### Tool Whitelist

```ruby
network = RobotLab.create_network do
  name "restricted"

  # Only these tools available to robots
  tools %w[read_file search_code]
end
```

## History Configuration

Enable conversation persistence:

```ruby
network = RobotLab.create_network do
  name "persistent_chat"

  history History::Config.new(
    create_thread: ->(state:, input:, **) {
      thread = ConversationThread.create!(initial_input: input.to_s)
      { thread_id: thread.id.to_s }
    },

    get: ->(thread_id:, **) {
      ConversationResult.where(thread_id: thread_id)
                        .order(:created_at)
                        .map(&:to_robot_result)
    },

    append_results: ->(thread_id:, new_results:, **) {
      new_results.each do |result|
        ConversationResult.create!(
          thread_id: thread_id,
          robot_name: result.robot_name,
          output_data: result.output.map(&:to_h),
          stop_reason: result.stop_reason
        )
      end
    }
  )
end
```

## Running Networks

### Basic Run

```ruby
state = RobotLab.create_state(message: "Help me with my order")
result = network.run(state: state)

# Get the final response
response = result.last_result.output.first.content
```

### With Custom Router

```ruby
result = network.run(
  state: state,
  router: ->(args) { args.call_count.zero? ? :assistant : nil }
)
```

### With Single Robot

```ruby
result = network.run(
  state: state,
  router: my_robot  # Robot used as router
)
```

### With Streaming

```ruby
result = network.run(
  state: state,
  streaming: ->(event) {
    puts "#{event[:event]}: #{event[:data]}"
  }
)
```

## NetworkRun Results

```ruby
run = network.run(state: state)

run.results        # All results (including loaded history)
run.new_results    # Only results from this run
run.last_result    # Most recent result
run.execution_state  # :completed, :failed, etc.
run.run_id         # Unique run identifier

run.to_h           # Hash representation
```

## Patterns

### Classifier Pattern

Route to specialists based on input classification:

```ruby
classifier = RobotLab.build do
  name "classifier"
  template <<~PROMPT
    Classify the request: BILLING, TECHNICAL, or GENERAL.
    Respond with only the category.
  PROMPT
end

specialists = {
  "BILLING" => billing_robot,
  "TECHNICAL" => tech_robot,
  "GENERAL" => general_robot
}

network = RobotLab.create_network do
  name "smart_router"
  add_robot classifier
  specialists.values.each { |r| add_robot r }

  router ->(args) {
    case args.call_count
    when 0 then :classifier
    when 1
      category = args.last_result&.output&.first&.content&.strip
      specialists[category]&.name || :general
    else nil
    end
  }
end
```

### Pipeline Pattern

Process through stages:

```ruby
network = RobotLab.create_network do
  name "document_processor"

  add_robot extractor      # Extract key info
  add_robot analyzer       # Analyze content
  add_robot formatter      # Format output

  router ->(args) {
    [:extractor, :analyzer, :formatter][args.call_count]
  }
end
```

### Fallback Pattern

Try primary, fall back if needed:

```ruby
router ->(args) {
  case args.call_count
  when 0
    :primary_agent
  when 1
    # Check if primary succeeded
    result = args.last_result
    if result&.output&.first&.content&.include?("I cannot help")
      :fallback_agent
    else
      nil  # Primary succeeded, done
    end
  else
    nil
  end
}
```

### Consensus Pattern

Get multiple opinions:

```ruby
network = RobotLab.create_network do
  name "consensus"

  add_robot analyst_1
  add_robot analyst_2
  add_robot analyst_3
  add_robot synthesizer

  router ->(args) {
    case args.call_count
    when 0..2
      [:analyst_1, :analyst_2, :analyst_3][args.call_count]
    when 3
      :synthesizer  # Combine all opinions
    else
      nil
    end
  }
end
```

## Best Practices

### 1. Keep Routers Simple

```ruby
# Good: Clear logic
router ->(args) {
  args.call_count.zero? ? :handler : nil
}

# Bad: Complex logic in router
router ->(args) {
  # 50 lines of business logic...
}
```

### 2. Use Memory for Data Passing

```ruby
# Instead of parsing results in router
router ->(args) {
  # Read from memory
  intent = args.network.state.memory.recall("user_intent")
  intent == "billing" ? :billing : :general
}
```

### 3. Handle Edge Cases

```ruby
router ->(args) {
  return nil if args.call_count > 5  # Safety limit

  result = args.last_result&.output&.first&.content
  return :fallback if result.nil?    # Handle missing result

  # Normal routing...
}
```

## Next Steps

- [Using Tools](using-tools.md) - Add capabilities to robots
- [History Guide](history.md) - Persist conversations
- [API Reference: Network](../api/core/network.md) - Complete API
