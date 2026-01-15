# State

Manages conversation data, results, and memory.

## Class: `RobotLab::State`

```ruby
state = RobotLab.create_state(
  message: "Hello",
  data: { user_id: "123" }
)
```

## Attributes

### thread_id

```ruby
state.thread_id  # => String | nil
```

Conversation thread identifier for persistence.

### memory

```ruby
state.memory  # => Memory
```

Shared key-value store.

## Methods

### data

```ruby
state.data  # => StateProxy
```

Access workflow data as a proxy object.

```ruby
state.data[:user_id]          # Hash access
state.data.user_id            # Method access
state.data[:status] = "active"
```

### results

```ruby
state.results  # => Array<RobotResult>
```

All robot execution results.

### messages

```ruby
state.messages  # => Array<Message>
```

Formatted conversation messages for LLM.

### append_result

```ruby
state.append_result(robot_result)
```

Add a robot result to history.

### set_results

```ruby
state.set_results(array_of_results)
```

Replace all results.

### results_from

```ruby
state.results_from(5)  # => Array<RobotResult>
```

Get results starting at index.

### thread_id=

```ruby
state.thread_id = "thread_123"
```

Set the thread identifier.

### format_history

```ruby
state.format_history  # => Array<Message>
```

Format results as conversation history.

### clone

```ruby
new_state = state.clone
```

Create a deep copy.

### to_h

```ruby
state.to_h  # => Hash
```

Hash representation.

### to_json

```ruby
state.to_json  # => String
```

JSON representation.

### from_hash (class method)

```ruby
state = State.from_hash(hash)
```

Restore from hash.

## StateProxy

The `data` attribute is a `StateProxy`:

```ruby
proxy = state.data

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

## Creating State

### Basic

```ruby
state = RobotLab.create_state(message: "Hello")
```

### With Data

```ruby
state = RobotLab.create_state(
  message: "Process order",
  data: {
    user_id: "user_123",
    order_id: "ord_456"
  }
)
```

### With Thread ID

```ruby
# Via UserMessage
message = UserMessage.new("Continue", thread_id: "thread_123")
state = RobotLab.create_state(message: message)

# Direct assignment
state = RobotLab.create_state(message: "Continue")
state.thread_id = "thread_123"
```

### With Existing Results

```ruby
state = RobotLab.create_state(
  message: "Follow up",
  results: previous_results
)
```

## UserMessage

Enhanced message with metadata:

```ruby
message = UserMessage.new(
  "What's my order status?",
  thread_id: "thread_123",
  system_prompt: "Respond in Spanish",
  metadata: { source: "web" }
)

message.content       # => "What's my order status?"
message.thread_id     # => "thread_123"
message.system_prompt # => "Respond in Spanish"
message.metadata      # => { source: "web" }
message.id            # => UUID
message.created_at    # => Time
```

## Examples

### Accessing Data

```ruby
state = RobotLab.create_state(
  message: "Help",
  data: { user: { name: "Alice", plan: "pro" } }
)

state.data[:user][:name]  # => "Alice"
state.data.to_h           # => { user: { name: "Alice", plan: "pro" } }
```

### Working with Results

```ruby
# After running network
state.results.size           # Number of results
state.results.last           # Most recent
state.results.map(&:robot_name)  # ["classifier", "support"]
```

### Using Memory

```ruby
state.memory.remember("intent", "billing")
intent = state.memory.recall("intent")

scoped = state.memory.scoped("user:123")
scoped.remember("preference", "dark_mode")
```

### Serialization

```ruby
# Save state
json = state.to_json
File.write("state.json", json)

# Restore state
data = JSON.parse(File.read("state.json"))
state = State.from_hash(data)
```

## See Also

- [State Management Architecture](../../architecture/state-management.md)
- [Memory](memory.md)
- [History Guide](../../guides/history.md)
