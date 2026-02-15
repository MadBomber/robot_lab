# History::Config

Configuration for conversation history persistence using callback-based architecture.

## Class: `RobotLab::History::Config`

```ruby
config = RobotLab::History::Config.new(
  create_thread: ->(state:, input:, **) {
    { session_id: SecureRandom.uuid }
  },
  get: ->(session_id:, **) {
    database.find_results(session_id)
  },
  append_results: ->(session_id:, new_results:, **) {
    database.insert_results(session_id, new_results)
  }
)
```

## Constructor

```ruby
Config.new(
  create_thread: nil,
  get: nil,
  append_user_message: nil,
  append_results: nil
)
```

All parameters are optional Proc/lambda callbacks. The `configured?` method returns `true` only when both `create_thread` and `get` are set.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `create_thread` | `Proc`, `nil` | `nil` | Callback to create a new conversation thread |
| `get` | `Proc`, `nil` | `nil` | Callback to retrieve history for a thread |
| `append_user_message` | `Proc`, `nil` | `nil` | Callback to append user messages |
| `append_results` | `Proc`, `nil` | `nil` | Callback to append robot results |

## Attributes

All attributes are read-write (`attr_accessor`):

### create_thread

```ruby
config.create_thread  # => Proc | nil
config.create_thread = ->(state:, input:, **) { ... }
```

### get

```ruby
config.get  # => Proc | nil
config.get = ->(session_id:, **) { ... }
```

### append_user_message

```ruby
config.append_user_message  # => Proc | nil
config.append_user_message = ->(session_id:, message:, **) { ... }
```

### append_results

```ruby
config.append_results  # => Proc | nil
config.append_results = ->(session_id:, new_results:, **) { ... }
```

## Methods

### configured?

```ruby
config.configured?  # => Boolean
```

Returns `true` if both `create_thread` and `get` callbacks are set.

### create_thread!

```ruby
result = config.create_thread!(state:, input:, **kwargs)
```

Invoke the `create_thread` callback. Validates that the callback is configured and that the return value is a Hash containing `:session_id`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `state` | `Object` | Current state or memory |
| `input` | `String`, `UserMessage` | Initial user input |
| `**kwargs` | `Hash` | Additional context passed through |

**Returns:** Hash with at least `{ session_id: "..." }`.

**Raises:** `HistoryError` if callback is not configured or return value is invalid.

### get!

```ruby
results = config.get!(session_id:, **kwargs)
```

Invoke the `get` callback to retrieve history for a thread.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `**kwargs` | `Hash` | Additional context |

**Returns:** Array of `RobotResult` (or whatever the callback returns).

**Raises:** `HistoryError` if callback is not configured.

### append_user_message!

```ruby
config.append_user_message!(session_id:, message:, **kwargs)
```

Invoke the `append_user_message` callback. No-op if the callback is not configured.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `message` | `UserMessage` | User message to append |
| `**kwargs` | `Hash` | Additional context |

### append_results!

```ruby
config.append_results!(session_id:, new_results:, **kwargs)
```

Invoke the `append_results` callback. No-op if the callback is not configured.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `new_results` | `Array<RobotResult>` | Results to append |
| `**kwargs` | `Hash` | Additional context |

## Callback Signatures

### create_thread

Called when a new conversation starts.

```ruby
create_thread: ->(state:, input:, **context) {
  # Must return a Hash with :session_id
  { session_id: SecureRandom.uuid }
}
```

| Argument | Type | Description |
|----------|------|-------------|
| `state` | `Object` | Current robot memory or state |
| `input` | `String`, `UserMessage` | Initial user input |
| `**context` | `Hash` | Additional context |

### get

Called to retrieve existing conversation history.

```ruby
get: ->(session_id:, **context) {
  # Return array of previous results
  Thread.find(session_id).results
}
```

| Argument | Type | Description |
|----------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `**context` | `Hash` | Additional context |

### append_user_message

Called to record user messages in the thread.

```ruby
append_user_message: ->(session_id:, message:, **context) {
  Thread.find(session_id).update(last_message: message.content)
}
```

| Argument | Type | Description |
|----------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `message` | `UserMessage` | User message |
| `**context` | `Hash` | Additional context |

### append_results

Called after robot execution to persist results.

```ruby
append_results: ->(session_id:, new_results:, **context) {
  new_results.each { |r| Thread.find(session_id).results.create(r.to_h) }
}
```

| Argument | Type | Description |
|----------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `new_results` | `Array<RobotResult>` | Results to append |
| `**context` | `Hash` | Additional context |

## Error Handling

History operations raise `RobotLab::History::HistoryError` (a subclass of `RobotLab::Error`) when:

- A required callback is not configured and the `!` method is called
- The `create_thread` callback returns a value without `:session_id`

```ruby
begin
  config.create_thread!(state: memory, input: "Hello")
rescue RobotLab::History::HistoryError => e
  puts "History error: #{e.message}"
end
```

## Examples

### Basic Config

```ruby
STORE = {}

config = RobotLab::History::Config.new(
  create_thread: ->(state:, **) {
    id = SecureRandom.uuid
    STORE[id] = { results: [] }
    { session_id: id }
  },
  get: ->(session_id:, **) {
    STORE.dig(session_id, :results) || []
  },
  append_results: ->(session_id:, new_results:, **) {
    STORE[session_id][:results].concat(new_results.map(&:to_h))
  }
)
```

### With User Scoping

```ruby
config = RobotLab::History::Config.new(
  create_thread: ->(state:, user_id:, **) {
    thread = ConversationThread.create!(user_id: user_id)
    { session_id: thread.session_id }
  },
  get: ->(session_id:, user_id:, **) {
    ConversationThread.where(session_id: session_id, user_id: user_id)
      .first&.results || []
  },
  append_results: ->(session_id:, new_results:, user_id:, **) {
    thread = ConversationThread.find_by(session_id: session_id, user_id: user_id)
    return unless thread
    new_results.each { |r| thread.results.create!(r.to_h) }
  }
)
```

## See Also

- [History Overview](index.md)
- [ThreadManager](thread-manager.md)
- [ActiveRecordAdapter](active-record-adapter.md)
