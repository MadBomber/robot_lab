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
    # Create a new thread, return session_id
    { session_id: SecureRandom.uuid }
  },

  get: ->(session_id:, **) {
    # Retrieve history for thread
    # Return Array<RobotResult>
    []
  },

  append_user_message: ->(session_id:, message:, **) {
    # Optional: Store user message
  },

  append_results: ->(session_id:, new_results:, **) {
    # Store new results
  }
)
```

### Apply to Network

```ruby
network = RobotLab.create_network(name: "persistent_chat") do
  task :assistant, assistant_robot, depends_on: :none
end
```

## Callback Reference

### create_thread

Called when starting a new conversation:

```ruby
create_thread: ->(state:, input:, **kwargs) {
  # state - Current Memory object
  # input - UserMessage or string
  # kwargs - Additional context

  thread = Thread.create!(
    initial_input: input.to_s,
    user_id: state.data[:user_id]
  )

  { session_id: thread.id.to_s }  # Must return hash with :session_id
}
```

### get

Called to retrieve existing history:

```ruby
get: ->(session_id:, **kwargs) {
  # session_id - The thread identifier
  # kwargs - Additional context

  Result.where(session_id: session_id)
        .order(:created_at)
        .map { |r| deserialize_result(r) }

  # Must return Array<RobotResult>
}
```

### append_user_message (Optional)

Called when a user message is added:

```ruby
append_user_message: ->(session_id:, message:, **kwargs) {
  # session_id - The thread identifier
  # message - UserMessage object

  Message.create!(
    session_id: session_id,
    content: message.content,
    metadata: message.metadata
  )
}
```

### append_results

Called after robots finish:

```ruby
append_results: ->(session_id:, new_results:, **kwargs) {
  # session_id - The thread identifier
  # new_results - Array<RobotResult>

  new_results.each do |result|
    Result.create!(
      session_id: session_id,
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

network = RobotLab.create_network(name: "persistent_chat") do
  task :assistant, assistant_robot, depends_on: :none
end
```

### Required Models

```ruby title="app/models/robot_lab_thread.rb"
class RobotLabThread < ApplicationRecord
  has_many :results, class_name: "RobotLabResult", foreign_key: :session_id

  # Required columns:
  # - session_id: string
  # - initial_input: text
  # - input_metadata: jsonb
  # - state_data: jsonb
  # - last_user_message: text
  # - last_user_message_at: datetime
end
```

```ruby title="app/models/robot_lab_result.rb"
class RobotLabResult < ApplicationRecord
  belongs_to :thread, class_name: "RobotLabThread", foreign_key: :session_id

  # Required columns:
  # - session_id: string
  # - robot_name: string
  # - sequence_number: integer
  # - output_data: jsonb
  # - tool_calls_data: jsonb
  # - stop_reason: string
  # - checksum: string
end
```

## Using Session IDs

### Start New Thread

```ruby
memory = RobotLab.create_memory(data: { user_id: "user_123" })
result = network.run(message: "Hello!")

# Session ID is assigned automatically
session_id = memory.session_id
```

### Continue Existing Thread

```ruby
# Option 1: Via UserMessage
message = RobotLab::UserMessage.new(
  "Continue our conversation",
  session_id: existing_session_id
)
result = network.run(message: message)

# Option 2: Direct assignment on memory
memory = RobotLab.create_memory
memory.session_id = existing_session_id

# History is automatically loaded
result = network.run(message: "Continue")
```

## ThreadManager

For programmatic control:

```ruby
manager = RobotLab::History::ThreadManager.new(history_config)

# Create thread
session_id = manager.create_thread(state: memory, input: message)

# Load history
results = manager.get_history(session_id)

# Save state
manager.save_state(session_id: session_id, state: memory, since_index: 5)
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
    session_id = SecureRandom.uuid
    Redis.current.hset("threads", session_id, input.to_s)
    { session_id: session_id }
  },

  get: ->(session_id:, **) {
    data = Redis.current.lrange("results:#{session_id}", 0, -1)
    data.map { |json| deserialize_result(JSON.parse(json)) }
  },

  append_results: ->(session_id:, new_results:, **) {
    new_results.each do |result|
      Redis.current.rpush("results:#{session_id}", result.export.to_json)
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
    { session_id: id }
  end

  def get(session_id:, **)
    @storage.fetch_results(session_id)
  end

  def append_results(session_id:, new_results:, **)
    @storage.store_results(session_id, new_results)
  end
end
```

## Best Practices

### 1. Handle Missing Threads

```ruby
get: ->(session_id:, **) {
  thread = Thread.find_by(session_id: session_id)
  return [] unless thread

  thread.results.order(:created_at).map(&:to_robot_result)
}
```

### 2. Index for Performance

```sql
CREATE INDEX idx_results_session_id ON robot_lab_results(session_id);
CREATE INDEX idx_results_created_at ON robot_lab_results(created_at);
```

### 3. Clean Up Old Threads

```ruby
# Periodic cleanup job
Thread.where("updated_at < ?", 30.days.ago).destroy_all
```

### 4. Limit History Size

```ruby
get: ->(session_id:, **) {
  Result.where(session_id: session_id)
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
