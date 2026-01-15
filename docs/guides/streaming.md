# Streaming Responses

Stream LLM responses in real-time for better user experience.

## Basic Streaming

Pass a callback to receive streaming events:

```ruby
robot.run(
  state: state,
  network: network,
  streaming: ->(event) {
    puts event.inspect
  }
)
```

## Event Types

### Text Deltas

Receive text as it's generated:

```ruby
streaming: ->(event) {
  if event[:event] == "delta"
    print event[:data][:content]
  end
}
```

### Tool Calls

Know when tools are being called:

```ruby
streaming: ->(event) {
  case event[:event]
  when "tool_call.start"
    puts "\nCalling: #{event[:data][:name]}"
  when "tool_call.complete"
    puts "Done: #{event[:data][:result]}"
  end
}
```

### Lifecycle Events

Track execution lifecycle:

```ruby
streaming: ->(event) {
  case event[:event]
  when "run.started"
    puts "Starting run #{event[:data][:run_id]}"
  when "run.completed"
    puts "Completed!"
  when "run.failed"
    puts "Failed: #{event[:data][:error]}"
  end
}
```

## Event Reference

| Event | Description | Data |
|-------|-------------|------|
| `run.started` | Network run began | `run_id`, `network` |
| `run.completed` | Network run finished | `run_id`, `robot_count` |
| `run.failed` | Error occurred | `run_id`, `error` |
| `delta` | Text content chunk | `content` |
| `tool_call.start` | Tool execution starting | `name`, `input` |
| `tool_call.complete` | Tool execution done | `name`, `result` |

## Streaming Context

For advanced control, use `Streaming::Context`:

```ruby
context = RobotLab::Streaming::Context.new(
  run_id: SecureRandom.uuid,
  message_id: SecureRandom.uuid,
  scope: "network",
  publish: ->(event) { broadcast_to_client(event) }
)
```

### Context Properties

```ruby
context.run_id      # Unique run identifier
context.message_id  # Unique message identifier
context.scope       # "network" or "robot"
```

### Publishing Events

```ruby
context.publish_event(
  event: "custom.event",
  data: { key: "value" }
)
```

## Web Integration

### Rails Action Cable

```ruby
class ChatChannel < ApplicationCable::Channel
  def receive(data)
    state = RobotLab.create_state(message: data["message"])

    network.run(
      state: state,
      streaming: ->(event) {
        transmit(event)
      }
    )
  end
end
```

### Server-Sent Events

```ruby
class StreamController < ApplicationController
  include ActionController::Live

  def create
    response.headers["Content-Type"] = "text/event-stream"

    state = RobotLab.create_state(message: params[:message])

    network.run(
      state: state,
      streaming: ->(event) {
        response.stream.write("data: #{event.to_json}\n\n")
      }
    )
  ensure
    response.stream.close
  end
end
```

### WebSocket

```ruby
# Using Faye WebSocket
ws.on :message do |msg|
  state = RobotLab.create_state(message: msg.data)

  network.run(
    state: state,
    streaming: ->(event) {
      ws.send(event.to_json)
    }
  )
end
```

## Event Filtering

### Check Event Type

```ruby
streaming: ->(event) {
  return unless RobotLab::Streaming::Events.delta?(event)
  print event[:data][:content]
}
```

### Available Predicates

```ruby
Streaming::Events.lifecycle?(event)  # run.started, run.completed, etc.
Streaming::Events.delta?(event)       # Text content
Streaming::Events.valid?(event)       # Has required fields
```

## Buffering

Buffer content for batch processing:

```ruby
buffer = []

streaming: ->(event) {
  if event[:event] == "delta"
    buffer << event[:data][:content]

    # Flush every 10 chunks
    if buffer.size >= 10
      process_batch(buffer.join)
      buffer.clear
    end
  end
}

# Don't forget final flush
process_batch(buffer.join) if buffer.any?
```

## Progress Tracking

Track streaming progress:

```ruby
class StreamProgress
  def initialize
    @chars = 0
    @tools = 0
  end

  def handle(event)
    case event[:event]
    when "delta"
      @chars += event[:data][:content].length
      puts "\rReceived #{@chars} characters..."
    when "tool_call.start"
      @tools += 1
      puts "\nTool call ##{@tools}: #{event[:data][:name]}"
    end
  end
end

progress = StreamProgress.new
network.run(state: state, streaming: progress.method(:handle))
```

## Error Handling

Handle streaming errors gracefully:

```ruby
streaming: ->(event) {
  case event[:event]
  when "run.failed"
    log_error(event[:data][:error])
    notify_user("An error occurred")
  when "delta"
    begin
      broadcast(event)
    rescue BroadcastError => e
      # Client disconnected, but continue processing
      logger.warn "Broadcast failed: #{e.message}"
    end
  end
}
```

## Disabling Streaming

Disable streaming when not needed:

```ruby
RobotLab.configure do |config|
  config.streaming_enabled = false
end

# Or per-run
network.run(state: state, streaming: nil)
```

## Best Practices

### 1. Handle All Event Types

```ruby
streaming: ->(event) {
  case event[:event]
  when "delta" then handle_delta(event)
  when "tool_call.start" then show_tool_indicator(event)
  when "tool_call.complete" then hide_tool_indicator(event)
  when "run.completed" then finalize_response
  when "run.failed" then show_error(event)
  end
}
```

### 2. Provide User Feedback

```ruby
streaming: ->(event) {
  case event[:event]
  when "run.started"
    show_typing_indicator
  when "delta"
    update_message(event[:data][:content])
  when "tool_call.start"
    show_status("Looking up information...")
  when "run.completed"
    hide_typing_indicator
  end
}
```

### 3. Clean Up Resources

```ruby
begin
  network.run(state: state, streaming: callback)
ensure
  close_stream_connection
end
```

## Next Steps

- [Building Robots](building-robots.md) - Robot creation
- [Creating Networks](creating-networks.md) - Network patterns
- [API Reference: Streaming](../api/streaming/index.md) - Complete API
