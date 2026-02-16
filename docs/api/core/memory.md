# Memory

Reactive key-value store for sharing data between robots.

## Class: `RobotLab::Memory`

```ruby
memory = robot.memory

memory.set(:key, "value")
value = memory.get(:key)
```

## Constants

### RESERVED_KEYS

```ruby
Memory::RESERVED_KEYS  # => [:data, :results, :messages, :session_id, :cache]
```

Reserved keys with special accessors and behavior.

## Constructor

```ruby
memory = Memory.new(
  data: {},
  results: [],
  messages: [],
  session_id: nil,
  backend: :auto,
  enable_cache: true,
  network_name: nil
)
```

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `data` | `Hash` | `{}` | Initial runtime data |
| `results` | `Array` | `[]` | Pre-loaded robot results |
| `messages` | `Array` | `[]` | Pre-loaded conversation messages |
| `session_id` | `String, nil` | `nil` | Session identifier |
| `backend` | `Symbol` | `:auto` | Storage backend (`:auto`, `:redis`, `:hash`) |
| `enable_cache` | `Boolean` | `true` | Whether to enable semantic caching |
| `network_name` | `String, nil` | `nil` | Network this memory belongs to |

## Factory Method

```ruby
memory = RobotLab.create_memory(data: { user_id: 123 })
```

## Methods

### set

```ruby
memory.set(:key, value)
```

Store a value and notify subscribers asynchronously.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `key` | `Symbol`, `String` | Storage key |
| `value` | `Object` | Value to store |

### get

```ruby
memory.get(:key)                        # => value or nil
memory.get(:key, wait: true)            # Block until available
memory.get(:key, wait: 30)              # Block up to 30 seconds
memory.get(:a, :b, :c, wait: 60)        # Multiple keys, returns Hash
```

Retrieve one or more values, optionally waiting until they exist.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `keys` | `Symbol`, `String` | One or more keys to retrieve |
| `wait` | `Boolean`, `Numeric` | `false`: immediate, `true`: block, `Numeric`: timeout |

**Returns:** Single value for one key, `Hash` for multiple keys.

**Raises:** `AwaitTimeout` if timeout expires.

### key?

```ruby
memory.key?(:key)  # => Boolean
```

Check if key exists. Aliases: `has_key?`, `include?`.

### delete

```ruby
memory.delete(:key)  # => deleted value
```

Remove a key. Cannot delete reserved keys.

### keys

```ruby
memory.keys  # => Array<Symbol>
```

Get all non-reserved keys.

### clear

```ruby
memory.clear
```

Clear all non-reserved keys.

### reset

```ruby
memory.reset
```

Reset memory to initial state (clears everything including reserved keys, preserves cache).

### subscribe

```ruby
sub_id = memory.subscribe(:key1, :key2) do |change|
  puts "#{change.key} changed: #{change.value}"
end
```

Subscribe to changes on one or more keys. Callback receives a `MemoryChange` object.

**MemoryChange attributes:**

| Attribute | Type | Description |
|-----------|------|-------------|
| `key` | `Symbol` | The changed key |
| `value` | `Object` | New value |
| `previous` | `Object` | Previous value |
| `writer` | `String, nil` | Name of robot that wrote |
| `network_name` | `String, nil` | Network name |
| `timestamp` | `Time` | When the change occurred |
| `created?` | `Boolean` | Previous was nil |
| `updated?` | `Boolean` | Previous was not nil |
| `deleted?` | `Boolean` | New value is nil |

### subscribe_pattern

```ruby
sub_id = memory.subscribe_pattern("analysis:*") do |change|
  puts "Analysis key #{change.key} updated"
end
```

Subscribe to keys matching a glob pattern (`*` and `?` supported).

### unsubscribe

```ruby
memory.unsubscribe(sub_id)  # => Boolean
```

Remove a subscription by its ID.

### merge!

```ruby
memory.merge!(key1: "value1", key2: "value2")
```

Merge multiple key-value pairs into memory.

## Reserved Key Accessors

### data

```ruby
memory.data  # => StateProxy
memory.data[:user_id]          # Hash access
memory.data.user_id            # Method access
memory.data[:status] = "active"
```

Runtime data accessed through `StateProxy` for method-style access.

### results

```ruby
memory.results  # => Array<RobotResult>
```

Accumulated robot results (returns a copy).

### messages

```ruby
memory.messages  # => Array<Message>
```

Conversation messages (returns a copy).

### session_id

```ruby
memory.session_id          # => String | nil
memory.session_id = "abc"  # Set session identifier
```

### cache

```ruby
memory.cache  # => RubyLLM::SemanticCache
```

Semantic cache module (read-only after initialization).

## Serialization

### to_h

```ruby
memory.to_h
# => { data: {...}, results: [...], messages: [...], session_id: "...", custom: {...} }
```

### to_json

```ruby
memory.to_json  # => String
```

### from_hash

```ruby
memory = Memory.from_hash(hash)
```

Reconstruct memory from a hash.

### clone

```ruby
new_memory = memory.clone
```

Deep copy with fresh subscriptions (cache and network_name preserved).

## Examples

### Basic Usage

```ruby
robot.memory.set(:user_name, "Alice")
robot.memory.set(:order_count, 5)

name = robot.memory.get(:user_name)    # => "Alice"
count = robot.memory.get(:order_count) # => 5
```

### Bracket Access

```ruby
robot.memory[:user_id] = 123
robot.memory[:user_id]  # => 123
```

### Storing Objects

```ruby
robot.memory.set(:user, {
  id: 123,
  name: "Alice",
  plan: "pro"
})

user = robot.memory.get(:user)
user[:plan]  # => "pro"
```

### Blocking Reads (Network Parallel Execution)

```ruby
# In robot A (writer)
network.memory.set(:sentiment, { score: 0.8, confidence: 0.95 })

# In robot B (reader, may run concurrently)
result = network.memory.get(:sentiment, wait: true)   # Block indefinitely
result = network.memory.get(:sentiment, wait: 30)     # Block up to 30s

# Multiple keys with timeout
results = network.memory.get(:sentiment, :entities, :keywords, wait: 60)
# => { sentiment: {...}, entities: [...], keywords: [...] }
```

### Reactive Subscriptions

```ruby
# Subscribe to a key
memory.subscribe(:raw_data) do |change|
  enriched = enrich(change.value)
  memory.set(:enriched, enriched)
end

# Subscribe with pattern
memory.subscribe_pattern("user:*") do |change|
  puts "User key #{change.key} updated by #{change.writer}"
end
```

### Cross-Robot Communication via Network Memory

```ruby
# In classifier robot
network.memory.set(:intent, "billing")
network.memory.set(:entities, ["order", "refund"])

# In handler robot
intent = network.memory.get(:intent)
entities = network.memory.get(:entities)
```

### Data Proxy

```ruby
memory = RobotLab.create_memory(
  data: { user: { name: "Alice", plan: "pro" } }
)

memory.data[:user][:name]  # => "Alice"
memory.data.to_h           # => { user: { name: "Alice", plan: "pro" } }
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

- [Memory Guide](../../guides/memory.md)
- [State Management Architecture](../../architecture/state-management.md)
