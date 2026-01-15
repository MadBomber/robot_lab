# Building Robots

This guide covers everything you need to know about creating robots in RobotLab.

## Basic Robot

Create a simple robot with the builder DSL:

```ruby
robot = RobotLab.build do
  name "assistant"
  description "A helpful AI assistant"
  template "You are a helpful assistant."
end
```

## Robot Properties

### Name

A unique identifier used for routing and logging:

```ruby
name "support_agent"
```

### Description

Describes what the robot does (useful for routing decisions):

```ruby
description "Handles customer support inquiries about orders and refunds"
```

### Model

The LLM model to use:

```ruby
model "claude-sonnet-4"      # Anthropic
model "gpt-4o"               # OpenAI
model "gemini-1.5-pro"       # Google
```

### Template (System Prompt)

Instructions that define the robot's personality and behavior:

```ruby
template <<~PROMPT
  You are a customer support specialist for TechCo.

  Your responsibilities:
  - Answer questions about products and services
  - Help resolve order issues
  - Provide friendly, professional assistance

  Always be polite and acknowledge the customer's concerns.
PROMPT
```

## Adding Tools

Give robots capabilities with tools:

```ruby
robot = RobotLab.build do
  name "order_assistant"

  tool :lookup_order do
    description "Look up order details by order ID"
    parameter :order_id, type: :string, required: true, description: "The order ID"
    handler do |order_id:, **_context|
      Order.find_by(id: order_id)&.to_h || { error: "Order not found" }
    end
  end

  tool :check_inventory do
    description "Check product inventory"
    parameter :product_id, type: :string, required: true
    parameter :warehouse, type: :string, default: "main"
    handler do |product_id:, warehouse:, **_context|
      Inventory.check(product_id, warehouse: warehouse)
    end
  end
end
```

### Tool Parameters

Define parameters with types and descriptions:

```ruby
tool :search do
  parameter :query, type: :string, required: true, description: "Search query"
  parameter :limit, type: :integer, default: 10, description: "Max results"
  parameter :category, type: :string, enum: %w[books movies music]
end
```

| Option | Description |
|--------|-------------|
| `type` | Parameter type (`:string`, `:integer`, `:boolean`, `:number`, `:array`, `:object`) |
| `required` | Whether the parameter is required |
| `default` | Default value if not provided |
| `description` | Description for the LLM |
| `enum` | List of allowed values |

### Tool Handler Context

Handlers receive execution context:

```ruby
handler do |param1:, param2:, robot:, network:, state:|
  # robot   - The Robot instance
  # network - The NetworkRun
  # state   - Current State

  # Access state data
  user_id = state.data[:user_id]

  # Use memory
  state.memory.remember("last_search", param1)

  # Return result (will be sent to LLM)
  { success: true, data: result }
end
```

!!! tip "Ignoring Context"
    Use `**_context` to accept but ignore context:
    ```ruby
    handler { |query:, **_context| search(query) }
    ```

## Template Files

Load templates from files:

```ruby
# Configure template path
RobotLab.configure do |config|
  config.template_path = "prompts"  # or "app/prompts" in Rails
end

# Reference template by name
robot = RobotLab.build do
  name "support"
  template "support_agent"  # Loads prompts/support_agent.erb
end
```

### Template Variables

Pass variables to templates:

```ruby
robot = RobotLab.build do
  name "support"
  template "support_agent", company: "TechCo", tone: "friendly"
end
```

```erb title="prompts/support_agent.erb"
You are a support agent for <%= company %>.
Your tone should be <%= tone %>.
```

## MCP Configuration

Connect to MCP servers:

```ruby
robot = RobotLab.build do
  name "coder"

  # Use specific MCP servers
  mcp [
    {
      name: "filesystem",
      transport: { type: "stdio", command: "mcp-server-fs", args: ["--root", "/data"] }
    }
  ]

  # Or inherit from network
  mcp :inherit

  # Or disable MCP
  mcp :none
end
```

## Tool Whitelist

Restrict available tools:

```ruby
robot = RobotLab.build do
  name "reader"

  # Only allow specific tools
  tools %w[read_file list_directory]

  # Or inherit from network
  tools :inherit

  # Or disable all inherited tools
  tools :none
end
```

## Running Robots

### Standalone

Run a robot directly:

```ruby
state = RobotLab.create_state(message: "Hello!")
result = robot.run(state: state, network: nil)

puts result.output.first.content
```

### In a Network

Run through a network for full orchestration:

```ruby
network = RobotLab.create_network do
  add_robot robot
end

state = RobotLab.create_state(message: "Hello!")
result = network.run(state: state)
```

### With Streaming

Stream responses in real-time:

```ruby
robot.run(
  state: state,
  network: network,
  streaming: ->(event) {
    case event[:event]
    when "delta"
      print event[:data][:content]
    when "tool_call"
      puts "\nCalling tool: #{event[:data][:name]}"
    end
  }
)
```

## Robot Patterns

### Classifier Robot

Route requests to specialized handlers:

```ruby
classifier = RobotLab.build do
  name "classifier"
  description "Classifies incoming requests"

  template <<~PROMPT
    Analyze the user's message and classify it into exactly one category:
    - BILLING: Questions about invoices, payments, subscriptions
    - TECHNICAL: Technical issues, bugs, how-to questions
    - GENERAL: General inquiries, feedback, other

    Respond with only the category name, nothing else.
  PROMPT
end
```

### Specialist Robot

Handle specific domains:

```ruby
billing_specialist = RobotLab.build do
  name "billing_specialist"
  description "Handles billing and payment inquiries"

  template <<~PROMPT
    You are a billing specialist. You help customers with:
    - Invoice questions
    - Payment issues
    - Subscription management

    Always verify the customer's account before making changes.
  PROMPT

  tool :get_invoices do
    description "Get customer's recent invoices"
    parameter :customer_id, type: :string, required: true
    handler { |customer_id:, **_| Invoice.where(customer_id: customer_id).limit(10) }
  end
end
```

### Summarizer Robot

Condense information:

```ruby
summarizer = RobotLab.build do
  name "summarizer"
  description "Summarizes conversations and documents"

  template <<~PROMPT
    Create concise summaries of the provided content.
    Focus on key points and actionable items.
    Use bullet points for clarity.
  PROMPT
end
```

## Best Practices

### 1. Clear, Focused Templates

```ruby
# Good: Specific and focused
template <<~PROMPT
  You are a code reviewer. Review code for:
  - Security vulnerabilities
  - Performance issues
  - Best practice violations

  Provide specific line numbers and suggestions.
PROMPT

# Bad: Vague and unfocused
template "You help with code stuff."
```

### 2. Descriptive Tool Definitions

```ruby
# Good: Clear description and parameter docs
tool :search_users do
  description "Search for users by email, name, or ID. Returns up to 10 matches."
  parameter :query, type: :string, required: true,
            description: "Email address, partial name, or user ID"
end

# Bad: Missing context
tool :search do
  parameter :q, type: :string
end
```

### 3. Handle Tool Errors Gracefully

```ruby
handler do |user_id:, **_|
  user = User.find_by(id: user_id)
  if user
    { success: true, user: user.to_h }
  else
    { success: false, error: "User not found", user_id: user_id }
  end
rescue ActiveRecord::ConnectionError => e
  { success: false, error: "Database unavailable", retry: true }
end
```

## Next Steps

- [Creating Networks](creating-networks.md) - Orchestrate multiple robots
- [Using Tools](using-tools.md) - Advanced tool patterns
- [API Reference: Robot](../api/core/robot.md) - Complete API documentation
