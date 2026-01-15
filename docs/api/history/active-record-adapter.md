# ActiveRecordAdapter

Rails ActiveRecord integration for conversation persistence.

## Class: `RobotLab::History::ActiveRecordAdapter`

```ruby
adapter = History::ActiveRecordAdapter.new(
  thread_model: ConversationThread,
  result_model: ConversationResult
)

config = adapter.to_config
```

## Constructor

```ruby
ActiveRecordAdapter.new(
  thread_model:,
  result_model:,
  thread_factory: nil,
  result_factory: nil
)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `thread_model` | `Class` | ActiveRecord model for threads |
| `result_model` | `Class` | ActiveRecord model for results |
| `thread_factory` | `Proc`, `nil` | Custom thread creation |
| `result_factory` | `Proc`, `nil` | Custom result creation |

## Methods

### to_config

```ruby
config = adapter.to_config
```

Convert to `History::Config` for use with networks.

## Model Requirements

### Thread Model

```ruby
# db/migrate/xxx_create_conversation_threads.rb
create_table :conversation_threads do |t|
  t.string :external_id, null: false, index: { unique: true }
  t.jsonb :metadata, default: {}
  t.timestamps
end

# app/models/conversation_thread.rb
class ConversationThread < ApplicationRecord
  has_many :results, class_name: "ConversationResult",
           foreign_key: :thread_id, dependent: :destroy
end
```

### Result Model

```ruby
# db/migrate/xxx_create_conversation_results.rb
create_table :conversation_results do |t|
  t.references :thread, foreign_key: { to_table: :conversation_threads }
  t.string :robot_name
  t.jsonb :input, default: {}
  t.jsonb :output, default: []
  t.jsonb :tool_calls, default: []
  t.jsonb :metadata, default: {}
  t.integer :position
  t.timestamps
end

# app/models/conversation_result.rb
class ConversationResult < ApplicationRecord
  belongs_to :thread, class_name: "ConversationThread"

  def to_robot_result
    RobotLab::RobotResult.from_hash(attributes)
  end
end
```

## Examples

### Basic Setup

```ruby
adapter = History::ActiveRecordAdapter.new(
  thread_model: ConversationThread,
  result_model: ConversationResult
)

network = RobotLab.create_network do
  name "chat"
  history adapter.to_config
  add_robot assistant
end
```

### With Custom Factory

```ruby
adapter = History::ActiveRecordAdapter.new(
  thread_model: ConversationThread,
  result_model: ConversationResult,
  thread_factory: ->(state:, input:, **context) {
    ConversationThread.create!(
      external_id: SecureRandom.uuid,
      user_id: context[:user_id],
      title: input.truncate(100),
      metadata: { source: context[:source] }
    )
  }
)
```

### With User Scoping

```ruby
class ScopedAdapter
  def initialize(thread_model:, result_model:)
    @thread_model = thread_model
    @result_model = result_model
  end

  def to_config
    History::Config.new(
      create_thread: method(:create_thread),
      get: method(:get),
      append_results: method(:append_results)
    )
  end

  private

  def create_thread(state:, input:, user_id:, **)
    @thread_model.create!(
      external_id: SecureRandom.uuid,
      user_id: user_id,
      title: input.truncate(100)
    )
  end

  def get(thread_id:, user_id:, **)
    thread = @thread_model.find_by(external_id: thread_id, user_id: user_id)
    return [] unless thread
    thread.results.order(:position).map(&:to_robot_result)
  end

  def append_results(thread_id:, new_results:, user_id:, **)
    thread = @thread_model.find_by!(external_id: thread_id, user_id: user_id)
    position = thread.results.maximum(:position) || 0

    @result_model.transaction do
      new_results.each_with_index do |result, i|
        thread.results.create!(
          robot_name: result.robot_name,
          input: result.input.to_h,
          output: result.output.map(&:to_h),
          tool_calls: result.tool_calls.map(&:to_h),
          position: position + i + 1
        )
      end
    end
  end
end
```

### Rails Generator

Use the Rails generator to create models:

```bash
rails generate robot_lab:history
```

This creates:

- `ConversationThread` model
- `ConversationResult` model
- Database migrations
- Initializer configuration

## See Also

- [History Overview](index.md)
- [Config](config.md)
- [Rails Integration Guide](../../guides/rails-integration.md)
