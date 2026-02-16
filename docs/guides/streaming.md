# Streaming Responses

Stream LLM responses in real-time for better user experience.

## Streaming via Callbacks

RobotLab robots support streaming through callback methods inherited from RubyLLM::Agent. Register callbacks before calling `run`:

```ruby
robot = RobotLab.build(
  name: "storyteller",
  system_prompt: "You are a creative storyteller."
)

# Register streaming callback
robot.on_new_message do |message|
  print message.content if message.content
end

result = robot.run("Tell me a story about a brave robot")
```

## Available Callbacks

### on_new_message

Called when the assistant starts generating a new message, with streaming chunks:

```ruby
robot.on_new_message do |message|
  print message.content if message.content
end
```

### on_end_message

Called when the assistant finishes a message:

```ruby
robot.on_end_message do |message|
  puts "\n--- Response complete ---"
  puts "Content length: #{message.content&.length}"
end
```

### on_tool_call

Called when the LLM invokes a tool:

```ruby
robot.on_tool_call do |tool_call|
  puts "Calling tool: #{tool_call.name}"
end
```

### on_tool_result

Called when a tool returns its result:

```ruby
robot.on_tool_result do |tool_call, result|
  puts "Tool #{tool_call.name} returned: #{result}"
end
```

## Comprehensive Callback Setup

Register all callbacks for full visibility:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are helpful.",
  local_tools: [WeatherTool]
)

robot.on_new_message do |message|
  print message.content if message.content
end

robot.on_end_message do |_message|
  puts "\n--- Done ---"
end

robot.on_tool_call do |tool_call|
  puts "\n[Tool] Calling: #{tool_call.name}"
end

robot.on_tool_result do |tool_call, result|
  puts "[Tool] #{tool_call.name} returned: #{result}"
end

result = robot.run("What's the weather in Tokyo?")
```

## Streaming via Chat Block

For more control, pass a block directly to `chat.ask` (the underlying RubyLLM method):

```ruby
robot = RobotLab.build(
  name: "chat_bot",
  system_prompt: "You are a helpful assistant."
)

# Use the underlying chat directly with a streaming block
robot.chat.ask("Tell me a story") do |chunk|
  print chunk.content if chunk.content
end
```

Note: Using `chat.ask` directly bypasses Robot's memory resolution and tool hierarchy. Use callbacks with `robot.run` when you need those features.

## Web Integration

### Rails Action Cable

```ruby
class ChatChannel < ApplicationCable::Channel
  def receive(data)
    robot = RobotLab.build(
      name: "chat_bot",
      system_prompt: "You are a helpful chat assistant."
    )

    robot.on_new_message do |message|
      transmit({ event: "text.delta", content: message.content }) if message.content
    end

    robot.on_end_message do |_message|
      transmit({ event: "run.completed" })
    end

    robot.run(data["message"])
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

    robot.on_new_message do |message|
      response.stream.write("data: #{message.content}\n\n") if message.content
    end

    robot.on_end_message do |_message|
      response.stream.write("data: [DONE]\n\n")
    end

    robot.run(params[:message])
  ensure
    response.stream.close
  end
end
```

### WebSocket

```ruby
# Using Faye WebSocket
ws.on :message do |msg|
  robot.on_new_message do |message|
    ws.send(message.content) if message.content
  end

  robot.run(msg.data)
end
```

## Progress Tracking

Track streaming progress with callbacks:

```ruby
class StreamProgress
  def initialize
    @chars = 0
    @tools = 0
  end

  attr_reader :chars, :tools

  def attach(robot)
    robot.on_new_message do |message|
      @chars += message.content.length if message.content
      print "\rReceived #{@chars} characters..."
    end

    robot.on_tool_call do |tool_call|
      @tools += 1
      puts "\nTool call ##{@tools}: #{tool_call.name}"
    end
  end
end

progress = StreamProgress.new
progress.attach(robot)

result = robot.run("Process this complex request")
puts "\nTotal: #{progress.chars} chars, #{progress.tools} tool calls"
```

## Without Streaming

When streaming is not needed, simply call `run` without registering callbacks:

```ruby
# No streaming - returns RobotResult directly
result = robot.run("Hello!")
puts result.last_text_content
```

## Best Practices

### 1. Register Callbacks Before Run

```ruby
# Correct: register first, then run
robot.on_new_message { |msg| print msg.content if msg.content }
robot.run("Hello")
```

### 2. Handle Errors in Callbacks

```ruby
robot.on_new_message do |message|
  begin
    broadcast(message.content) if message.content
  rescue BroadcastError => e
    # Client disconnected, but continue processing
    logger.warn "Broadcast failed: #{e.message}"
  end
end
```

### 3. Clean Up Resources

```ruby
begin
  robot.on_new_message do |message|
    stream_to_client(message.content) if message.content
  end
  robot.run("Hello")
ensure
  close_stream_connection
end
```

## Next Steps

- [Building Robots](building-robots.md) - Robot creation
- [Creating Networks](creating-networks.md) - Network patterns
- [API Reference: Streaming](../api/streaming/index.md) - Complete API
