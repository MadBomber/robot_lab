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

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `*keys` | `Symbol`, `String` | — | One or more keys to retrieve; flattened and symbolized |
| `wait` | `Boolean`, `Numeric` | `false` | `false`: return immediately (nil if missing). `true`: block indefinitely. `Numeric`: block up to that many seconds |

**Returns:** the single value for one key, a `Hash` keyed by symbol for multiple keys.

**Raises:** `RobotLab::AwaitTimeout` — `"Timeout waiting for :<key> after <N> seconds"`.

!!! warning "Blocking semantics"
    - On expiry `get` **raises `RobotLab::AwaitTimeout`**; it does not return nil.
      Rescue it if a missing value is acceptable.
    - With multiple keys the timeout is applied **per missing key**, not to the
      call as a whole. `get(:a, :b, :c, wait: 60)` can block for up to 180
      seconds if all three are missing.
    - `wait: true` blocks with no deadline and can hang forever. Prefer a numeric
      timeout in production.
    - Waiting is implemented with a pipe (`Waiter`, using `IO#wait_readable`), so
      a blocked reader does not spin.

    ```ruby
    value = begin
      memory.get(:sentiment, wait: 30)
    rescue RobotLab::AwaitTimeout
      nil
    end
    ```

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

All keys **excluding** the reserved ones.

### all_keys

```ruby
memory.all_keys  # => Array<Symbol>
```

All keys **including** the reserved ones (`:data`, `:results`, `:messages`,
`:session_id`, `:cache`).

### clear

```ruby
memory.clear
```

Clear all non-reserved keys.

### reset

```ruby
memory.reset
```

Reset memory to its initial state: clears the backend, restores `:data` to `{}`,
`:results` and `:messages` to `[]`, `:session_id` to `nil`, and re-installs the
existing cache object. The `StateProxy` returned by `data` is discarded and
rebuilt on next access.

This resets the **key-value store only**. It has nothing to do with a robot's
chat history — use `robot.clear_messages(keep_system: true)` for that. The two
are independent.

### subscribe

```ruby
sub_id = memory.subscribe(:key1, :key2) do |change|
  puts "#{change.key} changed: #{change.value}"
end
```

