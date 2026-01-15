# Streaming

Real-time response streaming from LLM providers.

## Overview

Streaming allows you to receive LLM responses in real-time, token by token, enabling responsive user interfaces and progressive content display.

```ruby
result = robot.run(state: state) do |event|
  case event.type
  when :text_delta
    print event.text
  when :tool_call
    puts "\nCalling tool: #{event.name}"
  when :complete
    puts "\nDone!"
  end
end
```

## Components

| Component | Description |
|-----------|-------------|
| [Context](context.md) | Streaming context and state |
| [Events](events.md) | Event types and handling |

## Quick Start

### Basic Streaming

```ruby
robot.run(state: state) do |event|
  print event.text if event.type == :text_delta
end
```

### With Network

```ruby
network.run(state: state) do |event|
  case event.type
  when :robot_start
    puts "Robot #{event.robot_name} starting..."
  when :text_delta
    print event.text
  when :robot_complete
    puts "\nRobot #{event.robot_name} complete"
  end
end
```

## Event Types

| Event | Description |
|-------|-------------|
| `:start` | Streaming started |
| `:text_delta` | Text chunk received |
| `:tool_call` | Tool being called |
| `:tool_result` | Tool result received |
| `:robot_start` | Robot execution started |
| `:robot_complete` | Robot execution finished |
| `:complete` | All streaming finished |
| `:error` | Error occurred |

## Callback Patterns

### Proc/Lambda

```ruby
callback = ->(event) {
  print event.text if event.type == :text_delta
}

robot.run(state: state, streaming: callback)
```

### Block

```ruby
robot.run(state: state) do |event|
  print event.text if event.type == :text_delta
end
```

### Object with `call`

```ruby
class StreamHandler
  def call(event)
    case event.type
    when :text_delta
      broadcast(event.text)
    when :error
      log_error(event.error)
    end
  end
end

robot.run(state: state, streaming: StreamHandler.new)
```

## See Also

- [Streaming Guide](../../guides/streaming.md)
- [Robot](../core/robot.md)
- [Network](../core/network.md)
