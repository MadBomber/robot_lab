# Memory (State Management)

Memory manages conversation data, results, and runtime state. There is no separate `State` class; `Memory` serves this role.

## Class: `RobotLab::Memory`

```ruby
memory = RobotLab.create_memory(
  data: { user_id: "123" }
)
```

## Attributes

### session_id

```ruby
memory.session_id  # => String | nil
```

Conversation session identifier for persistence.

### data

```ruby
memory.data  # => StateProxy
```

Access workflow data as a proxy object.

```ruby
memory.data[:user_id]          # Hash access
memory.data.user_id            # Method access
memory.data[:status] = "active"
```

### results

```ruby
memory.results  # => Array<RobotResult>
```

All robot execution results.

### messages

```ruby
memory.messages  # => Array<Message>
```

Formatted conversation messages for LLM.

## Methods

### append_result

```ruby
memory.append_result(robot_result)
```

Add a robot result to history.

### set_results

```ruby
memory.set_results(array_of_results)
```

Replace all results.

### results_from

```ruby
memory.results_from(5)  # => Array<RobotResult>
```

Get results starting at index.

### session_id=

```ruby
memory.session_id = "session_123"
```

Set the session identifier.

### format_history

```ruby
memory.format_history  # => Array<Message>
```

Format results as conversation history.

### clone

```ruby
new_memory = memory.clone
```

Create a deep copy.

### to_h

```ruby
memory.to_h  # => Hash
```

Hash representation.

### to_json

```ruby
memory.to_json  # => String
```

JSON representation.

### from_hash (class method)

```ruby
memory = Memory.from_hash(hash)
```

Restore from hash.

## StateProxy

The `data` attribute is a `StateProxy`:

```ruby
proxy = memory.data

# Hash-style access
proxy[:key]
proxy[:key] = value

# Method-style access
proxy.key
proxy.key = value

# Hash operations
proxy.key?(:key)
proxy.keys
proxy.values
proxy.each { |k, v| ... }
proxy.merge!(other_hash)
proxy.delete(:key)
proxy.to_h
proxy.empty?
proxy.size
```

## Creating Memory

### Basic

```ruby
memory = RobotLab.create_memory
```

### With Data

```ruby
memory = RobotLab.create_memory(
  data: {
    user_id: "user_123",
    order_id: "ord_456"
  }
)
```

### With Session ID

```ruby
memory = RobotLab.create_memory
memory.session_id = "session_123"
```

### With Existing Results

```ruby
memory = RobotLab.create_memory
memory.set_results(previous_results)
```

## UserMessage

Enhanced message with metadata:

```ruby
message = UserMessage.new(
  "What's my order status?",
  session_id: "session_123",
  system_prompt: "Respond in Spanish",
  metadata: { source: "web" }
)

message.content       # => "What's my order status?"
message.session_id    # => "session_123"
message.system_prompt # => "Respond in Spanish"
message.metadata      # => { source: "web" }
message.id            # => UUID
message.created_at    # => Time
```

## Examples

### Accessing Data

```ruby
memory = RobotLab.create_memory(
  data: { user: { name: "Alice", plan: "pro" } }
)

memory.data[:user][:name]  # => "Alice"
memory.data.to_h           # => { user: { name: "Alice", plan: "pro" } }
```

### Working with Results

```ruby
# After running network
memory.results.size           # Number of results
memory.results.last           # Most recent
memory.results.map(&:robot_name)  # ["classifier", "support"]
```

### Using Reactive Memory

```ruby
memory.set(:intent, "billing")
intent = memory.get(:intent)

memory.subscribe(:status) do |change|
  puts "Status changed to #{change.value} by #{change.writer}"
end
```

### Serialization

```ruby
# Save memory
json = memory.to_json
File.write("memory.json", json)

# Restore memory
data = JSON.parse(File.read("memory.json"))
memory = Memory.from_hash(data)
```

## See Also

- [State Management Architecture](../../architecture/state-management.md)
- [Memory](memory.md)
- [History Guide](../../guides/history.md)
