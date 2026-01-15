# Conversation History

Persist and restore conversation threads across sessions.

## Overview

History allows you to:

- Save conversation results to a database
- Restore previous conversations
- Continue multi-turn interactions
- Maintain context across sessions

## Configuration

### History Config

Configure history with callbacks:

```ruby
history_config = RobotLab::History::Config.new(
  create_thread: ->(state:, input:, **) {
    # Create a new thread, return thread_id
    { thread_id: SecureRandom.uuid }
  },

  get: ->(thread_id:, **) {
    # Retrieve history for thread
    # Return Array<RobotResult>
    []
  },

  append_user_message: ->(thread_id:, message:, **) {
    # Optional: Store user message
  },

  append_results: ->(thread_id:, new_results:, **) {
    # Store new results
  }
)
```

### Apply to Network

```ruby
network = RobotLab.create_network do
  name "persistent_chat"
  history history_config
end
```

## Callback Reference

### create_thread

Called when starting a new conversation:

```ruby
create_thread: ->(state:, input:, **kwargs) {
  # state - Current State object
  # input - UserMessage or string
  # kwargs - Additional context

  thread = Thread.create!(
    initial_input: input.to_s,
    user_id: state.data[:user_id]
  )

  { thread_id: thread.id.to_s }  # Must return hash with :thread_id
}
```

### get

Called to retrieve existing history:

```ruby
get: ->(thread_id:, **kwargs) {
  # thread_id - The thread identifier
  # kwargs - Additional context

  Result.where(thread_id: thread_id)
        .order(:created_at)
        .map { |r| deserialize_result(r) }

  # Must return Array<RobotResult>
}
```

### append_user_message (Optional)

Called when a user message is added:

```ruby
append_user_message: ->(thread_id:, message:, **kwargs) {
  # thread_id - The thread identifier
  # message - UserMessage object

  Message.create!(
    thread_id: thread_id,
    content: message.content,
    metadata: message.metadata
  )
}
```

### append_results

Called after robots finish:

```ruby
append_results: ->(thread_id:, new_results:, **kwargs) {
  # thread_id - The thread identifier
  # new_results - Array<RobotResult>

  new_results.each do |result|
    Result.create!(
      thread_id: thread_id,
      robot_name: result.robot_name,
      output_data: serialize_output(result.output),
      stop_reason: result.stop_reason
    )
  end
}
```

## ActiveRecord Adapter

RobotLab includes a built-in ActiveRecord adapter:

```ruby
adapter = RobotLab::History::ActiveRecordAdapter.new(
  thread_model: RobotLabThread,
  result_model: RobotLabResult
)

network = RobotLab.create_network do
  history adapter.to_config
end
```

### Required Models

```ruby title="app/models/robot_lab_thread.rb"
class RobotLabThread < ApplicationRecord
  has_many :results, class_name: "RobotLabResult", foreign_key: :thread_id

  # Required columns:
  # - thread_id: string
  # - initial_input: text
  # - input_metadata: jsonb
  # - state_data: jsonb
  # - last_user_message: text
  # - last_user_message_at: datetime
end
```

```ruby title="app/models/robot_lab_result.rb"
class RobotLabResult < ApplicationRecord
  belongs_to :thread, class_name: "RobotLabThread", foreign_key: :thread_id

  # Required columns:
  # - thread_id: string
  # - robot_name: string
  # - sequence_number: integer
  # - output_data: jsonb
  # - tool_calls_data: jsonb
  # - stop_reason: string
  # - checksum: string
end
```

## Using Thread IDs

### Start New Thread

```ruby
state = RobotLab.create_state(message: "Hello!")
result = network.run(state: state)

# Thread ID is assigned automatically
thread_id = state.thread_id
```

### Continue Existing Thread

```ruby
# Option 1: Via UserMessage
message = RobotLab::UserMessage.new(
  "Continue our conversation",
  thread_id: existing_thread_id
)
state = RobotLab.create_state(message: message)

# Option 2: Direct assignment
state = RobotLab.create_state(message: "Continue")
state.thread_id = existing_thread_id

# History is automatically loaded
result = network.run(state: state)
```

## ThreadManager

For programmatic control:

```ruby
manager = RobotLab::History::ThreadManager.new(history_config)

# Create thread
thread_id = manager.create_thread(state: state, input: message)

# Load history
results = manager.get_history(thread_id)

# Save state
manager.save_state(thread_id: thread_id, state: state, since_index: 5)
```

## Serialization

### RobotResult

Results are serialized via `export`:

```ruby
result.export
# => {
#   robot_name: "assistant",
#   output: [...],
#   tool_calls: [...],
#   stop_reason: "stop",
#   id: "...",
#   created_at: "..."
# }
```

### Messages

Messages serialize to hashes:

```ruby
message.to_h
# => {
#   type: "text",
#   role: "assistant",
#   content: "Hello!",
#   stop_reason: "stop"
# }
```

### Restore from hash

```ruby
RobotLab::Message.from_hash(hash)
```

## Patterns

### Redis-Based History

```ruby
history_config = History::Config.new(
  create_thread: ->(state:, input:, **) {
    thread_id = SecureRandom.uuid
    Redis.current.hset("threads", thread_id, input.to_s)
    { thread_id: thread_id }
  },

  get: ->(thread_id:, **) {
    data = Redis.current.lrange("results:#{thread_id}", 0, -1)
    data.map { |json| deserialize_result(JSON.parse(json)) }
  },

  append_results: ->(thread_id:, new_results:, **) {
    new_results.each do |result|
      Redis.current.rpush("results:#{thread_id}", result.export.to_json)
    end
  }
)
```

### Custom Storage

```ruby
class CustomHistoryAdapter
  def initialize(storage)
    @storage = storage
  end

  def to_config
    History::Config.new(
      create_thread: method(:create_thread),
      get: method(:get),
      append_results: method(:append_results)
    )
  end

  private

  def create_thread(state:, input:, **)
    id = @storage.create_conversation(input: input.to_s)
    { thread_id: id }
  end

  def get(thread_id:, **)
    @storage.fetch_results(thread_id)
  end

  def append_results(thread_id:, new_results:, **)
    @storage.store_results(thread_id, new_results)
  end
end
```

## Best Practices

### 1. Handle Missing Threads

```ruby
get: ->(thread_id:, **) {
  thread = Thread.find_by(thread_id: thread_id)
  return [] unless thread

  thread.results.order(:created_at).map(&:to_robot_result)
}
```

### 2. Index for Performance

```sql
CREATE INDEX idx_results_thread_id ON robot_lab_results(thread_id);
CREATE INDEX idx_results_created_at ON robot_lab_results(created_at);
```

### 3. Clean Up Old Threads

```ruby
# Periodic cleanup job
Thread.where("updated_at < ?", 30.days.ago).destroy_all
```

### 4. Limit History Size

```ruby
get: ->(thread_id:, **) {
  Result.where(thread_id: thread_id)
        .order(created_at: :desc)
        .limit(50)  # Last 50 exchanges
        .reverse
        .map(&:to_robot_result)
}
```

## Next Steps

- [Memory System](memory.md) - In-memory data sharing
- [State Management](../architecture/state-management.md) - State details
- [API Reference: History](../api/history/index.md) - Complete API
