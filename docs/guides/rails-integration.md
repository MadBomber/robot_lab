# Rails Integration

RobotLab integrates seamlessly with Ruby on Rails applications.

## Installation

### Generate Files

```bash
rails generate robot_lab:install
```

This creates:

```
config/initializers/robot_lab.rb  # Configuration
db/migrate/*_create_robot_lab_tables.rb  # Database tables
app/models/robot_lab_thread.rb  # Thread model
app/models/robot_lab_result.rb  # Result model
app/robots/  # Directory for robots
app/tools/   # Directory for tools
```

### Run Migrations

```bash
rails db:migrate
```

## Configuration

### Initializer

```ruby title="config/initializers/robot_lab.rb"
RobotLab.configure do |config|
  # API Keys from credentials
  config.anthropic_api_key = Rails.application.credentials.anthropic_api_key
  config.openai_api_key = Rails.application.credentials.openai_api_key

  # Defaults
  config.default_provider = :anthropic
  config.default_model = "claude-sonnet-4"

  # Rails logger
  config.logger = Rails.logger

  # Template path (auto-configured to app/prompts)
end
```

### Environment-Specific

```ruby
RobotLab.configure do |config|
  config.anthropic_api_key = Rails.application.credentials.anthropic_api_key

  case Rails.env
  when "development"
    config.default_model = "claude-haiku-3"  # Faster/cheaper
    config.logger.level = :debug
  when "test"
    config.streaming_enabled = false
  when "production"
    config.default_model = "claude-sonnet-4"
  end
end
```

### Application Config

```ruby title="config/application.rb"
module MyApp
  class Application < Rails::Application
    config.robot_lab.default_model = "claude-sonnet-4"
    config.robot_lab.default_provider = :anthropic
  end
end
```

## Creating Robots

### Robot Generator

```bash
rails generate robot_lab:robot Support
rails generate robot_lab:robot Billing --description="Handles billing inquiries"
rails generate robot_lab:robot Router --routing
```

### Robot Class

```ruby title="app/robots/support_robot.rb"
class SupportRobot
  def self.build
    RobotLab.build do
      name "support"
      description "Handles customer support inquiries"
      model "claude-sonnet-4"

      template "support/system_prompt"

      tool :lookup_order do
        description "Look up order by ID"
        parameter :order_id, type: :string, required: true
        handler { |order_id:, **_| Order.find_by(id: order_id)&.to_h }
      end
    end
  end
end
```

### Using in Controllers

```ruby title="app/controllers/chat_controller.rb"
class ChatController < ApplicationController
  def create
    network = build_network
    state = RobotLab.create_state(
      message: params[:message],
      data: { user_id: current_user.id }
    )

    result = network.run(state: state)

    render json: {
      response: result.last_result.output.first.content,
      thread_id: state.thread_id
    }
  end

  private

  def build_network
    RobotLab.create_network do
      name "customer_service"
      add_robot SupportRobot.build
      add_robot BillingRobot.build

      history history_adapter.to_config
    end
  end

  def history_adapter
    RobotLab::History::ActiveRecordAdapter.new(
      thread_model: RobotLabThread,
      result_model: RobotLabResult
    )
  end
end
```

## Prompt Templates

### Template Location

```
app/prompts/
├── support/
│   ├── system_prompt.erb
│   └── greeting.erb
└── billing/
    └── system_prompt.erb
```

### Template Usage

```ruby
robot = RobotLab.build do
  name "support"
  template "support/system_prompt", company: "Acme Corp"
end
```

```erb title="app/prompts/support/system_prompt.erb"
You are a support agent for <%= company %>.

Your responsibilities:
- Answer product questions
- Help with order issues
- Provide friendly assistance
```

## Action Cable Integration

### Channel

```ruby title="app/channels/chat_channel.rb"
class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat_#{params[:thread_id]}"
  end

  def receive(data)
    message = data["message"]
    thread_id = data["thread_id"]

    state = RobotLab.create_state(message: message)
    state.thread_id = thread_id if thread_id

    network.run(
      state: state,
      streaming: ->(event) {
        ActionCable.server.broadcast("chat_#{thread_id || state.thread_id}", event)
      }
    )
  end

  private

  def network
    @network ||= ChatNetwork.build
  end
end
```

### JavaScript Client

