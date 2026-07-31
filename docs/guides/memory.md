# Memory System

The memory system provides key-value storage for robots, supporting both standalone and network execution modes.

## Overview

Memory is a reactive key-value store that provides:

- Key-value storage with `[]` and `[]=` accessors
- Reserved keys for structured data (`:data`, `:results`, `:messages`, `:session_id`, `:cache`)
- Reactive subscriptions and blocking reads for inter-robot communication
- Optional Redis backend for persistence
- Semantic caching via `RubyLLM::SemanticCache`

## Standalone Robot Memory

Every robot has its own inherent memory that persists across runs:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are helpful."
)

# Memory persists across runs
robot.memory[:user_name] = "Alice"
robot.memory[:preferences] = { theme: "dark", language: "en" }

result = robot.run("Hello!")

# Read it back later
robot.memory[:user_name]      # => "Alice"
robot.memory[:preferences]    # => { theme: "dark", language: "en" }
```

## Basic Operations

### Store Values

```ruby
robot.memory[:key] = "value"
robot.memory[:count] = 42
robot.memory[:config] = { timeout: 30, retries: 3 }
```

### Retrieve Values

```ruby
name = robot.memory[:user_name]    # => "Alice"
missing = robot.memory[:unknown]   # => nil
```

### Check Existence

```ruby
robot.memory.key?(:user_name)   # => true
robot.memory.key?(:unknown)     # => false
```

### Delete Values

```ruby
robot.memory.delete(:temp_data)
```

### List Keys

```ruby
robot.memory.keys      # => [:user_name, :preferences] (excludes reserved keys)
robot.memory.all_keys  # => [:data, :results, :messages, :session_id, :cache, :user_name, ...]
```

### Merge Values

```ruby
robot.memory.merge!(user_id: 123, session: "abc")
```

## Reserved Keys

Memory has reserved keys with special behavior:

| Key | Type | Description |
|-----|------|-------------|
| `:data` | Hash (StateProxy) | Runtime data with method-style access |
| `:results` | Array | Accumulated robot results |
| `:messages` | Array | Conversation history |
| `:session_id` | String | Session identifier for history persistence |
| `:cache` | `RubyLLM::SemanticCache` module, or `nil` | Semantic cache (read-only after init). Set at construction time; `nil` when built with `enable_cache: false` |

### The Data Hash

The `:data` key provides a `StateProxy` for method-style access:

```ruby
robot.memory.data[:category] = "billing"
robot.memory.data.category    # => "billing" (method-style access)
robot.memory.data.to_h        # => { category: "billing" }
```

### Results and Messages

```ruby
robot.memory.results    # => Array of RobotResult objects
robot.memory.messages   # => Array of Message objects
robot.memory.session_id # => "abc123" or nil
```

## Runtime Memory Injection

Pass memory values for a single run using the `memory:` keyword:

```ruby
# Inject a hash -- values are merged into the active memory
result = robot.run("What's my order status?", memory: { user_id: 123, order_id: "ORD-456" })

# The robot's memory now contains those keys
robot.memory[:user_id]    # => 123
robot.memory[:order_id]   # => "ORD-456"
```

You can also pass a full `Memory` object to replace the active memory for that run:

```ruby
custom_memory = RobotLab.create_memory(data: { user_id: 123 })
custom_memory[:context] = "billing inquiry"

result = robot.run("Help me", memory: custom_memory)
```

## Resetting Memory

Clear a robot's memory back to its initial state:

```ruby
robot.reset_memory
robot.memory.keys  # => [] (custom keys cleared, reserved keys reset)
```

You can also clear just the custom keys without resetting reserved keys:

```ruby
robot.memory.clear  # Clears non-reserved keys only
```

> [!WARNING]
> `reset_memory` resets **only the key-value store**. It does not touch the
> robot's conversation history — the chat still holds every prior message, and
> the LLM will still see them. Clearing the transcript is a separate call:
>
> ```ruby
> robot.reset_memory                        # key-value store only
> robot.clear_messages(keep_system: true)   # conversation history only
> ```

## Network Shared Memory

When robots run in a network, they share the network's memory instead of using their own inherent memory. This allows robots to communicate through shared state:

```ruby
network = RobotLab.create_network(name: "pipeline") do
  task :analyzer, analyzer_robot, depends_on: :none
  task :writer, writer_robot, depends_on: [:analyzer]
