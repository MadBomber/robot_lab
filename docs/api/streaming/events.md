# Streaming::Events

Event type constants and classification helpers for the streaming system.

## Module: `RobotLab::Streaming::Events`

Defines all recognized event types as string constants and provides helper methods for classifying events.

```ruby
RobotLab::Streaming::Events::TEXT_DELTA       # => "text.delta"
RobotLab::Streaming::Events::RUN_COMPLETED    # => "run.completed"
RobotLab::Streaming::Events.delta?("text.delta")  # => true
```

## Event Type Constants

### Run Lifecycle Events

| Constant | Value | Description |
|----------|-------|-------------|
| `RUN_STARTED` | `"run.started"` | A run has begun |
| `RUN_COMPLETED` | `"run.completed"` | A run completed successfully |
| `RUN_FAILED` | `"run.failed"` | A run failed with an error |
| `RUN_INTERRUPTED` | `"run.interrupted"` | A run was interrupted |

### Step Events

For durable execution tracking:

| Constant | Value | Description |
|----------|-------|-------------|
| `STEP_STARTED` | `"step.started"` | A processing step has begun |
| `STEP_COMPLETED` | `"step.completed"` | A processing step completed |
| `STEP_FAILED` | `"step.failed"` | A processing step failed |

### Part Events

For message composition tracking:

| Constant | Value | Description |
|----------|-------|-------------|
| `PART_CREATED` | `"part.created"` | A message part was created |
| `PART_COMPLETED` | `"part.completed"` | A message part completed |
| `PART_FAILED` | `"part.failed"` | A message part failed |

### Content Delta Events

Token-level streaming events:

| Constant | Value | Description |
|----------|-------|-------------|
| `TEXT_DELTA` | `"text.delta"` | A chunk of text content was generated |
| `TOOL_CALL_ARGUMENTS_DELTA` | `"tool_call.arguments.delta"` | A chunk of tool call arguments |
| `TOOL_CALL_OUTPUT_DELTA` | `"tool_call.output.delta"` | A chunk of tool call output |
| `REASONING_DELTA` | `"reasoning.delta"` | A chunk of reasoning/thinking content |
| `DATA_DELTA` | `"data.delta"` | A chunk of structured data |

### Human-in-the-Loop Events

| Constant | Value | Description |
|----------|-------|-------------|
| `HITL_REQUESTED` | `"hitl.requested"` | Human input has been requested |
| `HITL_RESOLVED` | `"hitl.resolved"` | Human input has been provided |

### Metadata Events

| Constant | Value | Description |
|----------|-------|-------------|
| `USAGE_UPDATED` | `"usage.updated"` | Token usage statistics updated |
| `METADATA_UPDATED` | `"metadata.updated"` | Run metadata updated |

### Terminal Event

| Constant | Value | Description |
|----------|-------|-------------|
| `STREAM_ENDED` | `"stream.ended"` | The stream has ended; no more events |

## Event Collections

### ALL_EVENTS

```ruby
RobotLab::Streaming::Events::ALL_EVENTS
# => Array of all event type strings (frozen)
```

### LIFECYCLE_EVENTS

```ruby
RobotLab::Streaming::Events::LIFECYCLE_EVENTS
# => ["run.started", "run.completed", "run.failed", "run.interrupted"]
```

### DELTA_EVENTS

```ruby
RobotLab::Streaming::Events::DELTA_EVENTS
# => ["text.delta", "tool_call.arguments.delta", "tool_call.output.delta",
#     "reasoning.delta", "data.delta"]
```

## Classification Methods

### Events.lifecycle?

```ruby
RobotLab::Streaming::Events.lifecycle?("run.started")   # => true
RobotLab::Streaming::Events.lifecycle?("text.delta")     # => false
```

Returns `true` if the event is a run lifecycle event.

### Events.delta?

```ruby
RobotLab::Streaming::Events.delta?("text.delta")         # => true
RobotLab::Streaming::Events.delta?("run.completed")      # => false
```

Returns `true` if the event is a content delta (token streaming) event.

### Events.valid?

```ruby
RobotLab::Streaming::Events.valid?("text.delta")         # => true
RobotLab::Streaming::Events.valid?("unknown.event")      # => false
```

Returns `true` if the event is a recognized event type.

## Examples

### Filtering Events by Category

```ruby
publish = ->(event) {
  event_type = event[:event]

  if RobotLab::Streaming::Events.delta?(event_type)
    # Handle streaming content
    print event[:data][:delta]
  elsif RobotLab::Streaming::Events.lifecycle?(event_type)
    # Handle lifecycle transitions
    puts "\n[#{event_type}] run_id=#{event[:data][:run_id]}"
  end
}
```

### Using Constants for Event Matching

```ruby
include RobotLab::Streaming::Events

publish = ->(event) {
  case event[:event]
  when TEXT_DELTA
    print event[:data][:delta]
  when TOOL_CALL_ARGUMENTS_DELTA
    buffer_tool_args(event[:data])
  when RUN_COMPLETED
    puts "\nRun complete"
  when RUN_FAILED
    puts "\nRun failed: #{event[:data][:error]}"
  when STREAM_ENDED
    cleanup
  end
}
```

### Validating Custom Events

```ruby
def emit(event_type, data)
  unless RobotLab::Streaming::Events.valid?(event_type)
    raise ArgumentError, "Unknown event type: #{event_type}"
  end

  context.publish_event(event: event_type, data: data)
end
```

## See Also

- [Streaming Overview](index.md)
- [Context](context.md)
