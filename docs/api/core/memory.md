# Memory

Namespaced key-value store for sharing data between robots.

## Class: `RobotLab::Memory`

```ruby
memory = state.memory

memory.remember("key", "value")
value = memory.recall("key")
```

## Constants

### SHARED_NAMESPACE

```ruby
Memory::SHARED_NAMESPACE  # => "SHARED"
```

Conventional namespace for cross-robot data.

## Constructor

```ruby
memory = Memory.new(initial_data = {})
```

## Methods

### remember

```ruby
memory.remember(key, value)
```

Store a value.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `key` | `String`, `Symbol` | Storage key |
| `value` | `Object` | Value to store |

### recall

```ruby
memory.recall(key)  # => Object | nil
```

Retrieve a value.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `key` | `String`, `Symbol` | Storage key |

**Returns:** Stored value or `nil`.

### exists?

```ruby
memory.exists?(key)  # => Boolean
```

Check if key exists.

### forget

```ruby
memory.forget(key)  # => Object | nil
```

Remove a key, returns the value.

### all

```ruby
memory.all  # => Hash
```

Get all stored data.

### namespaces

```ruby
memory.namespaces  # => Array<String>
```

List all namespaces.

### clear

```ruby
memory.clear
```

Clear all data in current scope.

### clear_all

```ruby
memory.clear_all
```

Clear all data globally.

### search

```ruby
memory.search(pattern)  # => Hash
```

Find keys matching pattern.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `pattern` | `String` | Glob pattern (e.g., "user:*") |

### stats

```ruby
memory.stats  # => Hash
```

Get memory statistics.

**Returns:**

```ruby
{
  total_keys: 15,
  namespaces: ["user", "session"]
}
```

### scoped

```ruby
scoped_memory = memory.scoped(namespace)  # => ScopedMemory
```

Create a scoped view.

## ScopedMemory

Scoped view with automatic key prefixing.

### Methods

All Memory methods are available:

```ruby
scoped = memory.scoped("user:123")

scoped.remember("name", "Alice")   # Key: "user:123:name"
scoped.recall("name")              # => "Alice"
scoped.exists?("name")             # => true
scoped.forget("name")
scoped.all                         # Only "user:123:*" keys
scoped.clear                       # Clear only this scope
```

### Nested Scopes

```ruby
user = memory.scoped("user:123")
prefs = user.scoped("preferences")

prefs.remember("theme", "dark")
# Full key: "user:123:preferences:theme"
```

## Examples

### Basic Usage

```ruby
state.memory.remember("user_name", "Alice")
state.memory.remember("order_count", 5)

name = state.memory.recall("user_name")  # => "Alice"
count = state.memory.recall("order_count")  # => 5
```

### Storing Objects

```ruby
state.memory.remember("user", {
  id: 123,
  name: "Alice",
  plan: "pro"
})

user = state.memory.recall("user")
user[:plan]  # => "pro"
```

### Scoped Organization

```ruby
# User-specific data
user = state.memory.scoped("user:#{user_id}")
user.remember("last_login", Time.now)
user.remember("preferences", { theme: "dark" })

# Session-specific data
session = state.memory.scoped("session:#{session_id}")
session.remember("page_views", 0)

# Temporary working data
temp = state.memory.scoped("temp")
temp.remember("intermediate_result", calculation)
```

### Cross-Robot Communication

```ruby
# In classifier robot
state.memory.remember("SHARED:intent", "billing")
state.memory.remember("SHARED:entities", ["order", "refund"])

# In handler robot
intent = state.memory.recall("SHARED:intent")
entities = state.memory.recall("SHARED:entities")
```

### In Tool Handlers

```ruby
tool :update_preference do
  handler do |key:, value:, state:, **_|
    prefs = state.memory.scoped("preferences")
    old_value = prefs.recall(key)
    prefs.remember(key, value)

    {
      success: true,
      key: key,
      old_value: old_value,
      new_value: value
    }
  end
end
```

### Search and Iteration

```ruby
# Find all user keys
user_data = state.memory.search("user:*")
# => { "user:123:name" => "Alice", "user:123:email" => "..." }

# Process all keys
state.memory.all.each do |key, value|
  puts "#{key}: #{value}"
end
```

### Cleanup

```ruby
# Clear temporary data
state.memory.scoped("temp").clear

# Clear specific namespace
state.memory.scoped("cache").clear

# Clear everything
state.memory.clear_all
```

### Caching Pattern

```ruby
def cached_fetch(state, key, &block)
  cache = state.memory.scoped("cache")
  cached = cache.recall(key)
  return cached if cached

  result = block.call
  cache.remember(key, result)
  result
end

# Usage
data = cached_fetch(state, "expensive:#{id}") do
  ExpensiveService.fetch(id)
end
```

### Accumulating Results

```ruby
# In each robot, accumulate findings
findings = state.memory.recall("findings") || []
findings << { robot: robot.name, finding: new_finding }
state.memory.remember("findings", findings)

# In final robot, aggregate
all_findings = state.memory.recall("findings")
summary = all_findings.group_by { |f| f[:robot] }
```

## See Also

- [Memory Guide](../../guides/memory.md)
- [State](state.md)
- [State Management Architecture](../../architecture/state-management.md)
