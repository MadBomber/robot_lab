# StreamingContext

Manages streaming state during execution.

## Class: `RobotLab::Streaming::Context`

```ruby
context = RobotLab::Streaming::Context.new(callback: ->(e) { handle(e) })
```

## Constructor

```ruby
Context.new(callback:, robot: nil, network: nil)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `callback` | `Proc` | Event handler |
| `robot` | `Robot`, `nil` | Current robot |
| `network` | `NetworkRun`, `nil` | Network context |

## Attributes

### callback

```ruby
context.callback  # => Proc
```

The event handler callback.

### robot

```ruby
context.robot  # => Robot | nil
```

The currently executing robot.

### network

```ruby
context.network  # => NetworkRun | nil
```

The network run context.

### buffer

```ruby
context.buffer  # => String
```

Accumulated text content.

### tool_calls

```ruby
context.tool_calls  # => Array<ToolCallMessage>
```

Tool calls received during streaming.

## Methods

### emit

```ruby
context.emit(event)
```

Send an event to the callback.

### emit_text

```ruby
context.emit_text(text)
```

Emit a text delta event.

### emit_tool_call

```ruby
context.emit_tool_call(id:, name:, input:)
```

Emit a tool call event.

### emit_error

```ruby
context.emit_error(error)
```

Emit an error event.

### complete

```ruby
context.complete
```

Signal streaming completion.

### for_robot

```ruby
new_context = context.for_robot(robot)
```

Create a child context for a specific robot.

## Examples

### Custom Context

```ruby
context = RobotLab::Streaming::Context.new(
  callback: ->(event) {
    case event.type
    when :text_delta
      @output << event.text
    when :complete
      process_output(@output)
    end
  }
)

# Pass to robot
robot.run(state: state, streaming: context)
```

### Accumulating Content

```ruby
context = RobotLab::Streaming::Context.new(
  callback: ->(event) {
    print event.text if event.type == :text_delta
  }
)

robot.run(state: state, streaming: context)

# Access accumulated content
puts "Total content: #{context.buffer}"
puts "Tool calls: #{context.tool_calls.size}"
```

### Network Context

```ruby
context = RobotLab::Streaming::Context.new(
  callback: ->(event) {
    prefix = event.robot_name ? "[#{event.robot_name}] " : ""
    case event.type
    when :text_delta
      print "#{prefix}#{event.text}"
    when :robot_complete
      puts "\n#{prefix}Complete"
    end
  }
)

network.run(state: state, streaming: context)
```

## See Also

- [Streaming Overview](index.md)
- [Events](events.md)
