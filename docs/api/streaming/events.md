# Streaming Events

Event types for real-time response handling.

## Class: `RobotLab::Streaming::Event`

```ruby
event.type        # => Symbol
event.text        # => String (for text events)
event.robot_name  # => String (for robot events)
```

## Event Types

### :start

Streaming has begun.

```ruby
case event.type
when :start
  puts "Starting..."
end
```

**Attributes:**

| Name | Type | Description |
|------|------|-------------|
| `robot_name` | `String`, `nil` | Robot name |

### :text_delta

A chunk of text was received.

```ruby
case event.type
when :text_delta
  print event.text
end
```

**Attributes:**

| Name | Type | Description |
|------|------|-------------|
| `text` | `String` | Text content |
| `robot_name` | `String`, `nil` | Source robot |

### :tool_call

A tool is being invoked.

```ruby
case event.type
when :tool_call
  puts "Calling #{event.name} with #{event.input}"
end
```

**Attributes:**

| Name | Type | Description |
|------|------|-------------|
| `id` | `String` | Tool call ID |
| `name` | `String` | Tool name |
| `input` | `Hash` | Tool parameters |
| `robot_name` | `String`, `nil` | Source robot |

### :tool_result

A tool has returned a result.

```ruby
case event.type
when :tool_result
  puts "#{event.name} returned: #{event.result}"
end
```

**Attributes:**

| Name | Type | Description |
|------|------|-------------|
| `id` | `String` | Tool call ID |
| `name` | `String` | Tool name |
| `result` | `Object` | Tool result |
| `robot_name` | `String`, `nil` | Source robot |

### :robot_start

A robot has started executing (network only).

```ruby
case event.type
when :robot_start
  puts "Robot #{event.robot_name} starting"
end
```

**Attributes:**

| Name | Type | Description |
|------|------|-------------|
| `robot_name` | `String` | Robot name |

### :robot_complete

A robot has finished executing (network only).

```ruby
case event.type
when :robot_complete
  puts "Robot #{event.robot_name} finished"
end
```

**Attributes:**

| Name | Type | Description |
|------|------|-------------|
| `robot_name` | `String` | Robot name |
| `result` | `RobotResult` | Execution result |

### :complete

All streaming has finished.

```ruby
case event.type
when :complete
  puts "All done!"
end
```

### :error

An error occurred.

```ruby
case event.type
when :error
  puts "Error: #{event.error.message}"
end
```

**Attributes:**

| Name | Type | Description |
|------|------|-------------|
| `error` | `Exception` | The error |
| `robot_name` | `String`, `nil` | Source robot |

## Examples

### Complete Handler

```ruby
robot.run(state: state) do |event|
  case event.type
  when :start
    puts "=== Starting ==="
  when :text_delta
    print event.text
  when :tool_call
    puts "\n[Tool: #{event.name}]"
  when :tool_result
    puts "[Result: #{event.result.to_s.truncate(50)}]"
  when :complete
    puts "\n=== Complete ==="
  when :error
    puts "\n!!! Error: #{event.error.message}"
  end
end
```

### Network Handler

```ruby
network.run(state: state) do |event|
  robot = event.robot_name || "system"

  case event.type
  when :robot_start
    puts "[#{robot}] Starting..."
  when :text_delta
    print event.text
  when :tool_call
    puts "\n[#{robot}] Calling #{event.name}"
  when :robot_complete
    puts "\n[#{robot}] Complete"
  when :error
    puts "\n[#{robot}] Error: #{event.error.message}"
  end
end
```

### Filtering Events

```ruby
# Only text
robot.run(state: state) do |event|
  print event.text if event.type == :text_delta
end

# Only tools
robot.run(state: state) do |event|
  if event.type == :tool_call
    log_tool_usage(event.name, event.input)
  end
end
```

### Async Processing

```ruby
queue = Queue.new

Thread.new do
  loop do
    event = queue.pop
    break if event == :done
    process_event(event)
  end
end

robot.run(state: state) do |event|
  queue << event
  queue << :done if event.type == :complete
end
```

## See Also

- [Streaming Overview](index.md)
- [StreamingContext](context.md)
- [Streaming Guide](../../guides/streaming.md)
