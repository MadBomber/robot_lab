# Multi-Robot Network

Customer service system with intelligent routing.

## Overview

This example demonstrates a multi-robot network where a classifier routes customer inquiries to specialized support robots.

## Complete Example

```ruby
#!/usr/bin/env ruby
# examples/customer_service.rb

require "bundler/setup"
require "robot_lab"

RobotLab.configure do |config|
  config.default_model = "claude-sonnet-4"
end

# Classifier robot - determines the category of inquiry
classifier = RobotLab.build do
  name "classifier"
  description "Classifies customer inquiries"

  template <<~PROMPT
    You are a customer inquiry classifier. Analyze the customer's message
    and respond with exactly ONE of these categories:

    - BILLING (payment issues, invoices, refunds, subscriptions)
    - TECHNICAL (bugs, errors, how-to questions, feature requests)
    - ACCOUNT (login issues, profile changes, security concerns)
    - GENERAL (everything else)

    Respond with ONLY the category name, nothing else.
  PROMPT
end

# Billing specialist
billing_agent = RobotLab.build do
  name "billing_agent"
  description "Handles billing inquiries"

  template <<~PROMPT
    You are a billing support specialist. You help customers with:
    - Payment issues and refunds
    - Invoice questions
    - Subscription management
    - Pricing inquiries

    Be helpful, empathetic, and provide clear next steps.
  PROMPT
end

# Technical support
tech_agent = RobotLab.build do
  name "tech_agent"
  description "Handles technical issues"

  template <<~PROMPT
    You are a technical support specialist. You help customers with:
    - Bug reports and troubleshooting
    - Feature explanations
    - Integration questions
    - Best practices

    Ask clarifying questions when needed. Provide step-by-step solutions.
  PROMPT
end

# Account specialist
account_agent = RobotLab.build do
  name "account_agent"
  description "Handles account issues"

  template <<~PROMPT
    You are an account support specialist. You help customers with:
    - Login and authentication issues
    - Profile and settings changes
    - Security concerns
    - Account recovery

    Prioritize security while being helpful.
  PROMPT
end

# General support
general_agent = RobotLab.build do
  name "general_agent"
  description "Handles general inquiries"

  template <<~PROMPT
    You are a general support agent. You help customers with:
    - Product information
    - General questions
    - Feedback collection
    - Routing to appropriate departments

    Be friendly and informative.
  PROMPT
end

# Create the network with routing
network = RobotLab.create_network do
  name "customer_service"

  add_robot classifier
  add_robot billing_agent
  add_robot tech_agent
  add_robot account_agent
  add_robot general_agent

  router ->(args) {
    case args.call_count
    when 0
      # First call: classify the inquiry
      :classifier
    when 1
      # Second call: route to appropriate specialist
      category = args.last_result&.output&.first&.content&.strip&.upcase

      case category
      when "BILLING" then :billing_agent
      when "TECHNICAL" then :tech_agent
      when "ACCOUNT" then :account_agent
      else :general_agent
      end
    else
      # Done after specialist responds
      nil
    end
  }
end

# Run the support system
puts "Customer Service System"
puts "=" * 50
puts

test_inquiries = [
  "I was charged twice for my subscription last month",
  "How do I reset my password?",
  "The app crashes when I try to upload photos",
  "What features are included in the pro plan?"
]

test_inquiries.each do |inquiry|
  puts "Customer: #{inquiry}"
  puts "-" * 50

  state = RobotLab.create_state(message: inquiry)

  network.run(state: state) do |event|
    case event.type
    when :robot_start
      puts "[#{event.robot_name}] Processing..."
    when :text_delta
      print event.text if event.robot_name != "classifier"
    when :robot_complete
      puts if event.robot_name != "classifier"
    end
  end

  puts
  puts "=" * 50
  puts
end
```

## With Shared Memory

```ruby
# Enhanced version with shared context between robots

network = RobotLab.create_network do
  name "customer_service_v2"

  add_robot classifier
  add_robot billing_agent
  add_robot tech_agent

  router ->(args) {
    case args.call_count
    when 0
      :classifier
    when 1
      # Store classification in memory for specialist
      category = args.last_result&.output&.first&.content&.strip
      args.network.state.memory.remember("SHARED:category", category)
      args.network.state.memory.remember("SHARED:original_message",
        args.context[:message])

      case category&.upcase
      when "BILLING" then :billing_agent
      when "TECHNICAL" then :tech_agent
      else :general_agent
      end
    end
  }
end

# Specialist can access shared memory
billing_agent = RobotLab.build do
  name "billing_agent"
  template <<~PROMPT
    You handle billing questions.
    The inquiry was classified as: {{state.memory.recall("SHARED:category")}}
  PROMPT
end
```

## With Fallback Routing

```ruby
router ->(args) {
  case args.call_count
  when 0
    :classifier
  when 1
    category = args.last_result&.output&.first&.content&.strip&.upcase

    # Try specific agent first, fallback to general
    specific = {
      "BILLING" => :billing_agent,
      "TECHNICAL" => :tech_agent
    }[category]

    if specific && args.network.network.robots.key?(specific.to_s)
      specific
    else
      :general_agent
    end
  end
}
```

## With Consensus (Multiple Agents)

```ruby
# Get opinions from multiple specialists
router ->(args) {
  case args.call_count
  when 0
    # Run multiple specialists in parallel
    [:billing_agent, :tech_agent]
  when 1
    # Summarizer combines their responses
    :summarizer
  end
}

summarizer = RobotLab.build do
  name "summarizer"
  template <<~PROMPT
    Review the responses from our specialists and provide a
    comprehensive answer that incorporates their insights.
  PROMPT
end
```

## Running

```bash
export ANTHROPIC_API_KEY="your-key"
ruby examples/customer_service.rb
```

## Key Concepts

1. **Multiple Robots**: Each specialist handles specific domains
2. **Classifier**: Routes inquiries to appropriate specialist
3. **Router Function**: Controls execution flow based on results
4. **Streaming**: Shows real-time progress across robots

## See Also

- [Creating Networks Guide](../guides/creating-networks.md)
- [Memory Guide](../guides/memory.md)
- [Robot](../api/core/robot.md)
