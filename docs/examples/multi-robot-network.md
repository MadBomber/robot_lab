# Multi-Robot Network

Customer service system with intelligent routing using SimpleFlow pipelines.

## Overview

This example demonstrates a multi-robot network where a classifier routes customer inquiries to specialized support robots using optional task activation.

## Complete Example

```ruby
#!/usr/bin/env ruby
# examples/customer_service.rb

require "bundler/setup"
require "robot_lab"

RobotLab.configure do |config|
  config.default_model = "claude-sonnet-4"
end

# Custom classifier that routes to specialists
class ClassifierRobot < RobotLab::Robot
  def call(result)
    robot_result = run(**extract_run_context(result))

    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    # Route based on classification
    category = robot_result.last_text_content.to_s.strip.downcase

    case category
    when /billing/ then new_result.activate(:billing_agent)
    when /technical/ then new_result.activate(:tech_agent)
    when /account/ then new_result.activate(:account_agent)
    else new_result.activate(:general_agent)
    end
  end
end

# Classifier robot
classifier = ClassifierRobot.new(
  name: "classifier",
  description: "Classifies customer inquiries",
  system_prompt: <<~PROMPT
    You are a customer inquiry classifier. Analyze the customer's message
    and respond with exactly ONE of these categories:

    - BILLING (payment issues, invoices, refunds, subscriptions)
    - TECHNICAL (bugs, errors, how-to questions, feature requests)
    - ACCOUNT (login issues, profile changes, security concerns)
    - GENERAL (everything else)

    Respond with ONLY the category name, nothing else.
  PROMPT
)

# Billing specialist
billing_agent = RobotLab.build(
  name: "billing_agent",
  description: "Handles billing inquiries",
  system_prompt: <<~PROMPT
    You are a billing support specialist. You help customers with:
    - Payment issues and refunds
    - Invoice questions
    - Subscription management
    - Pricing inquiries

    Be helpful, empathetic, and provide clear next steps.
  PROMPT
)

# Technical support
tech_agent = RobotLab.build(
  name: "tech_agent",
  description: "Handles technical issues",
  system_prompt: <<~PROMPT
    You are a technical support specialist. You help customers with:
    - Bug reports and troubleshooting
    - Feature explanations
    - Integration questions
    - Best practices

    Ask clarifying questions when needed. Provide step-by-step solutions.
  PROMPT
)

# Account specialist
account_agent = RobotLab.build(
  name: "account_agent",
  description: "Handles account issues",
  system_prompt: <<~PROMPT
    You are an account support specialist. You help customers with:
    - Login and authentication issues
    - Profile and settings changes
    - Security concerns
    - Account recovery

    Prioritize security while being helpful.
  PROMPT
)

# General support
general_agent = RobotLab.build(
  name: "general_agent",
  description: "Handles general inquiries",
  system_prompt: <<~PROMPT
    You are a general support agent. You help customers with:
    - Product information
    - General questions
    - Feedback collection
    - Routing to appropriate departments

    Be friendly and informative.
  PROMPT
)

# Create the network with optional task routing
network = RobotLab.create_network(name: "customer_service") do
  task :classifier, classifier, depends_on: :none
  task :billing_agent, billing_agent, depends_on: :optional
  task :tech_agent, tech_agent, depends_on: :optional
  task :account_agent, account_agent, depends_on: :optional
  task :general_agent, general_agent, depends_on: :optional
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

  result = network.run(message: inquiry)

  # Show classification
  if result.context[:classifier]
    puts "Classification: #{result.context[:classifier].last_text_content}"
  end

  # Show specialist response
  if result.value.is_a?(RobotLab::RobotResult)
    puts "Handled by: #{result.value.robot_name}"
    puts "Response: #{result.value.last_text_content[0..200]}..."
  end

  puts
  puts "=" * 50
  puts
end
```

## With Context Passing

