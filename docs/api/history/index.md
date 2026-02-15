# History

Conversation persistence and thread management.

## Overview

The history system enables persistent conversations by storing and retrieving conversation threads and results. It uses a callback-based architecture where you provide lambda/proc implementations for thread creation, retrieval, and result storage.

```ruby
config = RobotLab::History::Config.new(
  create_thread: ->(state:, input:, **) {
    { session_id: SecureRandom.uuid }
  },
  get: ->(session_id:, **) {
    STORE[session_id] || []
  },
  append_results: ->(session_id:, new_results:, **) {
    STORE[session_id] ||= []
    STORE[session_id].concat(new_results)
  }
)
```

## Components

| Component | Description |
|-----------|-------------|
| [Config](config.md) | History configuration with persistence callbacks |
| [ThreadManager](thread-manager.md) | Thread lifecycle management |
| [ActiveRecordAdapter](active-record-adapter.md) | Rails ActiveRecord integration |

## Quick Start

### Basic Configuration

```ruby
STORE = {}

history = RobotLab::History::Config.new(
  create_thread: ->(state:, input:, **) {
    id = SecureRandom.uuid
    STORE[id] = []
    { session_id: id }
  },
  get: ->(session_id:, **) {
    STORE[session_id] || []
  },
  append_results: ->(session_id:, new_results:, **) {
    STORE[session_id].concat(new_results)
  }
)
```

### With ActiveRecord

```ruby
adapter = RobotLab::History::ActiveRecordAdapter.new(
  thread_model: RobotLabThread,
  result_model: RobotLabResult
)

config = adapter.to_config
```

## Callbacks

| Callback | Required | Purpose |
|----------|----------|---------|
| `create_thread` | Yes (for `configured?`) | Create a new conversation thread |
| `get` | Yes (for `configured?`) | Retrieve existing thread history |
| `append_user_message` | No | Record user messages |
| `append_results` | No | Persist robot results |

## Thread Lifecycle

1. **Create** -- When a new conversation starts, `create_thread` is called. It must return a Hash with a `:session_id` key.
2. **Retrieve** -- On subsequent messages, `get` is called with the `session_id` to load previous results.
3. **Append** -- After each robot execution, `append_results` is called with the new `RobotResult` objects.
4. **User Messages** -- Optionally, `append_user_message` records each user input.

## Examples

### In-Memory Store

```ruby
THREADS = {}

history = RobotLab::History::Config.new(
  create_thread: ->(state:, **) {
    id = SecureRandom.uuid
    THREADS[id] = []
    { session_id: id }
  },
  get: ->(session_id:, **) {
    THREADS[session_id] || []
  },
  append_results: ->(session_id:, new_results:, **) {
    THREADS[session_id].concat(new_results)
  }
)
```

### Redis Store

```ruby
history = RobotLab::History::Config.new(
  create_thread: ->(state:, **) {
    id = SecureRandom.uuid
    Redis.current.set("thread:#{id}", [].to_json)
    { session_id: id }
  },
  get: ->(session_id:, **) {
    data = Redis.current.get("thread:#{session_id}")
    data ? JSON.parse(data) : []
  },
  append_results: ->(session_id:, new_results:, **) {
    existing = JSON.parse(Redis.current.get("thread:#{session_id}") || "[]")
    existing.concat(new_results.map(&:to_h))
    Redis.current.set("thread:#{session_id}", existing.to_json)
  }
)
```

## See Also

- [Config](config.md)
- [ThreadManager](thread-manager.md)
- [ActiveRecordAdapter](active-record-adapter.md)
