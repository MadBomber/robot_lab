# Streaming Responses

Stream LLM responses in real-time for better user experience.

## Basic Streaming

Pass a block to `robot.run` to receive streaming events:

```ruby
robot = RobotLab.build(
  name: "storyteller",
  system_prompt: "You are a creative storyteller."
)

robot.run("Tell me a story about a brave robot") do |event|
  puts event.inspect
end
```

## Event Types

### Text Deltas

Receive text as it is generated:

```ruby
robot.run("Tell me a story") do |event|
  if event[:event] == "text.delta"
    print event[:data][:content]
  end
end
```

### Tool Calls

Know when tools are being called:

```ruby
robot.run("What's the weather in Tokyo?") do |event|
  case event[:event]
  when "tool_call.start"
    puts "\nCalling: #{event[:data][:name]}"
  when "tool_call.complete"
    puts "Done: #{event[:data][:result]}"
  end
end
```

### Lifecycle Events

Track execution lifecycle:

```ruby
robot.run("Help me with my task") do |event|
  case event[:event]
  when "run.started"
    puts "Starting..."
  when "run.completed"
    puts "Completed!"
  when "run.failed"
    puts "Failed: #{event[:data][:error]}"
  end
end
```

## Event Reference

| Event | Description | Data |
|-------|-------------|------|
| `run.started` | Execution began | `run_id` |
| `run.completed` | Execution finished | `run_id` |
| `run.failed` | Error occurred | `run_id`, `error` |
| `text.delta` | Text content chunk | `content` |
| `tool_call.start` | Tool execution starting | `name`, `input` |
| `tool_call.complete` | Tool execution done | `name`, `result` |

## Comprehensive Event Handling

Handle all event types in a single block:

```ruby
robot.run("Analyze this data and generate a report") do |event|
  case event[:event]
  when "text.delta"
    print event[:data][:content]
  when "tool_call.start"
    puts "\n[Tool] Calling: #{event[:data][:name]}"
  when "tool_call.complete"
    puts "[Tool] Done: #{event[:data][:name]}"
  when "run.completed"
    puts "\n--- Complete ---"
  when "run.failed"
    puts "\n[Error] #{event[:data][:error]}"
  end
end
```

## Web Integration

### Rails Action Cable

```ruby
class ChatChannel < ApplicationCable::Channel
  def receive(data)
    robot = RobotLab.build(
      name: "chat_bot",
      system_prompt: "You are a helpful chat assistant."
    )

    robot.run(data["message"]) do |event|
      transmit(event)
    end
  end
end
```

### Server-Sent Events

```ruby
class StreamController < ApplicationController
  include ActionController::Live

  def create
    response.headers["Content-Type"] = "text/event-stream"

    robot = RobotLab.build(
      name: "stream_bot",
      system_prompt: "You are helpful."
    )

    robot.run(params[:message]) do |event|
      response.stream.write("data: #{event.to_json}\n\n")
    end
  ensure
    response.stream.close
  end
end
```

### WebSocket

```ruby
# Using Faye WebSocket
ws.on :message do |msg|
  robot.run(msg.data) do |event|
    ws.send(event.to_json)
  end
end
```

## Buffering

Buffer content for batch processing:

```ruby
buffer = []

robot.run("Generate a long response") do |event|
  if event[:event] == "text.delta"
    buffer << event[:data][:content]

    # Flush every 10 chunks
    if buffer.size >= 10
      process_batch(buffer.join)
      buffer.clear
    end
  end
end

# Final flush
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
    when "text.delta"
      @chars += event[:data][:content].length
      print "\rReceived #{@chars} characters..."
    when "tool_call.start"
      @tools += 1
      puts "\nTool call ##{@tools}: #{event[:data][:name]}"
    end
  end
end

progress = StreamProgress.new

robot.run("Process this complex request") do |event|
  progress.handle(event)
end
```

## Error Handling

Handle streaming errors gracefully:

```ruby
robot.run("Analyze this") do |event|
  case event[:event]
  when "run.failed"
    log_error(event[:data][:error])
    notify_user("An error occurred")
  when "text.delta"
    begin
      broadcast(event)
    rescue BroadcastError => e
      # Client disconnected, but continue processing
      logger.warn "Broadcast failed: #{e.message}"
    end
  end
end
```

## Without Streaming

When streaming is not needed, simply call `run` without a block:

```ruby
# No streaming - returns RobotResult directly
result = robot.run("Hello!")
puts result.last_text_content
```

## Best Practices

### 1. Handle All Event Types

```ruby
robot.run("Hello") do |event|
  case event[:event]
  when "text.delta" then handle_delta(event)
  when "tool_call.start" then show_tool_indicator(event)
  when "tool_call.complete" then hide_tool_indicator(event)
  when "run.completed" then finalize_response
  when "run.failed" then show_error(event)
  end
end
```

### 2. Provide User Feedback

```ruby
robot.run("Process my request") do |event|
  case event[:event]
  when "run.started"
    show_typing_indicator
  when "text.delta"
    update_message(event[:data][:content])
  when "tool_call.start"
    show_status("Looking up information...")
  when "run.completed"
    hide_typing_indicator
  end
end
```

### 3. Clean Up Resources

```ruby
begin
  robot.run("Hello") do |event|
    stream_to_client(event)
  end
ensure
  close_stream_connection
end
```

## Next Steps

- [Building Robots](building-robots.md) - Robot creation
- [Creating Networks](creating-networks.md) - Network patterns
- [API Reference: Streaming](../api/streaming/index.md) - Complete API
