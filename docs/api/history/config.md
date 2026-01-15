# History::Config

Configuration for conversation persistence.

## Class: `RobotLab::History::Config`

```ruby
config = History::Config.new(
  create_thread: create_proc,
  get: get_proc,
  append_results: append_proc
)
```

## Constructor

```ruby
Config.new(
  create_thread:,
  get:,
  append_results:
)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `create_thread` | `Proc` | Creates a new thread |
| `get` | `Proc` | Retrieves thread history |
| `append_results` | `Proc` | Appends results to thread |

## Callbacks

### create_thread

Called when a new conversation starts without a thread_id.

```ruby
create_thread: ->(state:, input:, **context) {
  # Create and return thread info
  { id: SecureRandom.uuid }
}
```

**Arguments:**

| Name | Type | Description |
|------|------|-------------|
| `state` | `State` | Current state |
| `input` | `String` | User input |
| `**context` | `Hash` | Additional context |

**Returns:** Hash with `:id` key.

### get

Called to retrieve existing conversation history.

```ruby
get: ->(thread_id:, **context) {
  # Return array of previous results
  Thread.find(thread_id).results
}
```

**Arguments:**

| Name | Type | Description |
|------|------|-------------|
| `thread_id` | `String` | Thread identifier |
| `**context` | `Hash` | Additional context |

**Returns:** Array of `RobotResult` or hashes.

### append_results

Called after each network run to persist new results.

```ruby
append_results: ->(thread_id:, new_results:, **context) {
  # Persist the new results
  thread = Thread.find(thread_id)
  new_results.each { |r| thread.results.create(r.to_h) }
}
```

**Arguments:**

| Name | Type | Description |
|------|------|-------------|
| `thread_id` | `String` | Thread identifier |
| `new_results` | `Array<RobotResult>` | Results to append |
| `**context` | `Hash` | Additional context |

## Attributes

### create_thread

```ruby
config.create_thread  # => Proc
```

### get

```ruby
config.get  # => Proc
```

### append_results

```ruby
config.append_results  # => Proc
```

## Examples

### Basic Config

```ruby
STORE = {}

config = History::Config.new(
  create_thread: ->(state:, **) {
    id = SecureRandom.uuid
    STORE[id] = { results: [] }
    { id: id }
  },

  get: ->(thread_id:, **) {
    STORE.dig(thread_id, :results) || []
  },

  append_results: ->(thread_id:, new_results:, **) {
    STORE[thread_id][:results].concat(new_results.map(&:to_h))
  }
)
```

### With Context

```ruby
config = History::Config.new(
  create_thread: ->(state:, user_id:, **) {
    Thread.create(user_id: user_id, started_at: Time.current)
  },

  get: ->(thread_id:, user_id:, **) {
    Thread.where(id: thread_id, user_id: user_id).first&.results || []
  },

  append_results: ->(thread_id:, new_results:, user_id:, **) {
    thread = Thread.find_by(id: thread_id, user_id: user_id)
    return unless thread
    new_results.each { |r| thread.results.create(r.to_h) }
  }
)

# Pass context when running
network.run(state: state, user_id: current_user.id)
```

### With Validation

```ruby
config = History::Config.new(
  create_thread: ->(state:, **) {
    raise "Invalid state" unless state.data[:user_id]
    Thread.create(user_id: state.data[:user_id])
  },

  get: ->(thread_id:, **) {
    thread = Thread.find_by(id: thread_id)
    raise "Thread not found" unless thread
    thread.results
  },

  append_results: ->(thread_id:, new_results:, **) {
    thread = Thread.find(thread_id)
    Thread.transaction do
      new_results.each { |r| thread.results.create!(r.to_h) }
    end
  }
)
```

## See Also

- [History Overview](index.md)
- [ThreadManager](thread-manager.md)
- [ActiveRecordAdapter](active-record-adapter.md)
