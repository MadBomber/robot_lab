# Rails Application

Full Rails integration with Action Cable and background jobs.

## Overview

This example demonstrates integrating RobotLab into a Rails application with real-time streaming via Action Cable, background job processing, and persistent conversation history.

## Setup

### 1. Add to Gemfile

```ruby
# Gemfile
gem "robot_lab"
```

### 2. Run Generator

```bash
rails generate robot_lab:install
```

This creates:

- `config/initializers/robot_lab.rb`
- `app/robots/` directory
- Database migrations for history

### 3. Run Migrations

```bash
rails db:migrate
```

## Configuration

```ruby
# config/initializers/robot_lab.rb

RobotLab.configure do |config|
  config.default_model = ENV.fetch("LLM_MODEL", "claude-sonnet-4")

  # Enable logging in development
  config.logger = Rails.logger if Rails.env.development?
end
```

## Models

```ruby
# app/models/conversation_thread.rb
class ConversationThread < ApplicationRecord
  belongs_to :user
  has_many :messages, class_name: "ConversationMessage", dependent: :destroy

  validates :external_id, presence: true, uniqueness: true

  def self.find_or_create_for(user:, external_id: nil)
    external_id ||= SecureRandom.uuid
    find_or_create_by!(user: user, external_id: external_id)
  end
end

# app/models/conversation_message.rb
class ConversationMessage < ApplicationRecord
  belongs_to :thread, class_name: "ConversationThread"

  validates :role, presence: true
  validates :content, presence: true

  scope :ordered, -> { order(:position) }

  def to_robot_result
    RobotLab::RobotResult.from_hash(
      robot_name: robot_name,
      input: input,
      output: output
    )
  end
end
```

## Robot Definitions

```ruby
# app/robots/support_robot.rb
class SupportRobot
  def self.build
    RobotLab.build do
      name "support"
      description "Customer support assistant"

      template <<~PROMPT
        You are a helpful customer support assistant for our company.
        Be friendly, professional, and thorough in your responses.
        If you need to look up information, use the available tools.
      PROMPT

      tool :get_user_info do
        description "Get information about the current user"

        handler do |state:, **_|
          user_id = state.data[:user_id]
          user = User.find(user_id)

          {
            name: user.name,
            email: user.email,
            plan: user.subscription&.plan || "free",
            member_since: user.created_at.to_date.to_s
          }
        rescue ActiveRecord::RecordNotFound
          { error: "User not found" }
        end
      end

      tool :get_orders do
        description "Get user's recent orders"
        parameter :limit, type: :integer, default: 5

        handler do |limit:, state:, **_|
          user_id = state.data[:user_id]
          orders = Order.where(user_id: user_id)
                       .order(created_at: :desc)
                       .limit(limit)

          orders.map do |order|
            {
              id: order.external_id,
              status: order.status,
              total: order.total.to_f,
              created_at: order.created_at.iso8601
            }
          end
        end
      end

      tool :create_ticket do
        description "Create a support ticket"
        parameter :subject, type: :string, required: true
        parameter :description, type: :string, required: true
        parameter :priority, type: :string, enum: %w[low medium high], default: "medium"

        handler do |subject:, description:, priority:, state:, **_|
          ticket = SupportTicket.create!(
            user_id: state.data[:user_id],
            subject: subject,
            description: description,
            priority: priority
          )

          {
            success: true,
            ticket_id: ticket.external_id,
            message: "Ticket created successfully"
          }
        rescue => e
          { success: false, error: e.message }
        end
      end
    end
  end
end
```

## Network Configuration

```ruby
# app/robots/support_network.rb
class SupportNetwork
  def self.build
    RobotLab.create_network do
      name "support_network"
      default_model "claude-sonnet-4"

      history RobotLab::History::ActiveRecordAdapter.new(
        thread_model: ConversationThread,
        result_model: ConversationMessage
      ).to_config

      add_robot SupportRobot.build
    end
  end
end
```

## Service Object

