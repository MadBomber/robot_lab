# Streaming

Real-time event streaming during robot and network execution.

## Overview

The streaming system provides structured event publishing during LLM execution. Events are emitted for run lifecycle, content deltas (token streaming), tool calls, and metadata updates. The system supports nested contexts for network-level orchestration where multiple robots execute within a single run.

```ruby
publish = ->(event) {
  case event[:event]
  when "text.delta"
    print event[:data][:delta]
  when "run.completed"
    puts "\nDone!"
  end
}

context = RobotLab::Streaming::Context.new(
  run_id: SecureRandom.uuid,
  message_id: SecureRandom.uuid,
  scope: "robot",
  publish: publish
)

context.publish_event(event: "text.delta", data: { delta: "Hello" })
```

## Components

| Component | Description |
|-----------|-------------|
| [Context](context.md) | Manages streaming state, sequencing, and event publishing |
| [Events](events.md) | Event type constants and classification helpers |

Also used internally:

| Component | Description |
|-----------|-------------|
| `SequenceCounter` | Thread-safe monotonic counter for event ordering |

## Event Categories

| Category | Events | Description |
|----------|--------|-------------|
| Lifecycle | `run.started`, `run.completed`, `run.failed`, `run.interrupted` | Run-level state changes |
| Steps | `step.started`, `step.completed`, `step.failed` | Durable execution steps |
| Parts | `part.created`, `part.completed`, `part.failed` | Message composition parts |
| Deltas | `text.delta`, `tool_call.arguments.delta`, `reasoning.delta`, `data.delta` | Token-level content streaming |
| HITL | `hitl.requested`, `hitl.resolved` | Human-in-the-loop events |
| Metadata | `usage.updated`, `metadata.updated` | Token usage and metadata |
| Terminal | `stream.ended` | End of stream signal |

## Event Structure

Each published event is a hash with the following shape:

```ruby
{
  event: "text.delta",           # Event type string
  data: {                        # Event payload (merged with context info)
    delta: "Hello",              #   Custom data
    run_id: "run_123",           #   Injected by context
    message_id: "msg_456",       #   Injected by context
    scope: "robot"               #   Injected by context
  },
  timestamp: 1707900000000,      # Millisecond Unix timestamp
  sequence_number: 1,            # Monotonically increasing
  id: "publish-1:text.delta"     # Unique event ID
}
```

## Quick Start

### Publishing Events

```ruby
context = RobotLab::Streaming::Context.new(
  run_id: "run_123",
  message_id: "msg_456",
  scope: "network",
  publish: ->(event) { broadcast(event) }
)

context.publish_event(event: "run.started", data: { robot_name: "assistant" })
context.publish_event(event: "text.delta", data: { delta: "Hello " })
context.publish_event(event: "text.delta", data: { delta: "world!" })
context.publish_event(event: "run.completed", data: {})
```

### Nested Contexts for Networks

```ruby
# Parent context for the network run
network_context = RobotLab::Streaming::Context.new(
  run_id: "network_run_1",
  message_id: "msg_1",
  scope: "network",
  publish: ->(event) { stream_to_client(event) }
)

# Child context for each robot (shares the sequence counter)
robot_context = network_context.create_child_context("robot_run_1")
robot_context.publish_event(event: "text.delta", data: { delta: "Response" })
```

## See Also

- [Context](context.md)
- [Events](events.md)
