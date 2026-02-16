# Rails Integration

RobotLab integrates seamlessly with Ruby on Rails applications.

## Installation

### Generate Files

```bash
rails generate robot_lab:install
```

This creates:

```
config/initializers/robot_lab.rb  # Logger setup
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

RobotLab uses [MywayConfig](https://github.com/madbomber/myway_config) for configuration. There is no `RobotLab.configure` block. Instead, settings are loaded from YAML files and environment variables in the following priority order:

1. **Bundled defaults** (`lib/robot_lab/config/defaults.yml`)
2. **Environment-specific overrides** (development, test, production sections)
3. **XDG user config** (`~/.config/robot_lab/config.yml`)
4. **Project config** (`./config/robot_lab.yml`)
5. **Environment variables** (`ROBOT_LAB_*` prefix)

### Project Config File

```yaml title="config/robot_lab.yml"
defaults:
  ruby_llm:
    anthropic_api_key: <%= ENV['ANTHROPIC_API_KEY'] %>
    openai_api_key: <%= ENV['OPENAI_API_KEY'] %>
    model: claude-sonnet-4
    request_timeout: 180

  # Template path auto-detected as app/prompts in Rails
  # template_path: app/prompts

development:
  ruby_llm:
    model: claude-haiku-3
    log_level: :debug

test:
  streaming_enabled: false
  ruby_llm:
    model: claude-3-haiku-20240307
    request_timeout: 30

production:
  ruby_llm:
    request_timeout: 180
    max_retries: 5
```

### Environment Variables

Environment variables use the `ROBOT_LAB_` prefix with double underscores for nested keys:

```bash
ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...
ROBOT_LAB_RUBY_LLM__MODEL=claude-sonnet-4
ROBOT_LAB_RUBY_LLM__REQUEST_TIMEOUT=180
```

RobotLab also falls back to standard provider environment variables (e.g. `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) when the prefixed versions are not set.

### Initializer (Logger Only)

The only runtime-writable config attribute is the logger. The generated initializer sets it to the Rails logger:

```ruby title="config/initializers/robot_lab.rb"
# frozen_string_literal: true

# Set the RobotLab logger to use Rails.logger
RobotLab.config.logger = Rails.logger
```

### Accessing Configuration

```ruby
# Read configuration values
RobotLab.config.ruby_llm.model             #=> "claude-sonnet-4"
RobotLab.config.ruby_llm.anthropic_api_key #=> "sk-ant-..."
RobotLab.config.ruby_llm.request_timeout   #=> 120
RobotLab.config.streaming_enabled          #=> true
```

## Creating Robots

### Robot Generator

```bash
rails generate robot_lab:robot Support
rails generate robot_lab:robot Billing --description="Handles billing inquiries"
rails generate robot_lab:robot Router --routing
```

### Robot Class

Robots are plain Ruby classes with a `.build` factory method that calls `RobotLab.build` with keyword arguments:

```ruby title="app/robots/support_robot.rb"
# frozen_string_literal: true

class SupportRobot
  def self.build
    RobotLab.build(
      name: "support",
      description: "Handles customer support inquiries",
      model: "claude-sonnet-4",
      template: :support,
      local_tools: [OrderLookup.new]
    )
  end
end
```

### Custom Tool

Tools subclass `RobotLab::Tool` (which extends `RubyLLM::Tool`):

```ruby title="app/tools/order_lookup.rb"
# frozen_string_literal: true

class OrderLookup < RobotLab::Tool
  description "Look up an order by ID"
  param :order_id, type: "string", desc: "The order ID to look up"

  def execute(order_id:)
    order = Order.find_by(id: order_id)
    return "Order not found" unless order

    {
      id: order.id,
      status: order.status,
      total: order.total.to_s,
      created_at: order.created_at.iso8601
    }.to_json
  end
end
```

### Using in Controllers

```ruby title="app/controllers/chat_controller.rb"
class ChatController < ApplicationController
  def create
    robot = SupportRobot.build
    result = robot.run(params[:message])

    render json: {
      response: result.last_text_content,
      robot_name: result.robot_name
    }
  end
end
```

### Using a Network in Controllers

Networks use `RobotLab.create_network` with a block DSL that defines tasks. Each task wraps a robot with dependency declarations:

```ruby title="app/controllers/chat_controller.rb"
class ChatController < ApplicationController
  def create
    support_robot  = SupportRobot.build
    billing_robot  = BillingRobot.build

    network = RobotLab.create_network(name: "customer_service") do
      task :support, support_robot, depends_on: :none
      task :billing, billing_robot, depends_on: :optional
    end

    result = network.run(message: params[:message], user_id: current_user.id)

    # result is a SimpleFlow::Result
    # result.value is a RobotResult from the last robot
    render json: {
      response: result.value.last_text_content,
      robot_name: result.value.robot_name
    }
  end
end
```

## Prompt Templates

### Template Location

Templates are `.md` files with YAML front matter, stored in `app/prompts/` (auto-configured for Rails):

