# Memory Management

Memory in RobotLab is a reactive key-value store that provides persistent storage for runtime data, conversation history, and arbitrary user-defined values. It replaces the old `State` class with a unified system that supports both standalone robot usage and shared network execution.

## Memory Structure

The `Memory` class holds:

```ruby
memory = RobotLab.create_memory(data: { user_id: "123" })

memory.data        # StateProxy - custom key-value data with method-style access
memory.results     # Array<RobotResult> - execution history
memory.messages    # Array<Message> - conversation history
memory.session_id  # String - optional persistence identifier
memory.cache       # RubyLLM::SemanticCache - semantic caching module
```

## Standalone Robot Memory

Every robot has its own inherent memory instance, accessible via `robot.memory`:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are helpful."
)

# Access the robot's memory
robot.memory[:user_name] = "Alice"
robot.memory[:user_name]  #=> "Alice"

# Run the robot
result = robot.run("Hello!")

# Memory persists between runs on the same robot instance
robot.memory[:preference] = "dark_mode"
result2 = robot.run("What are my preferences?")

# Reset memory to initial state
robot.reset_memory
```

## Network Shared Memory

When robots execute within a network, they share the network's memory instead of using their own inherent memory. This enables inter-robot communication.

```ruby
classifier = RobotLab.build(name: "classifier", system_prompt: "Classify requests.")
handler = RobotLab.build(name: "handler", system_prompt: "Handle requests.")

network = RobotLab.create_network(name: "support") do
  task :classifier, classifier, depends_on: :none
  task :handler, handler, depends_on: [:classifier]
end

# The network has its own shared memory
network.memory[:customer_tier] = "premium"

# All robots in the network read/write from network.memory during execution
result = network.run(message: "I need help with billing")

# Reset network memory between runs if needed
network.reset_memory
```

The memory resolution logic is:

1. If `network_memory` is provided at runtime, use that
2. If the robot is in a network, use the network's shared memory
3. Otherwise, use the robot's own inherent memory (`robot.memory`)

## Creating Memory

### Basic Creation

```ruby
memory = RobotLab.create_memory
```

### With Initial Data

```ruby
memory = RobotLab.create_memory(
  data: {
    user_id: "user_123",
    order_id: "ord_456",
    priority: "high"
  }
)
```

### With Caching Disabled

```ruby
memory = RobotLab.create_memory(data: {}, enable_cache: false)
```

## Reserved Keys

Memory has five reserved keys with special behavior and dedicated accessors:

| Key | Type | Description |
|-----|------|-------------|
| `:data` | `StateProxy` | Runtime data with method-style access |
| `:results` | `Array<RobotResult>` | Accumulated robot execution results |
| `:messages` | `Array<Message>` | Conversation history |
| `:session_id` | `String` | Conversation session identifier |
| `:cache` | `RubyLLM::SemanticCache` | Semantic cache module (read-only after init) |

Reserved keys are accessed through dedicated methods and are excluded from `memory.keys`:

```ruby
memory.data[:category] = "billing"
memory.data.category  #=> "billing"   (method-style via StateProxy)

memory.results       #=> []
memory.session_id    #=> nil
memory.cache         #=> RubyLLM::SemanticCache
```

## StateProxy

The `data` attribute is a `StateProxy` that provides convenient hash-style and method-style access:

```ruby
memory.data[:user_id]          # Hash-style access
memory.data[:user_id] = "456"  # Assignment

memory.data.user_id            # Method-style access
memory.data.user_id = "456"    # Method-style assignment

memory.data.key?(:user_id)     # Check existence
memory.data.keys               # Get all keys
memory.data.to_h               # Convert to plain hash
```

## Reactive Features

Memory supports pub/sub semantics where robots can subscribe to key changes and optionally block until values become available.

### Setting Values

Use `memory.set(key, value)` to write a value and notify subscribers asynchronously:

```ruby
memory.set(:sentiment, { score: 0.8, confidence: 0.95 })
```

The `[]=` operator also triggers reactive notifications for non-reserved keys:

```ruby
memory[:sentiment] = { score: 0.8 }  # Equivalent to memory.set(:sentiment, ...)
```

### Blocking Reads

Use `memory.get(key, wait:)` to block until a value becomes available. This is useful for concurrent pipeline execution where one robot needs to wait for another's output:

```ruby
# Immediate read (returns nil if missing)
memory.get(:sentiment)

# Block indefinitely until value exists
memory.get(:sentiment, wait: true)

# Block up to 30 seconds, raise AwaitTimeout if exceeded
memory.get(:sentiment, wait: 30)

# Wait for multiple keys at once
results = memory.get(:sentiment, :entities, :keywords, wait: 60)
#=> { sentiment: {...}, entities: [...], keywords: [...] }
```

### Subscriptions

Subscribe to key changes with async callbacks. The callback receives a `MemoryChange` object:

```ruby
memory.subscribe(:raw_data) do |change|
  puts "#{change.key} changed from #{change.previous} to #{change.value}"
  puts "Written by: #{change.writer} at #{change.timestamp}"