```javascript
const channel = consumer.subscriptions.create(
  { channel: "ChatChannel", thread_id: threadId },
  {
    received(data) {
      if (data.event === "delta") {
        appendToMessage(data.data.content);
      }
    }
  }
);

channel.send({ message: "Hello!", thread_id: threadId });
```

## Background Jobs

### Async Processing

```ruby title="app/jobs/process_message_job.rb"
class ProcessMessageJob < ApplicationJob
  queue_as :default

  def perform(thread_id:, message:, user_id:)
    state = RobotLab.create_state(
      message: message,
      data: { user_id: user_id }
    )
    state.thread_id = thread_id

    result = network.run(state: state)

    # Notify user of completion
    ActionCable.server.broadcast(
      "chat_#{thread_id}",
      { event: "complete", response: result.last_result.output.first.content }
    )
  end

  private

  def network
    ChatNetwork.build
  end
end
```

### Enqueue from Controller

```ruby
ProcessMessageJob.perform_later(
  thread_id: params[:thread_id],
  message: params[:message],
  user_id: current_user.id
)

render json: { status: "processing" }
```

## Testing

### Test Configuration

```ruby title="config/environments/test.rb"
Rails.application.configure do
  config.robot_lab.streaming_enabled = false
end
```

### Robot Tests

```ruby title="test/robots/support_robot_test.rb"
require "test_helper"

class SupportRobotTest < ActiveSupport::TestCase
  test "builds valid robot" do
    robot = SupportRobot.build
    assert_equal "support", robot.name
    assert_includes robot.tools.map(&:name), "lookup_order"
  end
end
```

### Integration Tests

```ruby title="test/integration/chat_test.rb"
require "test_helper"

class ChatTest < ActionDispatch::IntegrationTest
  test "processes chat message" do
    VCR.use_cassette("chat_response") do
      post chat_path, params: { message: "Hello" }
      assert_response :success

      json = JSON.parse(response.body)
      assert json["response"].present?
      assert json["thread_id"].present?
    end
  end
end
```

## Models

### Thread Model

```ruby title="app/models/robot_lab_thread.rb"
class RobotLabThread < ApplicationRecord
  has_many :results, class_name: "RobotLabResult", foreign_key: :thread_id
  belongs_to :user, optional: true

  scope :recent, -> { order(updated_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
end
```

### Result Model

```ruby title="app/models/robot_lab_result.rb"
class RobotLabResult < ApplicationRecord
  belongs_to :thread, class_name: "RobotLabThread"

  def to_robot_result
    RobotLab::RobotResult.new(
      robot_name: robot_name,
      output: deserialize_messages(output_data),
      tool_calls: deserialize_messages(tool_calls_data),
      stop_reason: stop_reason
    )
  end

  private

  def deserialize_messages(data)
    return [] unless data
    data.map { |h| RobotLab::Message.from_hash(h.symbolize_keys) }
  end
end
```

## Best Practices

### 1. Use Service Objects

```ruby title="app/services/chat_service.rb"
class ChatService
  def initialize(user:)
    @user = user
  end

  def process(message, thread_id: nil)
    state = build_state(message, thread_id)
    result = network.run(state: state)

    {
      response: result.last_result.output.first.content,
      thread_id: state.thread_id
    }
  end

  private

  def build_state(message, thread_id)
    state = RobotLab.create_state(
      message: message,
      data: { user_id: @user.id }
    )
    state.thread_id = thread_id if thread_id
    state
  end

  def network
    @network ||= ChatNetwork.build
  end
end
```

### 2. Handle Errors

```ruby
def create
  result = ChatService.new(user: current_user).process(params[:message])
  render json: result
rescue RobotLab::Error => e
  render json: { error: e.message }, status: :unprocessable_entity
rescue StandardError => e
  Rails.logger.error("Chat error: #{e.message}")
  render json: { error: "An error occurred" }, status: :internal_server_error
end
```

### 3. Rate Limiting

```ruby
class ChatController < ApplicationController
  before_action :check_rate_limit

  private

  def check_rate_limit
    key = "chat_rate:#{current_user.id}"
    count = Rails.cache.increment(key, 1, expires_in: 1.minute)

    if count > 10
      render json: { error: "Rate limit exceeded" }, status: :too_many_requests
    end
  end
end
```

## Next Steps

- [Building Robots](building-robots.md) - Robot patterns
- [Creating Networks](creating-networks.md) - Network configuration
- [History Guide](history.md) - Conversation persistence
