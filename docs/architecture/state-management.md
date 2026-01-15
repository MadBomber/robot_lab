# State Management

State in RobotLab tracks all data and history for a conversation or workflow.

## State Structure

The `State` class holds:

```ruby
state = RobotLab.create_state(
  message: "Hello!",           # Current user message
  data: { user_id: "123" }     # Custom workflow data
)

state.data        # StateProxy - custom key-value data
state.results     # Array<RobotResult> - execution history
state.messages    # Array<Message> - formatted conversation
state.thread_id   # String - optional persistence ID
state.memory      # Memory - shared key-value store
```

## Creating State

### Basic Creation

```ruby
state = RobotLab.create_state(message: "What's the weather?")
```

### With Custom Data

```ruby
state = RobotLab.create_state(
  message: "Process my order",
  data: {
    user_id: "user_123",
    order_id: "ord_456",
    priority: "high"
  }
)
```

### From Existing Results

```ruby
state = RobotLab.create_state(
  message: "Continue our conversation",
  results: previous_results,
  thread_id: "thread_abc"
)
```

## StateProxy

The `data` attribute is a `StateProxy` that provides convenient access:

```ruby
state.data[:user_id]          # Hash-style access
state.data[:user_id] = "456"  # Assignment

state.data.user_id            # Method-style access
state.data.user_id = "456"    # Method-style assignment

state.data.key?(:user_id)     # Check existence
state.data.keys               # Get all keys
state.data.to_h               # Convert to plain hash
```

### Change Tracking

StateProxy can track changes:

```ruby
state = State.new(
  data: { count: 0 },
  on_change: ->(key, old_val, new_val) {
    puts "#{key}: #{old_val} -> #{new_val}"
  }
)

state.data[:count] = 1  # Prints: "count: 0 -> 1"
```

## Memory

Memory provides a shared key-value store across robots:

```ruby
# Store values
state.memory.remember("user_name", "Alice")
state.memory.remember("preferences", { theme: "dark" })

# Retrieve values
name = state.memory.recall("user_name")  # => "Alice"

# Check existence
state.memory.exists?("user_name")  # => true

# Remove values
state.memory.forget("user_name")

# List all
state.memory.all  # => { "user_name" => "Alice", ... }
```

### Scoped Memory

Organize memory with namespaces:

```ruby
# Create scoped view
user_memory = state.memory.scoped("user:123")
user_memory.remember("last_login", Time.now)

# Access scoped data
user_memory.recall("last_login")

# Full key is "user:123:last_login"
state.memory.recall("user:123:last_login")
```

### Shared Memory

Use the `SHARED` namespace for cross-robot data:

```ruby
# In first robot
state.memory.remember("SHARED:context", important_data)

# In second robot (same or different network run)
data = state.memory.recall("SHARED:context")
```

### Memory Operations

```ruby
# Search by pattern
matches = state.memory.search("user:*")

# Get statistics
state.memory.stats
# => { total_keys: 15, namespaces: ["user", "session"] }

# Clear namespace
state.memory.scoped("temp").clear

# Clear everything
state.memory.clear_all
```

## Results

Results track the history of robot executions:

```ruby
# Append a result
state.append_result(robot_result)

# Get all results
state.results

# Get results from index
state.results_from(5)  # Results starting at index 5

# Format for LLM conversation
state.format_history
```

### Result History

Each `RobotResult` contains:

```ruby
result.robot_name   # Which robot produced this
result.output       # Array<Message> - response content
result.tool_calls   # Array<ToolMessage> - tools called
result.stop_reason  # "stop", "tool", etc.
result.created_at   # When it was created
```

## Messages

The `messages` method formats state for LLM consumption:

```ruby
messages = state.messages

# Returns Array<Message> with:
# - System message (if present)
# - Alternating user/assistant messages
# - Tool calls and results
```

## Thread ID

For persistent conversations:

```ruby
# Set thread ID
state.thread_id = "thread_123"

# Or via UserMessage
message = UserMessage.new(
  "Continue",
  thread_id: "thread_123"
)
state = RobotLab.create_state(message: message)
```

## State Cloning

Create independent copies:

```ruby
original = RobotLab.create_state(data: { count: 1 })
clone = original.clone

clone.data[:count] = 2
original.data[:count]  # Still 1
```

## Serialization

Convert state to/from hash:

```ruby
# To hash
hash = state.to_h
json = state.to_json

# From hash
state = State.from_hash(hash)
```

### Hash Structure

```ruby
{
  data: { ... },
  results: [
    {
      robot_name: "assistant",
      output: [...],
      tool_calls: [...],
      stop_reason: "stop"
    }
  ],
  thread_id: "thread_123"
}
```

## UserMessage

Enhanced message with metadata:

```ruby
message = UserMessage.new(
  "What's the status of my order?",
  thread_id: "thread_123",
  system_prompt: "Respond in Spanish",  # Augment system prompt
  metadata: {
    user_id: "user_456",
    source: "web_chat"
  }
)

state = RobotLab.create_state(message: message)
```

### UserMessage Properties

| Property | Description |
|----------|-------------|
| `content` | The message text |
| `thread_id` | Conversation thread ID |
| `system_prompt` | Additional system instructions |
| `metadata` | Custom key-value data |
| `id` | Unique message identifier |
| `created_at` | Timestamp |

## Best Practices

### 1. Use Memory for Cross-Robot Data

```ruby
# Don't pass data through routing
router = ->(args) {
  # Bad: parsing previous output for data
}

# Do: use memory
state.memory.remember("classification", "billing")
# Later robot reads it directly
```

### 2. Scope Memory Appropriately

```ruby
# Session data
session = state.memory.scoped("session:#{session_id}")

# User preferences
user = state.memory.scoped("user:#{user_id}")

# Temporary working data
temp = state.memory.scoped("temp")
```

### 3. Keep Data Minimal

```ruby
# Don't store large objects
state.data[:huge_response] = api_response  # Bad

# Store references instead
state.data[:response_id] = response.id  # Good
```

## Next Steps

- [Memory System](../guides/memory.md) - Advanced memory patterns
- [History Guide](../guides/history.md) - Persisting state
- [Message Flow](message-flow.md) - How messages are processed
