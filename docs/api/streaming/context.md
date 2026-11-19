# Streaming::Context

Manages streaming event publishing with automatic sequencing, timestamping, and ID generation.

> **Not wired into the framework.** No robot, network, task, or hook ever
> constructs a `Streaming::Context` — `grep -rn "Streaming::" lib/` finds nothing
> outside `lib/robot_lab/streaming/`. The class works, but it only publishes what
> *you* hand it. For token streaming from a robot, use `on_content:` or the block
> form of `run`; see the [Streaming overview](index.md#the-real-streaming-api).

## Class: `RobotLab::Streaming::Context`

```ruby
context = RobotLab::Streaming::Context.new(
  run_id: "run_123",
  message_id: "msg_456",
  scope: "network",
  publish: ->(event) { broadcast(event) }
)

context.publish_event(event: "text.delta", data: { delta: "Hello" })
```

## Constructor

```ruby
Context.new(
  run_id:,
  message_id:,
  scope:,
  publish:,
  parent_run_id: nil,
  sequence_counter: nil
)
```

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `run_id` | `String` | required | Unique identifier for this run |
| `message_id` | `String` | required | Current message identifier |
| `scope` | `String`, `Symbol` | required | Context scope (e.g., `"network"`, `"robot"`) |
| `publish` | `Proc` | required | Callback invoked with each event hash |
| `parent_run_id` | `String`, `nil` | `nil` | Parent run identifier for nested contexts |
| `sequence_counter` | `SequenceCounter`, `nil` | `nil` | Shared sequence counter (creates new one if nil) |

## Attributes

### run_id

```ruby
context.run_id  # => String
```

The unique run identifier for this context.

### parent_run_id

```ruby
context.parent_run_id  # => String | nil
```

The parent run identifier. Set when this is a child context created by `create_child_context`.

### message_id

```ruby
context.message_id  # => String
```

The current message identifier.

### scope

```ruby
context.scope  # => String
```

The context scope (converted to string). Typically `"network"` or `"robot"`.

## Methods

### publish_event

```ruby
chunk = context.publish_event(event:, data: {})
```

Publish a streaming event. The event is wrapped in a chunk with automatic sequencing, timestamping, and context metadata injection.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `event` | `String` | Event type (e.g., `"text.delta"`, `"run.started"`) |
| `data` | `Hash` | Event payload (default: `{}`) |

**Returns:** The constructed event chunk hash.

The chunk structure:

```ruby
{
  event: "text.delta",
  data: {
    delta: "Hello",          # from data parameter
    run_id: "run_123",       # injected from context
    message_id: "msg_456",   # injected from context
    scope: "robot"           # injected from context
  },
  timestamp: 1707900000000,  # millisecond Unix timestamp
  sequence_number: 1,        # monotonically increasing
  id: "publish-1:text.delta" # unique event ID
}
```

If the publish callback raises an error, it is caught and logged as a warning via `RobotLab.config.logger`. The chunk is still returned.

### create_child_context

```ruby
child = context.create_child_context(robot_run_id)
```

Create a child context for a nested robot execution. The child shares the same publish callback and sequence counter, ensuring events are ordered globally across the parent and child.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `robot_run_id` | `String` | Run ID for the child context |

**Returns:** A new `Context` with:
- `run_id` set to `robot_run_id`
- `parent_run_id` set to the current context's `run_id`
- `scope` set to `"robot"`
- A new `message_id` (generated UUID)
- Shared `sequence_counter` and `publish` callback

### create_context_with_shared_sequence

```ruby
sibling = context.create_context_with_shared_sequence(
  run_id: "run_789",
  message_id: "msg_789",
  scope: "robot"
)
```

Create a new context that shares the same sequence counter as this context, but with different identifiers.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `run_id` | `String` | Run ID for the new context |
| `message_id` | `String` | Message ID for the new context |
| `scope` | `String` | Scope for the new context |

**Returns:** A new `Context` sharing the sequence counter and publish callback.

### generate_part_id

```ruby
context.generate_part_id  # => "part_37ac1d49_815007_8f522876"
```

Generate an OpenAI-compatible part ID (max 40 characters), assembled as
`"part_<msg>_<ts>_<rand>"`:

| Segment | Source | Length |
|---------|--------|--------|
| `<msg>` | First 8 characters of **`message_id`** (not `run_id`) | 8 |
| `<ts>` | Last 6 digits of the millisecond Unix timestamp | 6 |
| `<rand>` | `SecureRandom.hex(4)` | 8 hex chars |

Note this reads `message_id`, so two contexts sharing a message produce IDs with
the same first segment.

### generate_step_id

```ruby
context.generate_step_id("text_output")  # => "publish-3:text_output"
```

Generate a step ID for durable execution compatibility, formatted as
`"publish-<n>:<base_name>"`. It reads the counter with `current`, which does
**not** increment: `<n>` is the sequence number of the most recently published
event (`0` before anything has been published), so calling it repeatedly between
publishes yields the same ID.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `base_name` | `String` | Base name for the step |

### generate_message_id

```ruby
context.generate_message_id  # => "a1b2c3d4-..."
```

Generate a new UUID for use as a message identifier.

## Examples

### Basic Event Publishing

```ruby
publish = ->(event) {
  puts "[#{event[:event]}] #{event[:data]}"
}

context = RobotLab::Streaming::Context.new(
  run_id: SecureRandom.uuid,
  message_id: SecureRandom.uuid,
  scope: "robot",
  publish: publish
)

context.publish_event(event: "run.started", data: { robot_name: "assistant" })
context.publish_event(event: "text.delta", data: { delta: "Hello " })
context.publish_event(event: "text.delta", data: { delta: "world!" })
context.publish_event(event: "run.completed", data: {})
```

### Modelling a Multi-Robot Run with Child Contexts

`RobotLab::Network` does not do any of this for you — the nesting below is
something you would write by hand around your own orchestration.

```ruby
# Parent context
network_ctx = RobotLab::Streaming::Context.new(
  run_id: "net_run_1",
  message_id: "net_msg_1",
  scope: "network",
  publish: ->(e) { stream_to_client(e) }
)

network_ctx.publish_event(event: "run.started", data: {})

# Robot 1 executes
robot1_ctx = network_ctx.create_child_context("robot1_run_1")
robot1_ctx.publish_event(event: "step.started", data: { robot: "classifier" })
robot1_ctx.publish_event(event: "text.delta", data: { delta: "Category: billing" })
robot1_ctx.publish_event(event: "step.completed", data: { robot: "classifier" })

# Robot 2 executes (sequence numbers continue from robot 1)
robot2_ctx = network_ctx.create_child_context("robot2_run_1")
robot2_ctx.publish_event(event: "step.started", data: { robot: "responder" })
robot2_ctx.publish_event(event: "text.delta", data: { delta: "I can help with that." })
robot2_ctx.publish_event(event: "step.completed", data: { robot: "responder" })

network_ctx.publish_event(event: "run.completed", data: {})
```

### Error-Safe Publishing

```ruby
# Errors in the publish callback are caught and logged,
# so streaming failures do not interrupt execution.
context = RobotLab::Streaming::Context.new(
  run_id: "run_1",
  message_id: "msg_1",
  scope: "robot",
  publish: ->(e) { raise "connection lost" }
)

# This does not raise -- the error is logged via RobotLab.config.logger
chunk = context.publish_event(event: "text.delta", data: { delta: "test" })
# chunk is still returned with the event data
```

## See Also

- [Streaming Overview](index.md)
- [Events](events.md)
