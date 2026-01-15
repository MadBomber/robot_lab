# ThreadManager

Manages conversation thread lifecycle.

## Class: `RobotLab::History::ThreadManager`

```ruby
manager = History::ThreadManager.new(config: history_config)
```

## Constructor

```ruby
ThreadManager.new(config:)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `config` | `Config` | History configuration |

## Methods

### create_thread

```ruby
thread_info = manager.create_thread(state: state, input: input, **context)
```

Create a new conversation thread.

**Returns:** Hash with `:id` and optional metadata.

### get_history

```ruby
results = manager.get_history(thread_id: id, **context)
```

Retrieve conversation history.

**Returns:** Array of `RobotResult`.

### append_results

```ruby
manager.append_results(thread_id: id, new_results: results, **context)
```

Add results to a thread.

### ensure_thread

```ruby
thread_id = manager.ensure_thread(state: state, input: input, **context)
```

Create thread if state doesn't have one, or return existing.

### load_history

```ruby
state = manager.load_history(state: state, **context)
```

Load history into state if thread_id exists.

## Examples

### Basic Usage

```ruby
config = History::Config.new(...)
manager = History::ThreadManager.new(config: config)

# Start new conversation
state = RobotLab.create_state(message: "Hello")
thread_id = manager.ensure_thread(state: state, input: "Hello")
state.thread_id = thread_id

# Run and save
result = network.run(state: state)
manager.append_results(thread_id: thread_id, new_results: result.new_results)

# Continue conversation
state2 = RobotLab.create_state(message: "Follow up")
state2.thread_id = thread_id
state2 = manager.load_history(state: state2)
# state2 now has previous results
```

### In Network

```ruby
# ThreadManager is used internally by Network
network = RobotLab.create_network do
  history config
  add_robot assistant
end

# First message - thread created automatically
result1 = network.run(state: state1)
thread_id = result1.state.thread_id

# Continue - history loaded automatically
state2 = RobotLab.create_state(
  message: UserMessage.new("Continue", thread_id: thread_id)
)
result2 = network.run(state: state2)
```

### Custom Thread Data

```ruby
manager = History::ThreadManager.new(
  config: History::Config.new(
    create_thread: ->(state:, input:, metadata:, **) {
      Thread.create(
        title: input.truncate(50),
        metadata: metadata,
        created_at: Time.current
      )
    },
    get: ->(thread_id:, **) { Thread.find(thread_id).results },
    append_results: ->(thread_id:, new_results:, **) {
      Thread.find(thread_id).results.concat(new_results)
    }
  )
)

# Pass metadata when creating thread
thread = manager.create_thread(
  state: state,
  input: "Help with billing",
  metadata: { source: "web", priority: "high" }
)
```

## See Also

- [History Overview](index.md)
- [Config](config.md)
- [ActiveRecordAdapter](active-record-adapter.md)
