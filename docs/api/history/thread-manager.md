# History::ThreadManager

Manages conversation thread lifecycle using a `History::Config` for persistence.

## Class: `RobotLab::History::ThreadManager`

```ruby
config = RobotLab::History::Config.new(...)
manager = RobotLab::History::ThreadManager.new(config)

session_id = manager.create_thread(state: memory, input: "Hello")
history = manager.get_history(session_id)
```

## Constructor

```ruby
ThreadManager.new(config)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `config` | `Config` | History configuration with persistence callbacks |

## Attributes

### config

```ruby
manager.config  # => RobotLab::History::Config
```

The history configuration object.

## Methods

### create_thread

```ruby
session_id = manager.create_thread(state:, input:)
```

Create a new conversation thread. Delegates to `config.create_thread!` and returns the `session_id` from the result hash.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `state` | `Object` | Current robot memory or state |
| `input` | `String`, `UserMessage` | Initial user input |

**Returns:** `String` -- the session ID for the new thread.

### get_history

```ruby
results = manager.get_history(session_id)
```

Retrieve conversation history for a thread. Delegates to `config.get!`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `session_id` | `String` | Thread identifier |

**Returns:** `Array<RobotResult>` -- history of results for the thread.

### append_user_message

```ruby
manager.append_user_message(session_id:, message:)
```

Append a user message to the thread. Delegates to `config.append_user_message!`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `message` | `UserMessage` | User message to append |

### append_results

```ruby
manager.append_results(session_id:, results:)
```

Append robot results to the thread. Delegates to `config.append_results!`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `results` | `Array<RobotResult>` | Results to append |

### load_state

```ruby
state = manager.load_state(session_id:, state:)
```

Load history from a thread into a state/memory object. Retrieves the history, sets the `session_id` on the state, and calls `append_result` for each historical result.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `state` | `Object` | State or Memory object to populate |

**Returns:** The state object with loaded history.

### save_state

```ruby
manager.save_state(session_id:, state:, since_index: 0)
```

Save new results from a state object to the thread. Extracts results from `state.results` starting at `since_index` and appends them.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `state` | `Object` | State object with results |
| `since_index` | `Integer` | Save results from this index (default: 0) |

## Examples

### Basic Usage

```ruby
config = RobotLab::History::Config.new(
  create_thread: ->(state:, input:, **) { { session_id: SecureRandom.uuid } },
  get: ->(session_id:, **) { STORE[session_id] || [] },
  append_results: ->(session_id:, new_results:, **) {
    STORE[session_id] ||= []
    STORE[session_id].concat(new_results)
  }
)

manager = RobotLab::History::ThreadManager.new(config)

# Start a new conversation
session_id = manager.create_thread(state: memory, input: "Hello")

# Run a robot and save results
result = robot.run("Hello")
manager.append_results(session_id: session_id, results: [result])

# Later, retrieve history
history = manager.get_history(session_id)
```

### Loading History into Memory

```ruby
manager = RobotLab::History::ThreadManager.new(config)

# Create a memory object and load previous conversation
memory = RobotLab::Memory.new
manager.load_state(session_id: existing_session_id, state: memory)

# Memory now contains previous results and session_id
```

### Saving Incremental Results

```ruby
# Save only new results (since the last save point)
initial_count = memory.results.length

result = robot.run("Follow-up question")
memory.append_result(result)

manager.save_state(
  session_id: session_id,
  state: memory,
  since_index: initial_count
)
```

## See Also

- [History Overview](index.md)
- [Config](config.md)
- [ActiveRecordAdapter](active-record-adapter.md)
