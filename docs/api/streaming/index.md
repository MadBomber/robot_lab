# Streaming

A standalone event-publishing toolkit. **Not** the live streaming path.

## Status: not wired in

`RobotLab::Streaming::Context`, `Streaming::Events`, and
`Streaming::SequenceCounter` exist and work, but **nothing in the framework uses
them**. `grep -rn "Streaming::" lib/` returns zero hits outside
`lib/robot_lab/streaming/` itself: no robot, network, task, or hook ever
constructs a `Streaming::Context`, and no framework code publishes any of the
events listed below. Enabling this module does not make a robot stream.

Treat this as a set of building blocks you may drive yourself — a vocabulary of
event names plus a sequencing/ID helper — if you are writing your own
event-broadcast layer (a websocket relay, a SSE endpoint, an audit feed).

### The real streaming API

To actually receive tokens as a robot generates them, use `on_content:` and/or a
block on `run`:

```ruby
# Constructor / RunConfig callback — fires on every run
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are helpful.",
  on_content: ->(chunk) { print chunk.content }
)

# Or a block passed to run
robot.run("Tell me a story") { |chunk| print chunk.content }
```

Each callback receives a `RubyLLM::Chunk`. Use `chunk.content` — there is no
`chunk.text`. If both are supplied, both fire, with the stored `on_content`
first. `on_content` is read from the robot's own config at construction time; a
network-level `config:` does not supply it.

The config key `streaming_enabled` has zero consumers in `lib/` and does nothing.

## Overview

The module provides structured event publishing with automatic sequencing,
timestamping, and ID generation. Event names cover run lifecycle, content deltas
(token streaming), tool calls, and metadata updates, and contexts can be nested
so a network-level run and its child robot runs share one monotonic sequence.

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
| `SequenceCounter` | Thread-safe monotonic counter for event ordering. Its only consumer is `Streaming::Context`, which is itself unused by the framework |

## Event Categories

These are the names defined in `Streaming::Events`. They are constants and
classification helpers only — no framework code emits any of them.

| Category | Events | Description |
|----------|--------|-------------|
| Lifecycle | `run.started`, `run.completed`, `run.failed`, `run.interrupted` | Run-level state changes |
| Steps | `step.started`, `step.completed`, `step.failed` | Durable execution steps |
| Parts | `part.created`, `part.completed`, `part.failed` | Message composition parts |
| Deltas | `text.delta`, `tool_call.arguments.delta`, `tool_call.output.delta`, `reasoning.delta`, `data.delta` | Token-level content streaming |
| HITL | `hitl.requested`, `hitl.resolved` | Human-in-the-loop events |
| Metadata | `usage.updated`, `metadata.updated` | Token usage and metadata |
| Terminal | `stream.ended` | End of stream signal |

`DELTA_EVENTS` has five members — `tool_call.output.delta` is easy to miss.
`ALL_EVENTS` has twenty.

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

### Nested Contexts

Contexts can be nested to model a parent run with child runs sharing one
sequence. Note that no `Network` creates these — you would build the hierarchy
yourself.

```ruby
# Parent context for a run you are orchestrating
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
- [Robot](../core/robot.md) -- `on_content:`, and the block form of `run`, which is how streaming actually works