```ruby
# app/services/chat_service.rb
class ChatService
  def initialize(user:, thread_id: nil)
    @user = user
    @thread_id = thread_id
    @network = SupportNetwork.build
  end

  def call(message:, &streaming_callback)
    user_message = build_message(message)
    state = build_state(user_message)

    result = @network.run(state: state, user_id: @user.id) do |event|
      streaming_callback&.call(event)
    end

    {
      thread_id: result.state.thread_id,
      response: extract_response(result),
      messages: result.new_results
    }
  end

  private

  def build_message(content)
    if @thread_id
      RobotLab::UserMessage.new(content, thread_id: @thread_id)
    else
      content
    end
  end

  def build_state(message)
    RobotLab.create_state(
      message: message,
      data: { user_id: @user.id }
    )
  end

  def extract_response(result)
    result.last_result&.output&.find { |m| m.is_a?(RobotLab::TextMessage) }&.content
  end
end
```

## Controller

```ruby
# app/controllers/api/chats_controller.rb
module Api
  class ChatsController < ApplicationController
    before_action :authenticate_user!

    def create
      service = ChatService.new(
        user: current_user,
        thread_id: params[:thread_id]
      )

      result = service.call(message: params[:message])

      render json: {
        thread_id: result[:thread_id],
        response: result[:response]
      }
    end
  end
end
```

## Action Cable Integration

```ruby
# app/channels/chat_channel.rb
class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end

  def receive(data)
    ChatJob.perform_later(
      user_id: current_user.id,
      thread_id: data["thread_id"],
      message: data["message"]
    )
  end
end

# app/jobs/chat_job.rb
class ChatJob < ApplicationJob
  queue_as :default

  def perform(user_id:, thread_id:, message:)
    user = User.find(user_id)

    service = ChatService.new(user: user, thread_id: thread_id)

    service.call(message: message) do |event|
      case event.type
      when :text_delta
        broadcast_to_user(user, type: "text", content: event.text)
      when :tool_call
        broadcast_to_user(user, type: "tool", name: event.name)
      when :complete
        broadcast_to_user(user, type: "complete")
      end
    end
  end

  private

  def broadcast_to_user(user, data)
    ChatChannel.broadcast_to(user, data)
  end
end
```

## Frontend (Stimulus)

```javascript
// app/javascript/controllers/chat_controller.js
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["messages", "input", "response"]

  connect() {
    this.consumer = createConsumer()
    this.channel = this.consumer.subscriptions.create("ChatChannel", {
      received: (data) => this.handleMessage(data)
    })
  }

  disconnect() {
    this.channel?.unsubscribe()
  }

  send() {
    const message = this.inputTarget.value.trim()
    if (!message) return

    this.appendMessage("user", message)
    this.inputTarget.value = ""

    // Create response container
    this.currentResponse = document.createElement("div")
    this.currentResponse.className = "message assistant"
    this.messagesTarget.appendChild(this.currentResponse)

    this.channel.send({
      message: message,
      thread_id: this.threadId
    })
  }

  handleMessage(data) {
    switch (data.type) {
      case "text":
        this.currentResponse.textContent += data.content
        break
      case "tool":
        // Show tool indicator
        break
      case "complete":
        this.threadId = data.thread_id
        break
    }
  }

  appendMessage(role, content) {
    const div = document.createElement("div")
    div.className = `message ${role}`
    div.textContent = content
    this.messagesTarget.appendChild(div)
  }
}
```

## View

```erb
<!-- app/views/chats/show.html.erb -->
<div data-controller="chat">
  <div class="messages" data-chat-target="messages">
    <!-- Messages appear here -->
  </div>

  <form data-action="submit->chat#send">
    <input type="text"
           data-chat-target="input"
           placeholder="Type a message..."
           autocomplete="off">
    <button type="submit">Send</button>
  </form>
</div>
```

## Running

```bash
# Install dependencies
bundle install
yarn install

# Setup database
rails db:migrate

# Set API key
export ANTHROPIC_API_KEY="your-key"

# Start server
bin/dev
```

## Key Concepts

1. **Robot Classes**: Encapsulate robot definitions
2. **Network Classes**: Configure multi-robot networks
3. **Service Objects**: Handle business logic
4. **Action Cable**: Real-time streaming to browser
5. **Background Jobs**: Non-blocking processing
6. **History Persistence**: ActiveRecord integration

## See Also

- [Rails Integration Guide](../guides/rails-integration.md)
- [Streaming Guide](../guides/streaming.md)
- [History Guide](../guides/history.md)