Subscribe to changes on one or more keys. Callback receives a `MemoryChange` object.
Returns a subscription ID for [`unsubscribe`](#unsubscribe).

**Raises:** `ArgumentError` if no block is given.

Only [`set`](#set) notifies subscribers. Writing a reserved key
(`memory[:data] = ...`, `session_id=`, `append_result`) bypasses notification
entirely, as does mutating `memory.data`.

Callbacks are dispatched through `Async { }`. **Outside a running reactor the
callback runs synchronously on the writer's thread**, so a slow subscriber blocks
the `set` that triggered it.

**`RobotLab::MemoryChange` attributes:**

| Attribute | Type | Description |
|-----------|------|-------------|
| `key` | `Symbol` | The changed key |
| `value` | `Object` | New value |
| `previous` | `Object, nil` | Previous value |
| `writer` | `String, nil` | `memory.current_writer` at the time of the write — set to the robot's name for the duration of each `run` |
| `network_name` | `String, nil` | Network name |
| `timestamp` | `Time` | When the change occurred |
| `correlation_id` | `String, nil` | Optional tracing ID |

**Predicates** — note that each tests *both* sides, so all three are false when
`previous` and `value` are both nil, and all three are false for a nil→nil write:

| Predicate | Exact definition |
|-----------|------------------|
| `created?` | `previous.nil? && !value.nil?` |
| `updated?` | `!previous.nil? && !value.nil?` |
| `deleted?` | `value.nil? && !previous.nil?` |

Also available: `to_h` (`.compact`ed, `timestamp` rendered as ISO-8601),
`to_json`, and `MemoryChange.from_hash`.

### subscribe_pattern

```ruby
sub_id = memory.subscribe_pattern("analysis:*") do |change|
  puts "Analysis key #{change.key} updated"
end
```

Subscribe to keys matching a glob pattern (`*` and `?` supported). Returns a
subscription ID. **Raises:** `ArgumentError` if no block is given.

### unsubscribe

```ruby
memory.unsubscribe(sub_id)  # => Boolean
```

Remove a subscription by its ID (works for both `subscribe` and
`subscribe_pattern`). Returns `true` when something was removed.

### unsubscribe_keys

```ruby
memory.unsubscribe_keys(:status, :progress)  # => self
```

Drop **all** key subscriptions for the named keys at once, without needing their
IDs. Pattern subscriptions are unaffected.

### subscribed?

```ruby
memory.subscribed?(:status)  # => Boolean
```

Whether any subscriber — key-based or pattern-based — would be notified for `key`.

### merge!

```ruby
memory.merge!(key1: "value1", key2: "value2")  # => self
```

Merge multiple key-value pairs into memory. Each pair is assigned through `[]=`,
so non-reserved keys go through the reactive `set` path and do notify subscribers.

## Results and History

### append_result

```ruby
memory.append_result(robot_result)  # => self
```

Push a `RobotResult` onto the accumulated `:results` array. Bypasses subscriber
notification.

### set_results

```ruby
memory.set_results(array_of_results)  # => self
```

Replace the whole `:results` array (used when loading from persistence).

### results_from

```ruby
memory.results_from(5)  # => Array<RobotResult>
```

Results from the given index onward — for incremental saves. Returns `[]` when
the index is past the end.

### format_history

```ruby
memory.format_history(formatter: nil)  # => Array<Message>
```

`messages` followed by every result flat-mapped through `formatter`. Pass a
`Proc` for `formatter:` to control how a `RobotResult` becomes messages; the
default formatter is used when omitted.

## Backend

### redis?

```ruby
memory.redis?  # => Boolean
```

Whether this memory is backed by Redis rather than the in-process Hash. The
`backend: :auto` default tries Redis and falls back to a Hash; `backend: :hash`
forces the Hash.

### network_name

```ruby
memory.network_name  # => String, nil
```

The network this memory belongs to, set once at construction and read-only
thereafter. `Network` creates its shared memory as `Memory.new(network_name: name)`;
a standalone robot's inherent memory has `nil`. It is copied onto every
`MemoryChange` so a subscriber can tell which network a write came from, and it is
preserved by `clone`/`dup` — but **not** by `from_hash`.

### current_writer / current_writer=

```ruby
memory.current_writer          # => String, nil
memory.current_writer = "bot"
```

The name attributed to writes, surfaced as `MemoryChange#writer`. `Robot#run`
sets this to the robot's name for the duration of the run and restores the
previous value in an `ensure` block, so nested and concurrent runs attribute
correctly.

## Document Store

These four methods require the **`robot_lab-document_store`** extension gem. Without
it every one of them raises
`RobotLab::DependencyError: document storage requires the robot_lab-document_store gem.`

| Method | Returns | Description |
|--------|---------|-------------|
| `store_document(key, text)` | `self` | Embed `text` and store it under `key` |
| `search_documents(query, limit: 5)` | `Array<Hash>` | Hits sorted by score descending; each hash has `:key`, `:text`, `:score` |
| `document_keys` | `Array<Symbol>` | Keys of all stored documents |
| `delete_document(key)` | `self` | Remove a document |

```ruby
memory.store_document(:readme, File.read("README.md"))
memory.search_documents("how to configure redis", limit: 3).each do |hit|
  puts "#{hit[:key]} (#{hit[:score].round(3)})"
end
```

Documents live in a separate store, not in the key-value backend — they do not
appear in `keys`, `all_keys`, or `to_h`.

## Reserved Key Accessors

### data

```ruby
memory.data  # => StateProxy
memory.data[:user_id]          # Hash access
memory.data.user_id            # Method access
memory.data[:status] = "active"
```

Runtime data accessed through a [`StateProxy`](state.md) for method-style access.
Writes made through the proxy are **not** reactive — they bypass `set`, so they
wake no blocking readers and notify no subscribers.

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
memory.cache  # => RubyLLM::SemanticCache (the module itself), or nil
```

Read-only after initialization — assigning it raises
`ArgumentError: Cannot reassign cache - it is initialized automatically`.

!!! warning "`cache` is `nil` when caching is disabled"
    The value stored is the `RubyLLM::SemanticCache` **module**, not an instance.
    When constructed with `enable_cache: false` it is `nil`, so
    `memory.cache.fetch(...)` raises `NoMethodError`. Guard on
    `memory.cache` before use, or leave `enable_cache` at its `true` default.

    ```ruby
    RobotLab::Memory.new.cache                      # => RubyLLM::SemanticCache
    RobotLab::Memory.new(enable_cache: false).cache # => nil
    ```

## Serialization

### to_h

```ruby
memory.to_h
# => { data: {...}, results: [...], messages: [...], session_id: "...", custom: {...} }
```

Keys: `data` (from the `StateProxy`), `results` (each via `RobotResult#export`),
`messages` (each via `to_h`), `session_id`, and `custom` (every non-reserved key).
`cache` is never serialized.

!!! warning "`to_h` is `.compact`ed"
    Nil values are dropped, so `session_id` disappears entirely when unset:

    ```ruby
    RobotLab::Memory.new.to_h
    # => { data: {}, results: [], messages: [], custom: {} }   -- no :session_id
    ```

    Consumers must tolerate the missing key. `custom` is always present (it is
    `{}` rather than nil when there are no custom keys).

### to_json

```ruby
memory.to_json  # => String
```

Serializes `to_h`.

### from_hash

```ruby
memory = RobotLab::Memory.from_hash(hash)
```

Reconstructs `data`, `results`, `messages`, and `session_id`, then re-applies
every entry from `custom`. A fresh cache is created; subscriptions, backend
choice, and `network_name` are **not** restored.

### clone / dup

```ruby
new_memory = memory.clone
new_memory = memory.dup     # alias for clone
```

Deep copy of `data` plus copies of `results`, `messages`, `session_id`, and all
non-reserved keys. The `enable_cache` setting and `network_name` are preserved.
Subscriptions are **not** copied — the clone starts with none. Copying custom
keys uses the internal non-reactive setter, so no notifications fire.

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
result = network.memory.get(:sentiment, wait: 30)     # Block up to 30s, then raise

# Multiple keys — the timeout applies PER MISSING KEY, so this can block 180s
results = network.memory.get(:sentiment, :entities, :keywords, wait: 60)
# => { sentiment: {...}, entities: [...], keywords: [...] }

# Treat a timeout as "not available"
sentiment = begin
  network.memory.get(:sentiment, wait: 30)
rescue RobotLab::AwaitTimeout
  nil
end
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
- [StateProxy](state.md) — the wrapper returned by `memory.data`
- [State Management Architecture](../../architecture/state-management.md)
