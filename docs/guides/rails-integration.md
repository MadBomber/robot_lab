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
app/jobs/robot_run_job.rb  # Background job for robot execution
app/robots/  # Directory for robots
app/tools/   # Directory for tools
```

Options:

- `--skip-migration` — Skip database migration generation
- `--skip-job` — Skip background job generation

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
  def self.build(**options)
    RobotLab.build(
      name: "support",
      description: "Handles customer support inquiries",
      system_prompt: "You are a helpful support assistant.",
      model: "claude-sonnet-4",
      local_tools: [OrderLookup],
      **options
    )
  end
end
```

### Routing Robot Class

A routing robot classifies requests and activates optional tasks in a Network. It subclasses `RobotLab::Robot` and overrides `call(result)`:

```ruby title="app/robots/classifier_robot.rb"
# frozen_string_literal: true

class ClassifierRobot < RobotLab::Robot
  SYSTEM_PROMPT = <<~PROMPT
    You are a routing robot that classifies user requests.

    Analyze the user's request and respond with ONLY the category name.
    Valid categories: billing, technical, general
  PROMPT

  def self.build(**options)
    new(
      name: "classifier",
      description: "Classifies support requests",
      system_prompt: SYSTEM_PROMPT,
      **options
    )
  end

  def call(result)
    context = extract_run_context(result)
    message = context.delete(:message)

    robot_result = run(message, **context)

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    category = robot_result.last_text_content.to_s.strip.downcase

    case category
    when /billing/  then new_result.activate(:billing)
    when /technical/ then new_result.activate(:technical)
    else new_result.activate(:general)
    end
  end
end
```

Use the routing robot as the first task in a network:

```ruby
classifier = ClassifierRobot.build
billing    = BillingRobot.build
technical  = TechnicalRobot.build

network = RobotLab.create_network(name: "support") do
  task :classifier, classifier, depends_on: :none
  task :billing,    billing,    depends_on: :optional
  task :technical,  technical,  depends_on: :optional
end

result = network.run(message: "I was charged twice")
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

### RobotLab::Job Base Class

All RobotLab background jobs inherit from `RobotLab::Job` (`RobotLab::RailsIntegration::Job`), which handles the full robot-run lifecycle automatically:

1. Resolves the robot class (from the `robot_class` DSL or a `robot_class:` kwarg at enqueue time)
2. Finds or creates a `RobotLabThread` record and stamps the incoming message
3. Wires Turbo Stream callbacks when `turbo-rails` is available (graceful no-op otherwise)
4. Runs the robot and persists the `RobotResult` to `RobotLabResult`
5. Broadcasts a completion or error event via Turbo Streams

`retry_on StandardError` (3 attempts, 5 s wait) and `discard_on ActiveJob::DeserializationError` are configured by default.

### RobotRunJob (Generated)

The install generator creates a thin subclass you can enqueue with any robot class at runtime:

```ruby title="app/jobs/robot_run_job.rb"
class RobotRunJob < RobotLab::Job
  queue_as :default
end
```

```ruby
# Enqueue from a controller — pass robot_class: as a string
RobotRunJob.perform_later(
  robot_class: "SupportRobot",
  message:     params[:message],
  thread_id:   session_id
)

render json: { status: "processing" }
```

### Dedicated Job (robot_class DSL)

Generate a job pre-bound to a specific robot class so callers never need to pass `robot_class:`:

```bash
rails generate robot_lab:job Support            # binds to SupportRobot, queue: default
rails generate robot_lab:job Support --queue ai # custom queue name
```

```ruby title="app/jobs/support_job.rb"
class SupportJob < RobotLab::Job
  queue_as :default
  robot_class SupportRobot
end
```

```ruby
# No robot_class: needed at enqueue time
SupportJob.perform_later(message: params[:message], thread_id: session_id)
```

The `robot_class` DSL is per-subclass and does not affect sibling job classes.

### Omitting thread_id (fire-and-forget)

When `thread_id` is omitted the job runs the robot and returns the result without any persistence or broadcasting:

```ruby
RobotRunJob.perform_later(robot_class: "ChatRobot", message: "ping")
```

### Turbo Stream Token Streaming

When `turbo-rails` is installed, `RobotLab::Job` automatically streams content tokens and tool call badges to the browser in real time.

#### View Setup

Subscribe to the thread's Turbo Stream channel in your view:

```erb
<%%= turbo_stream_from "robot_lab_thread_#{@thread_id}" %>

<div id="robot_response"></div>
<div id="robot_tools"></div>
<div id="robot_status">Processing...</div>
<div id="robot_errors"></div>
```

As the robot generates tokens, they are appended to `#robot_response`. Tool calls appear as badges in `#robot_tools`. On completion, `#robot_status` is replaced with "Complete".

#### TurboStreamCallbacks API

`RobotLab::RailsIntegration::TurboStreamCallbacks` is a stateless utility module for building callback Procs. Use it outside of `RobotRunJob` for custom streaming setups:

```ruby
# Check if Turbo Streams is available
RobotLab::RailsIntegration::TurboStreamCallbacks.available?

# Build a content streaming callback
on_content = RobotLab::RailsIntegration::TurboStreamCallbacks.build_content_callback(
  stream_name: "robot_lab_thread_#{thread_id}",
  target: "robot_response"  # default
)

# Build a tool call badge callback
on_tool_call = RobotLab::RailsIntegration::TurboStreamCallbacks.build_tool_call_callback(
  stream_name: "robot_lab_thread_#{thread_id}",
  target: "robot_tools"  # default
)

# Wire into a robot at build time
robot = SupportRobot.build(on_content: on_content, on_tool_call: on_tool_call)
robot.run(message)
```

The stream name convention is `"robot_lab_thread_#{thread_id}"`, matching the `RobotLabThread.session_id` pattern.

### Custom Background Job

For full control outside of the `RobotLab::Job` lifecycle (e.g. custom persistence or a different broadcasting strategy), inherit from `ApplicationJob` directly:

```ruby title="app/jobs/process_message_job.rb"
class ProcessMessageJob < ApplicationJob
  queue_as :default

  def perform(session_id:, message:, user_id:)
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
