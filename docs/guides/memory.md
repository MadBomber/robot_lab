# Memory System

The memory system allows robots to share data within a network run.

## Overview

Memory provides:

- Key-value storage accessible by all robots
- Namespaced scopes for organization
- Persistence within a single network run

## Basic Usage

### Store Values

```ruby
state.memory.remember("user_name", "Alice")
state.memory.remember("preferences", { theme: "dark", language: "en" })
```

### Retrieve Values

```ruby
name = state.memory.recall("user_name")  # => "Alice"
prefs = state.memory.recall("preferences")  # => { theme: "dark", ... }

# Returns nil if not found
missing = state.memory.recall("unknown")  # => nil
```

### Check Existence

```ruby
state.memory.exists?("user_name")  # => true
state.memory.exists?("unknown")    # => false
```

### Remove Values

```ruby
state.memory.forget("user_name")
```

## Scoped Memory

Organize data with namespaces:

```ruby
# Create a scoped view
user_memory = state.memory.scoped("user:123")

# Operations are scoped
user_memory.remember("name", "Alice")
user_memory.remember("email", "alice@example.com")

# Keys are prefixed
state.memory.recall("user:123:name")  # => "Alice"

# Scoped recall
user_memory.recall("name")  # => "Alice"
```

### Nested Scopes

```ruby
session = state.memory.scoped("session:abc")
prefs = session.scoped("preferences")

prefs.remember("theme", "dark")
# Full key: "session:abc:preferences:theme"
```

## Memory Operations

### List All Keys

```ruby
state.memory.all
# => {
#   "user_name" => "Alice",
#   "user:123:email" => "alice@example.com",
#   ...
# }
```

### List Namespaces

```ruby
state.memory.namespaces
# => ["user:123", "session:abc", ...]
```

### Search by Pattern

```ruby
# Find keys matching pattern
matches = state.memory.search("user:*")
# => { "user:123:name" => "Alice", "user:123:email" => "..." }
```

### Statistics

```ruby
state.memory.stats
# => { total_keys: 15, namespaces: ["user:123", "session"] }
```

### Clear Memory

```ruby
# Clear a namespace
state.memory.scoped("temp").clear

# Clear all memory
state.memory.clear_all
```

## Shared Namespace

The `SHARED` namespace is a convention for cross-robot data:

```ruby
# In first robot
state.memory.remember("SHARED:context", important_data)

# In later robot
context = state.memory.recall("SHARED:context")
```

### Using Shared Scope

```ruby
shared = state.memory.scoped(RobotLab::Memory::SHARED_NAMESPACE)
shared.remember("workflow_status", "in_progress")
```

## In Tool Handlers

Access memory from tools:

```ruby
tool :update_preference do
  description "Update user preference"
  parameter :key, type: :string, required: true
  parameter :value, type: :string, required: true

  handler do |key:, value:, state:, **_|
    prefs = state.memory.scoped("preferences")
    prefs.remember(key, value)
    { success: true, key: key, value: value }
  end
end
```

## In Routers

Use memory for routing decisions:

```ruby
router = ->(args) {
  case args.call_count
  when 0
    :classifier
  when 1
    # Read classification from memory
    intent = args.network.state.memory.recall("SHARED:intent")
    case intent
    when "billing" then :billing_agent
    when "technical" then :tech_agent
    else :general_agent
    end
  else
    nil
  end
}
```

## Patterns

### Accumulating Data

```ruby
# In each robot
def add_finding(state, finding)
  findings = state.memory.recall("findings") || []
  findings << finding
  state.memory.remember("findings", findings)
end

# In final robot
all_findings = state.memory.recall("findings")
```

### Tracking Progress

```ruby
# Track workflow stages
state.memory.remember("stage", "intake")
# ... processing ...
state.memory.remember("stage", "analysis")
# ... processing ...
state.memory.remember("stage", "response")
```

### Caching Expensive Operations

```ruby
tool :fetch_user do
  handler do |user_id:, state:, **_|
    cache_key = "cache:user:#{user_id}"

    # Check cache
    cached = state.memory.recall(cache_key)
    return cached if cached

    # Fetch and cache
    user = User.find(user_id).to_h
    state.memory.remember(cache_key, user)
    user
  end
end
```

### User Session Data

```ruby
# Store session data
session = state.memory.scoped("session:#{session_id}")
session.remember("started_at", Time.now.iso8601)
session.remember("page_views", 0)

# Update during conversation
views = session.recall("page_views") || 0
session.remember("page_views", views + 1)
```

## Memory vs State.data

| Feature | Memory | State.data |
|---------|--------|------------|
| Purpose | Robot-to-robot sharing | Input/output data |
| Scope | Namespaced | Flat hash |
| Typical Use | Intermediate results | User input, workflow config |
| Persistence | Within run | Can be serialized |

```ruby
# Use state.data for input configuration
state = RobotLab.create_state(
  message: "Process order",
  data: { order_id: "123", priority: "high" }
)

# Use memory for intermediate findings
state.memory.remember("validation_result", { valid: true })
state.memory.remember("processing_steps", ["validated", "charged"])
```

## Best Practices

### 1. Use Descriptive Keys

```ruby
# Good
state.memory.remember("classification:intent", "billing")
state.memory.remember("user:123:last_order_id", "ord_456")

# Bad
state.memory.remember("x", "billing")
state.memory.remember("temp1", "ord_456")
```

### 2. Scope Related Data

```ruby
# Good
user = state.memory.scoped("user:#{user_id}")
user.remember("name", name)
user.remember("email", email)
user.remember("plan", plan)

# Less organized
state.memory.remember("user_name", name)
state.memory.remember("user_email", email)
state.memory.remember("user_plan", plan)
```

### 3. Clean Up Temporary Data

```ruby
# At end of processing
state.memory.scoped("temp").clear
```

### 4. Document Memory Keys

```ruby
# In your robot definitions, document expected keys
# Memory keys used:
# - SHARED:intent - Classification result
# - SHARED:entities - Extracted entities
# - user:{id}:* - User-specific data
```

## Next Steps

- [State Management](../architecture/state-management.md) - Full state details
- [Building Robots](building-robots.md) - Using memory in robots
- [API Reference: Memory](../api/core/memory.md) - Complete API