```ruby
# Enhanced version with additional context

class ContextAwareClassifier < RobotLab::Robot
  def call(result)
    robot_result = run(**extract_run_context(result))

    # Store classification in context for specialist
    new_result = result
      .with_context(@name.to_sym, robot_result)
      .with_context(:classification, robot_result.last_text_content.strip)
      .with_context(:original_message, result.context[:run_params][:message])
      .continue(robot_result)

    category = robot_result.last_text_content.to_s.downcase
    case category
    when /billing/ then new_result.activate(:billing_agent)
    when /technical/ then new_result.activate(:tech_agent)
    else new_result.activate(:general_agent)
    end
  end
end

# Specialist can access shared context
class BillingAgent < RobotLab::Robot
  def call(result)
    # Access context from classifier
    classification = result.context[:classification]
    original_message = result.context[:original_message]

    robot_result = run(
      **extract_run_context(result),
      classification: classification,
      customer_message: original_message
    )

    result.with_context(@name.to_sym, robot_result).continue(robot_result)
  end
end
```

## Per-Task Configuration

```ruby
# Tasks with individual context and tools
network = RobotLab.create_network(name: "support") do
  task :classifier, classifier, depends_on: :none
  task :billing_agent, billing_agent,
       context: { department: "billing", escalation_level: 2 },
       tools: [RefundTool, InvoiceTool],
       depends_on: :optional
  task :tech_agent, tech_agent,
       context: { department: "technical" },
       mcp: [FilesystemServer],
       depends_on: :optional
end
```

## Pipeline Pattern

```ruby
# Sequential processing pipeline
network = RobotLab.create_network(name: "document_processor") do
  task :extract, extractor, depends_on: :none
  task :analyze, analyzer, depends_on: [:extract]
  task :format, formatter, depends_on: [:analyze]
end

result = network.run(message: "Process this document")
puts result.value.last_text_content
```

## Parallel Analysis Pattern

```ruby
# Fan-out / fan-in pattern
network = RobotLab.create_network(name: "multi_analysis", concurrency: :threads) do
  task :prepare, preparer, depends_on: :none

  # These run in parallel
  task :sentiment, sentiment_analyzer, depends_on: [:prepare]
  task :entities, entity_extractor, depends_on: [:prepare]
  task :keywords, keyword_extractor, depends_on: [:prepare]

  # Waits for all three
  task :summarize, summarizer, depends_on: [:sentiment, :entities, :keywords]
end

result = network.run(message: "Analyze this text")

# Access parallel results
puts "Sentiment: #{result.context[:sentiment].last_text_content}"
puts "Entities: #{result.context[:entities].last_text_content}"
puts "Keywords: #{result.context[:keywords].last_text_content}"
puts "Summary: #{result.value.last_text_content}"
```

## Conditional Halting

```ruby
class ValidatorRobot < RobotLab::Robot
  def call(result)
    robot_result = run(**extract_run_context(result))

    if robot_result.last_text_content.include?("INVALID")
      # Halt the pipeline early
      result.halt(robot_result)
    else
      result.with_context(@name.to_sym, robot_result).continue(robot_result)
    end
  end
end

network = RobotLab.create_network(name: "validated_pipeline") do
  task :validate, validator, depends_on: :none
  task :process, processor, depends_on: [:validate]  # Only runs if not halted
end

result = network.run(message: "Process this")
if result.halted?
  puts "Validation failed: #{result.value.last_text_content}"
else
  puts "Processing complete: #{result.value.last_text_content}"
end
```

## Running

```bash
export ANTHROPIC_API_KEY="your-key"
ruby examples/customer_service.rb
```

## Key Concepts

1. **SimpleFlow Pipeline**: DAG-based execution with dependency management
2. **Optional Tasks**: Activated dynamically based on classification
3. **Robot#call**: Custom routing logic in classifier robots
4. **Context Flow**: Data passed through `result.context`
5. **Parallel Execution**: Tasks with same dependencies run concurrently
6. **Per-Task Configuration**: Each task can have its own context, tools, and MCP servers

## See Also

- [Creating Networks Guide](../guides/creating-networks.md)
- [Network Orchestration](../architecture/network-orchestration.md)
- [API Reference: Network](../api/core/network.md)