```
app/prompts/
├── support.md
├── billing.md
└── router.md
```

### Template Format

```markdown title="app/prompts/support.md"
---
description: Customer support assistant
parameters:
  company_name: null
  tone: friendly
model: claude-sonnet-4
temperature: 0.7
---
You are a support agent for <%= company_name %>.
Respond in a <%= tone %> manner.

Your responsibilities:
- Answer product questions
- Help with order issues
- Provide friendly assistance
```

### Template Usage

```ruby
# Pass context to fill template parameters
robot = RobotLab.build(
  name: "support",
  template: :support,
  context: { company_name: "Acme Corp" }
)

# Parameters with defaults (like `tone: friendly`) are optional.
# Parameters set to null are required and must be provided via context.
result = robot.run("I need help with my order")
```

## Action Cable Integration

### Channel

```ruby title="app/channels/chat_channel.rb"
class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat_#{params[:session_id]}"
  end

  def receive(data)
    message    = data["message"]
    session_id = data["session_id"]

    robot  = SupportRobot.build
    result = robot.run(message)

    ActionCable.server.broadcast(
      "chat_#{session_id}",
      {
        event: "complete",
        response: result.last_text_content,
        robot_name: result.robot_name
      }
    )
  end
end
```

### JavaScript Client

```javascript
const channel = consumer.subscriptions.create(
  { channel: "ChatChannel", session_id: sessionId },
  {
    received(data) {
      if (data.event === "complete") {
        displayMessage(data.response);
      }
    }
  }
);

channel.send({ message: "Hello!", session_id: sessionId });
```

## Background Jobs

### Async Processing

```ruby title="app/jobs/process_message_job.rb"
class ProcessMessageJob < ApplicationJob
  queue_as :default

  def perform(session_id:, message:, user_id:)
    robot  = SupportRobot.build
    result = robot.run(message)

    # Notify user of completion via Action Cable
    ActionCable.server.broadcast(
      "chat_#{session_id}",
      {
        event: "complete",
        response: result.last_text_content,
        robot_name: result.robot_name
      }
    )
  end
end
```

### Enqueue from Controller

```ruby
ProcessMessageJob.perform_later(
  session_id: params[:session_id],
  message: params[:message],
  user_id: current_user.id
)

render json: { status: "processing" }
```

## Testing

### Test Configuration

Use `config/robot_lab.yml` to configure the test environment with a faster, cheaper model:

```yaml title="config/robot_lab.yml"
test:
  max_iterations: 3
  streaming_enabled: false
  ruby_llm:
    model: claude-3-haiku-20240307
    request_timeout: 30
    max_retries: 1
```

### Robot Tests

```ruby title="test/robots/support_robot_test.rb"
require "test_helper"

class SupportRobotTest < ActiveSupport::TestCase
  test "builds valid robot" do
    robot = SupportRobot.build
    assert_equal "support", robot.name
  end

  test "robot has correct model" do
    robot = SupportRobot.build
    assert_equal "claude-sonnet-4", robot.model
  end

  test "robot has local tools" do
    robot = SupportRobot.build
    tool_names = robot.local_tools.map(&:name)
    assert_includes tool_names, "order_lookup"
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
    end
  end
end
```

## Models

### Thread Model

```ruby title="app/models/robot_lab_thread.rb"
class RobotLabThread < ApplicationRecord
  has_many :results,
           class_name: "RobotLabResult",
           foreign_key: :session_id,
           primary_key: :session_id,
           dependent: :destroy

  validates :session_id, presence: true, uniqueness: true

  def self.find_or_create_by_session_id(id)
    find_or_create_by(session_id: id)
  end

  def last_result
    results.order(sequence_number: :desc).first
  end
end
```

### Result Model

```ruby title="app/models/robot_lab_result.rb"
class RobotLabResult < ApplicationRecord
  belongs_to :thread,
             class_name: "RobotLabThread",
             foreign_key: :session_id,
             primary_key: :session_id

  validates :session_id, presence: true
  validates :robot_name, presence: true

  default_scope { order(sequence_number: :asc) }

  def to_robot_result
    RobotLab::RobotResult.new(
      robot_name: robot_name,
      output: (output_data || []).map { |d| RobotLab::Message.from_hash(d.symbolize_keys) },
      tool_calls: (tool_calls_data || []).map { |d| RobotLab::Message.from_hash(d.symbolize_keys) },
      stop_reason: stop_reason
    )
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

  def process(message)
    robot  = SupportRobot.build
    result = robot.run(message)

    {
      response: result.last_text_content,
      robot_name: result.robot_name
    }
  end

  def process_with_network(message)
    support_robot = SupportRobot.build
    billing_robot = BillingRobot.build

    network = RobotLab.create_network(name: "customer_service") do
      task :support, support_robot, depends_on: :none
      task :billing, billing_robot, depends_on: :optional
    end

    result = network.run(message: message, user_id: @user.id)

    {
      response: result.value.last_text_content,
      robot_name: result.value.robot_name
    }
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