end

# Subscribe to multiple keys
memory.subscribe(:sentiment, :entities) do |change|
  update_dashboard(change.key, change.value)
end

# Pattern-based subscriptions (glob-style matching)
memory.subscribe_pattern("analysis:*") do |change|
  puts "Analysis key #{change.key} updated"
end

# Unsubscribe
sub_id = memory.subscribe(:status) { |c| puts c.value }
memory.unsubscribe(sub_id)

# Check if key has subscribers
memory.subscribed?(:status)  #=> true/false
```

### MemoryChange

The `MemoryChange` object provides context about what changed:

```ruby
change.key           #=> :sentiment
change.value         #=> { score: 0.8 }
change.previous      #=> nil (or previous value)
change.writer        #=> "classifier" (robot name)
change.network_name  #=> "support_pipeline"
change.timestamp     #=> Time
change.created?      #=> true (new key, no previous value)
change.updated?      #=> false
change.deleted?      #=> false
```

## Memory Lifecycle

### Results

Results track the history of robot executions:

```ruby
# Append a result
memory.append_result(robot_result)

# Get all results (returns a copy)
memory.results

# Get results from a specific index (for incremental persistence)
memory.results_from(5)
```

Each `RobotResult` contains:

```ruby
result.robot_name       # Which robot produced this
result.output           # Array<Message> - response content
result.tool_calls       # Array<ToolResultMessage> - tools called
result.stop_reason      # Stop reason from LLM
result.last_text_content # Convenience: last text content string
result.has_tool_calls?  # Whether any tools were called
result.created_at       # When it was created
```

### Format History

The `format_history` method prepares messages for LLM consumption:

```ruby
formatted = memory.format_history
# Returns combined messages + formatted results
```

### Merge

Merge additional values into memory:

```ruby
memory.merge!(user_id: 123, category: "billing")
```

### Key Management

```ruby
memory.key?(:user_id)      # Check existence
memory.keys                 # Get all non-reserved keys
memory.all_keys             # Get all keys including reserved
memory.delete(:temp_data)   # Delete a specific key
memory.clear                # Clear all non-reserved keys
memory.reset                # Reset to initial state (preserves cache)
```

## Cloning

Create independent copies of memory for isolated execution. Subscriptions are not cloned:

```ruby
original = RobotLab.create_memory(data: { count: 1 })
cloned = original.clone

cloned[:count] = 2
original[:count]  #=> still 1
```

## Serialization

Convert memory to and from hash for persistence:

```ruby
# To hash
hash = memory.to_h
#=> {
#     data: { ... },
#     results: [...],
#     messages: [...],
#     session_id: "abc123",
#     custom: { my_key: "value" }
#   }

# To JSON
json = memory.to_json

# From hash
memory = Memory.from_hash(hash)
```

## Semantic Cache

Memory includes a semantic cache via `RubyLLM::SemanticCache` that reduces costs and latency by returning cached responses for semantically equivalent queries:

```ruby
# Using the cache with fetch
response = memory.cache.fetch("What is Ruby?") do
  RubyLLM.chat.ask("What is Ruby?")
end

# Wrapping a chat instance
chat = memory.cache.wrap(RubyLLM.chat(model: "gpt-4o"))
chat.ask("What is Ruby?")  # Cached on semantic similarity
```

Caching can be disabled per-memory or per-robot:

```ruby
memory = RobotLab.create_memory(enable_cache: false)
robot = RobotLab.build(name: "bot", system_prompt: "...", enable_cache: false)
```

## Backend Options

Memory defaults to a Hash-based backend but can use Redis for distributed scenarios:

```ruby
# Auto-detect (uses Redis if available, falls back to Hash)
memory = Memory.new(backend: :auto)

# Force Hash backend
memory = Memory.new(backend: :hash)

# Force Redis backend
memory = Memory.new(backend: :redis)

# Check backend
memory.redis?  #=> true/false
```

Redis is configured via `RobotLab.config.redis` or the `REDIS_URL` environment variable.

## Best Practices

### 1. Use Memory for Cross-Robot Data

```ruby
# In a network, robots share memory automatically.
# Robot A writes:
memory.set(:classification, "billing")

# Robot B reads:
category = memory.get(:classification)
```

### 2. Use Blocking Reads for Concurrent Pipelines

```ruby
# When robots run in parallel, use blocking reads
# to synchronize on shared data:
results = memory.get(:sentiment, :entities, wait: 60)
```

### 3. Keep Data Minimal

```ruby
# Store references instead of large objects
memory[:response_id] = response.id    # Preferred
# memory[:huge_response] = api_response  # Avoid
```

### 4. Reset Between Independent Runs

```ruby
network.reset_memory
result = network.run(message: "New conversation")
```

## Next Steps

- [Network Orchestration](network-orchestration.md) - How networks share memory
- [Message Flow](message-flow.md) - How messages are processed
