# StateProxy

!!! danger "There is no `RobotLab::State` class"
    RobotLab has never had a `State` class. Runtime state lives in
    [`RobotLab::Memory`](memory.md). The only state object is
    **`RobotLab::StateProxy`** (`lib/robot_lab/state_proxy.rb`), which is what
    `memory.data` returns — and that is what this page documents.

    This page is listed as "State" in the site navigation for historical reasons.
    For the key-value store, subscriptions, blocking reads, results, and
    serialization, go to **[Memory](memory.md)**.

## Class: `RobotLab::StateProxy`

A thin wrapper around a symbol-keyed Hash that adds method-style access and an
optional change callback. It is not a `Hash` subclass and does not implement the
full `Hash` interface — the supported methods are listed below.

```ruby
proxy = RobotLab::StateProxy.new({ count: 0, name: "test" })

proxy[:count] = 1
proxy.count       # => 1
proxy[:name]      # => "test"
proxy.to_h        # => { count: 1, name: "test" }
```

## Where you get one

`memory.data` — the reserved `:data` key of a `Memory` — is the only place the
framework hands you a `StateProxy`:

```ruby
memory = RobotLab.create_memory(data: { user_id: "123" })

memory.data                    # => #<RobotLab::StateProxy {user_id: "123"}>
memory.data[:user_id]          # => "123"     Hash access
memory.data.user_id            # => "123"     method access
memory.data[:status] = "active"
```

The proxy is memoized (`@data ||= StateProxy.new(...)`) and is reset whenever
`memory[:data] = ...` or `memory.reset` is called.

!!! warning "`memory.data` mutations are not reactive"
    `memory.data[:x] = 1` writes through the proxy into the `:data` hash. It does
    **not** go through `Memory#set`, so it wakes no blocking readers and notifies
    no subscribers. Use `memory.set(:x, 1)` on a non-reserved key when you need
    reactive semantics.

## Constructor

```ruby
RobotLab::StateProxy.new(data = {}, on_change: nil)
```

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `data` | `Hash` | `{}` | Initial data. Keys are converted to Symbols via `transform_keys(&:to_sym)` |
| `on_change` | `Proc`, `nil` | `nil` | Called as `on_change.call(key, old_value, new_value)` on `[]=`, and only when the value actually changed (`old_value != value`) |

`Memory#data` constructs the proxy **without** an `on_change` callback.

## Methods

### Element access

```ruby
proxy[:key]          # => value (keys are symbolized on read)
proxy[:key] = value  # fires on_change when the value differs
```

Both `[]` and `[]=` call `key.to_sym`, so `proxy["a"]` and `proxy[:a]` are the same entry.

### Method-style access

```ruby
proxy.name        # same as proxy[:name] — only when :name already exists
proxy.name = "x"  # same as proxy[:name] = "x" — always works
```

Implemented with `method_missing`. A **getter** for a key that does not exist
falls through to `super` and raises `NoMethodError`; a **setter** always works and
creates the key. `respond_to?(:name)` is true only once the key exists.

Method-style access cannot reach a key whose name collides with a real
`StateProxy` method (`keys`, `size`, `map`, `each`, `delete`, `dup`, `inspect`, …).
Use `proxy[:keys]` for those.

### Full method list

| Method | Returns | Notes |
|--------|---------|-------|
| `[](key)` | value | Symbolizes the key |
| `[]=(key, value)` | value | Symbolizes the key; fires `on_change` |
| `key?(key)` | `Boolean` | Aliases: `has_key?`, `include?` |
| `keys` | `Array<Symbol>` | |
| `values` | `Array` | |
| `each { \|k, v\| }` | delegates to `Hash#each` | |
| `map { \|k, v\| }` | `Array` | |
| `delete(key)` | deleted value | Does **not** fire `on_change` |
| `merge!(other)` | `self` | Assigns each pair through `[]=`, so `on_change` fires per key |
| `to_h` | `Hash` | A **shallow** `dup`; aliased as `to_hash` |
| `dup` | `StateProxy` | Deep duplicate, preserving `on_change` |
| `empty?` | `Boolean` | |
| `size` | `Integer` | Aliased as `length` |
| `inspect` | `String` | `#<RobotLab::StateProxy {...}>` |

There is no `clear`, no `fetch`, no `dig`, and no `clone`. `to_h` is a shallow
copy, so nested Hashes are shared with the proxy — mutate them and the proxy sees
it. Use `dup` when you need isolation.

## Examples

### Nested data

```ruby
memory = RobotLab.create_memory(
  data: { user: { name: "Alice", plan: "pro" } }
)

memory.data[:user][:name]  # => "Alice"   (plain Hash below the top level)
memory.data.user           # => { name: "Alice", plan: "pro" }
memory.data.to_h           # => { user: { name: "Alice", plan: "pro" } }
```

Only the top level is proxied. Nested values are returned as-is — a nested Hash
is a plain Hash, not another `StateProxy`.

### Change tracking

```ruby
proxy = RobotLab::StateProxy.new({ status: "pending" }, on_change: lambda { |key, old, new|
  puts "#{key}: #{old.inspect} -> #{new.inspect}"
})

proxy[:status] = "active"   # "status: \"pending\" -> \"active\""
proxy[:status] = "active"   # silent — value unchanged
proxy.delete(:status)       # silent — delete does not fire on_change
```

## See Also

- [Memory](memory.md) — the store that owns the proxy: keys, subscriptions, blocking reads, results, serialization
- [State Management Architecture](../../architecture/state-management.md)