end

# All robots in the network share this memory
network.memory[:project] = "quarterly_report"

result = network.run(message: "Analyze sales data")

# After the run, shared memory contains values written by all robots
network.memory[:analysis_result]  # Written by analyzer
network.memory[:draft]            # Written by writer
```

### Resetting Network Memory

```ruby
network.reset_memory  # Clear shared memory between runs
```

## Reactive Memory

Memory supports reactive features for concurrent robot execution.

### Blocking Reads

Wait for a value to become available (useful in parallel pipelines):

```ruby
# In robot A (writer)
memory.set(:sentiment, { score: 0.8, confidence: 0.95 })

# In robot B (reader, may run concurrently)
result = memory.get(:sentiment, wait: true)    # Blocks until available
result = memory.get(:sentiment, wait: 30)      # Blocks up to 30 seconds

# Multiple keys
results = memory.get(:sentiment, :entities, :keywords, wait: 60)
# => { sentiment: {...}, entities: [...], keywords: [...] }
```

> [!WARNING]
> A blocking `get` that expires **raises `RobotLab::AwaitTimeout`** — it does
> not return `nil`. (A *non*-blocking `get`, the default, returns `nil` for a
> missing key.) Wrap it if a missing value is survivable:
>
> ```ruby
> begin
>   memory.get(:sentiment, wait: 30)
> rescue RobotLab::AwaitTimeout => e
>   # => "Timeout waiting for :sentiment after 30 seconds"
>   nil
> end
> ```

> [!CAUTION]
> With multiple keys the timeout is applied **per missing key**, not to the call
> as a whole. `memory.get(:a, :b, :c, wait: 30)` awaits the missing keys
> sequentially, each with its own fresh 30-second budget.
>
> It does not, however, spend the whole 90 seconds before reporting: the first
> key whose wait expires **raises `AwaitTimeout` immediately**, aborting the call
> — so the keys that were already resolved are lost along with the ones not yet
> attempted. The 90 seconds is the worst case only for a call that *succeeds*
> (each key arriving just under its own deadline).

Each blocking wait is backed by an `IO.pipe` pair (`Waiter` class). The waiting
side calls `@read_io.wait_readable(timeout)`; `signal` writes one byte per
waiting caller so every blocked waiter wakes exactly once. `wait_readable`
yields to Ruby's Async fiber scheduler when one is installed — no mutex
contention or spurious wakeups.

### Subscriptions

Subscribe to key changes:

```ruby
# Subscribe to a single key
memory.subscribe(:raw_data) do |change|
  puts "#{change.key} changed by #{change.writer}"
  puts "Old: #{change.previous}, New: #{change.value}"
end

# Subscribe to multiple keys
memory.subscribe(:sentiment, :entities) do |change|
  update_dashboard(change.key, change.value)
end

# Pattern subscriptions (glob-style)
memory.subscribe_pattern("analysis:*") do |change|
  puts "Analysis key #{change.key} updated"
end
```

> [!IMPORTANT]
> Subscription callbacks are dispatched through `Async { }`. Inside a running
> Async reactor that defers them; **outside one — which is the normal case for
> plain Ruby, Rails request threads, and tests — the block runs synchronously
> on the writer's thread**, before `memory[:key] = value` returns:
>
> ```ruby
> order = []
> memory.subscribe(:k) { |c| order << "callback" }
> order << "before-set"
> memory[:k] = 1
> order << "after-set"
> order   # => ["before-set", "callback", "after-set"]
> ```
>
> Keep subscription callbacks fast, and never assume the writer has moved on by
> the time your callback runs.

### Unsubscribe

```ruby
sub_id = memory.subscribe(:status) { |c| puts c.value }
memory.unsubscribe(sub_id)
```

## Creating Standalone Memory

Use the factory method for standalone memory objects:

```ruby
memory = RobotLab.create_memory(
  data: { user_id: 123, category: nil },
  enable_cache: true
)

memory[:session_id] = "abc123"
memory[:custom_key] = "custom_value"
```

## Serialization

Memory can be exported and reconstructed:

```ruby
# Export to hash
hash = robot.memory.to_h
# => { data: {...}, results: [...], messages: [...], session_id: "...", custom: {...} }
# to_h is compacted: nil entries are dropped, so an unset :session_id (and the
# :cache key, which is never exported) simply will not appear.

