# History::ActiveRecordAdapter

ActiveRecord-based history persistence adapter for Rails applications.

## Class: `RobotLab::History::ActiveRecordAdapter`

Provides thread and result storage using ActiveRecord models. Converts itself to a `History::Config` via `to_config` for use with networks and thread managers.

```ruby
adapter = RobotLab::History::ActiveRecordAdapter.new(
  thread_model: RobotLabThread,
  result_model: RobotLabResult
)

config = adapter.to_config
```

## Constructor

```ruby
ActiveRecordAdapter.new(thread_model:, result_model:)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `thread_model` | `Class` | ActiveRecord model class for conversation threads |
| `result_model` | `Class` | ActiveRecord model class for conversation results |

## Attributes

### thread_model

```ruby
adapter.thread_model  # => Class (ActiveRecord model)
```

The ActiveRecord model class used for storing conversation threads.

### result_model

```ruby
adapter.result_model  # => Class (ActiveRecord model)
```

The ActiveRecord model class used for storing conversation results.

## Methods

### to_config

```ruby
config = adapter.to_config  # => RobotLab::History::Config
```

Convert the adapter to a `History::Config` object. The config's callbacks delegate to the adapter's `create_thread`, `get`, `append_user_message`, and `append_results` methods.

### create_thread

```ruby
adapter.create_thread(state:, input:, **)
```

Create a new conversation thread record. Generates a UUID `session_id`, extracts content and metadata from the input, and stores `state.data` as serialized state data.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `state` | `Object` | Current memory/state (must respond to `.data`) |
| `input` | `String`, `UserMessage` | Initial user input |

**Returns:** Hash with `{ session_id: "...", created_at: Time }`.

### get

```ruby
results = adapter.get(session_id:, **)
```

Retrieve all results for a thread, ordered by `sequence_number` and `created_at`. Deserializes each record into a `RobotResult`.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `session_id` | `String` | Thread identifier |

**Returns:** `Array<RobotResult>` -- deserialized results.

### append_user_message

```ruby
adapter.append_user_message(session_id:, message:, **)
```

Update the thread record with the latest user message content and timestamp.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `message` | `UserMessage` | User message |

### append_results

```ruby
adapter.append_results(session_id:, new_results:, **)
```

Append robot results to the thread. Each result is stored with an auto-incrementing `sequence_number`. Serializes `output` and `tool_calls` from each `RobotResult`. Also updates the thread's `updated_at` timestamp.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `session_id` | `String` | Thread identifier |
| `new_results` | `Array<RobotResult>` | Results to append |

## Model Requirements

### Thread Model

The thread model must have the following columns:

```ruby
# db/migrate/xxx_create_robot_lab_threads.rb
create_table :robot_lab_threads do |t|
  t.string :session_id, null: false, index: { unique: true }
  t.text :initial_input
  t.jsonb :input_metadata, default: {}
  t.jsonb :state_data, default: {}
  t.text :last_user_message
  t.datetime :last_user_message_at
  t.timestamps
end
```

### Result Model

The result model must have the following columns:

```ruby
# db/migrate/xxx_create_robot_lab_results.rb
create_table :robot_lab_results do |t|
  t.string :session_id, null: false, index: true
  t.string :robot_name
  t.integer :sequence_number
  t.jsonb :output_data, default: []
  t.jsonb :tool_calls_data, default: []
  t.string :stop_reason
  t.string :checksum
  t.timestamps
end
```

## Examples

### Basic Setup

```ruby
adapter = RobotLab::History::ActiveRecordAdapter.new(
  thread_model: RobotLabThread,
  result_model: RobotLabResult
)

config = adapter.to_config
# Use config with a ThreadManager or pass to network configuration
```

### Using with ThreadManager

```ruby
adapter = RobotLab::History::ActiveRecordAdapter.new(
  thread_model: RobotLabThread,
  result_model: RobotLabResult
)

manager = RobotLab::History::ThreadManager.new(adapter.to_config)

# Create a thread
session_id = manager.create_thread(state: memory, input: "Hello")

# Run robot and save
result = robot.run("Hello")
manager.append_results(session_id: session_id, results: [result])

# Later, retrieve
history = manager.get_history(session_id)
```

### With User-Scoped Models

For applications that need per-user thread scoping, create a custom adapter:

```ruby
class ScopedHistoryAdapter
  def initialize(thread_model:, result_model:)
    @thread_model = thread_model
    @result_model = result_model
  end

  def to_config
    RobotLab::History::Config.new(
      create_thread: method(:create_thread),
      get: method(:get),
      append_user_message: method(:append_user_message),
      append_results: method(:append_results)
    )
  end

  private

  def create_thread(state:, input:, user_id:, **)
    thread = @thread_model.create!(
      session_id: SecureRandom.uuid,
      user_id: user_id,
      initial_input: input.to_s
    )
    { session_id: thread.session_id, created_at: thread.created_at }
  end

  def get(session_id:, user_id:, **)
    @result_model
      .joins(:thread)
      .where(threads: { session_id: session_id, user_id: user_id })
      .order(:sequence_number)
      .map(&:to_robot_result)
  end

  def append_user_message(session_id:, message:, user_id:, **)
    @thread_model.where(session_id: session_id, user_id: user_id)
      .update_all(last_user_message: message.content, last_user_message_at: Time.current)
  end

  def append_results(session_id:, new_results:, user_id:, **)
    base_seq = @result_model.where(session_id: session_id).maximum(:sequence_number) || 0

    new_results.each_with_index do |result, i|
      @result_model.create!(
        session_id: session_id,
        robot_name: result.robot_name,
        sequence_number: base_seq + i + 1,
        output_data: result.output.map(&:to_h),
        tool_calls_data: result.tool_calls.map(&:to_h),
        stop_reason: result.stop_reason,
        checksum: result.checksum
      )
    end

    @thread_model.where(session_id: session_id).update_all(updated_at: Time.current)
  end
end
```

### Rails Generator

Use the Rails generator to scaffold the required models and migrations:

```bash
rails generate robot_lab:history
```

This creates:
- Thread and result ActiveRecord models
- Database migrations with required columns
- Initializer configuration

## See Also

- [History Overview](index.md)
- [Config](config.md)
- [ThreadManager](thread-manager.md)