# Export to JSON
json = robot.memory.to_json

# Reconstruct from hash
restored = RobotLab::Memory.from_hash(hash)
```

## Patterns

### Accumulating Data Across Robots

```ruby
# In each robot's processing
def accumulate_finding(memory, finding)
  findings = memory[:findings] || []
  findings << finding
  memory[:findings] = findings
end

# In the final robot
all_findings = memory[:findings]
```

### Tracking Progress

```ruby
memory[:stage] = "intake"
# ... processing ...
memory[:stage] = "analysis"
# ... processing ...
memory[:stage] = "response"
```

### Caching Expensive Operations

A tool reaches memory through its owning robot. Subclass `RobotLab::Tool` (which
has a `robot` accessor) and attach an **instance constructed with `robot:`** —
that is the only supported way for tool code to read and write robot memory:

```ruby
class FetchUser < RobotLab::Tool
  description "Fetch user details by ID"
  param :user_id, type: :string, desc: "User ID"

  def execute(user_id:)
    cache_key = :"cache:user:#{user_id}"

    cached = robot&.memory&.[](cache_key)
    return cached if cached

    user = User.find(user_id).to_h
    robot&.memory&.[]=(cache_key, user)
    user
  end
end

robot = RobotLab.build(name: "support", system_prompt: "...")
robot.local_tools << FetchUser.new(robot: robot)

robot.run("Look up user 42", tools: :inherit)
```

> [!WARNING]
> There is **no thread-local memory handle** in RobotLab — nothing anywhere in
> the codebase ever assigns `Thread.current[:robot_memory]`. A tool that reads
> it will always see `nil` and silently cache nothing. Go through `robot.memory`
> as above, and remember that `FetchUser.new` without `robot:` leaves `robot`
> `nil`.

### Semantic Caching

Memory exposes a semantic cache for LLM response caching. It is on by default
and becomes `nil` when you opt out with `enable_cache: false`:

```ruby
RobotLab.create_memory.cache                       # => RubyLLM::SemanticCache
RobotLab.create_memory(enable_cache: false).cache  # => nil

RobotLab.build(name: "x", system_prompt: "…").memory.cache
# => RubyLLM::SemanticCache
RobotLab.build(name: "x", system_prompt: "…", enable_cache: false).memory.cache
# => nil
```

Guard for `nil` in any code that might run against a cache-disabled memory.

```ruby
# Access the semantic cache
cache = robot.memory.cache

# Use it to cache semantically similar queries
response = cache.fetch("What is Ruby?") do
  robot.run("What is Ruby?")
end
```

> [!NOTE]
> `memory.cache` is the `RubyLLM::SemanticCache` **module itself**, not a
> per-memory instance. Its cache store, vector store, and configuration are
> process-global — two memories with `enable_cache: true` share one cache. It
> also embeds every query, so `fetch` costs an embedding call.

## Best Practices

### 1. Use Descriptive Keys

```ruby
# Good
robot.memory[:classification_intent] = "billing"
robot.memory[:user_last_order_id] = "ord_456"

# Bad
robot.memory[:x] = "billing"
robot.memory[:temp1] = "ord_456"
```

### 2. Use Data Hash for Structured Runtime Input

```ruby
memory = RobotLab.create_memory(
  data: { order_id: "123", priority: "high", customer_tier: "gold" }
)

# Access via data proxy
memory.data.order_id       # => "123"
memory.data.priority       # => "high"
memory.data.customer_tier  # => "gold"
```

### 3. Clean Up Temporary Values

```ruby
# After processing is done
robot.memory.delete(:temp_calculation)
robot.memory.delete(:intermediate_result)
```

### 4. Document Memory Keys

```ruby
# In your robot definitions, document expected keys:
#
# Memory keys used by this pipeline:
# - :intent       - Classification result (set by classifier)
# - :entities     - Extracted entities (set by entity_extractor)
# - :response     - Final response draft (set by responder)
```

## Next Steps

- [Building Robots](building-robots.md) - Using memory in robots
- [Creating Networks](creating-networks.md) - Shared memory in networks
- [API Reference: Memory](../api/core/memory.md) - Complete API
