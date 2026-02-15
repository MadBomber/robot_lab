# Multi-Robot Network

Customer service system with intelligent routing using SimpleFlow pipelines.

## Overview

This example demonstrates a multi-robot network where a classifier routes customer inquiries to specialized support robots using SimpleFlow's optional task activation.

## Complete Example

```ruby
#!/usr/bin/env ruby
# examples/customer_service.rb

require "bundler/setup"
require "robot_lab"

# Custom classifier that routes to specialists
class ClassifierRobot < RobotLab::Robot
  def call(result)
    context = extract_run_context(result)
    message = context.delete(:message)
    robot_result = run(message, **context)

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
  system_prompt: <<~PROMPT,
    You are a customer inquiry classifier. Analyze the customer's message
    and respond with exactly ONE of these categories:

    - BILLING (payment issues, invoices, refunds, subscriptions)
    - TECHNICAL (bugs, errors, how-to questions, feature requests)
    - ACCOUNT (login issues, profile changes, security concerns)
    - GENERAL (everything else)

    Respond with ONLY the category name, nothing else.
  PROMPT
  model: "claude-sonnet-4"
)

# Billing specialist
billing_agent = RobotLab.build(
  name: "billing_agent",
  description: "Handles billing inquiries",
  system_prompt: <<~PROMPT,
    You are a billing support specialist. You help customers with:
    - Payment issues and refunds
    - Invoice questions
    - Subscription management
    - Pricing inquiries

    Be helpful, empathetic, and provide clear next steps.
  PROMPT
  model: "claude-sonnet-4"
)

# Technical support
tech_agent = RobotLab.build(
  name: "tech_agent",
  description: "Handles technical issues",
  system_prompt: <<~PROMPT,
    You are a technical support specialist. You help customers with:
    - Bug reports and troubleshooting
    - Feature explanations
    - Integration questions
    - Best practices

    Ask clarifying questions when needed. Provide step-by-step solutions.
  PROMPT
  model: "claude-sonnet-4"
)

# Account specialist
account_agent = RobotLab.build(
  name: "account_agent",
  description: "Handles account issues",
  system_prompt: <<~PROMPT,
    You are an account support specialist. You help customers with:
    - Login and authentication issues
    - Profile and settings changes
    - Security concerns
    - Account recovery

    Prioritize security while being helpful.
  PROMPT
  model: "claude-sonnet-4"
)

# General support
general_agent = RobotLab.build(
  name: "general_agent",
  description: "Handles general inquiries",
  system_prompt: <<~PROMPT,
    You are a general support agent. You help customers with:
    - Product information
    - General questions
    - Feedback collection
    - Routing to appropriate departments

    Be friendly and informative.
  PROMPT
  model: "claude-sonnet-4"
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

## ClassifierRobot Pattern

The key to conditional routing is overriding the `call` method. The base `Robot#call` extracts the message from the `SimpleFlow::Result` and calls `run`. A classifier overrides this to inspect the output and activate the appropriate optional task:

```ruby
class ClassifierRobot < RobotLab::Robot
  def call(result)
    # 1. Extract run context from the SimpleFlow result
    context = extract_run_context(result)

    # 2. Pull out the message (it's a key in the context hash)
    message = context.delete(:message)

    # 3. Run the robot to get a classification
    robot_result = run(message, **context)

    # 4. Store our result and continue the pipeline
    new_result = result
      .with_context(@name.to_sym, robot_result)
      .continue(robot_result)

    # 5. Activate the appropriate optional task based on output
    category = robot_result.last_text_content.to_s.strip.downcase
    case category
    when /billing/ then new_result.activate(:billing)
    when /technical/ then new_result.activate(:technical)
    else new_result.activate(:general)
    end
  end
end
```

!!! note "extract_run_context"
    The `extract_run_context(result)` method is a protected helper on `Robot`. It extracts `run_params` from the SimpleFlow result context, handles value propagation from previous steps, and separates robot-specific params (`mcp:`, `tools:`, `memory:`, `network_memory:`) from the message and other context.

## With Context Passing

Enhanced version where the classifier passes additional context to specialists:

```ruby
class ContextAwareClassifier < RobotLab::Robot
  def call(result)
    context = extract_run_context(result)
    message = context.delete(:message)
    robot_result = run(message, **context)

    # Store classification and original message in context for specialist
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

    context = extract_run_context(result)
    message = context.delete(:message)

    robot_result = run(message, **context)

    result.with_context(@name.to_sym, robot_result).continue(robot_result)
  end
end
```

## Per-Task Configuration

Tasks can have individual context, tools, and MCP servers:

```ruby
network = RobotLab.create_network(name: "support") do
  task :classifier, classifier, depends_on: :none
  task :billing_agent, billing_agent,
       context: { department: "billing", escalation_level: 2 },
       tools: [RefundTool, InvoiceTool],
       depends_on: :optional
  task :tech_agent, tech_agent,
       context: { department: "technical" },
       mcp: [filesystem_server],
       depends_on: :optional
end
```

The `Task` wrapper deep-merges per-task context with the network's run params before delegating to the robot's `call` method.

## Pipeline Pattern

Sequential processing pipeline where each robot depends on the previous:

```ruby
extractor = RobotLab.build(
  name: "extractor",
  system_prompt: "Extract key information from documents."
)

analyzer = RobotLab.build(
  name: "analyzer",
  system_prompt: "Analyze extracted data and provide insights."
)

formatter = RobotLab.build(
  name: "formatter",
  system_prompt: "Format analysis results into a clear report."
)

network = RobotLab.create_network(name: "document_processor") do
  task :extract, extractor, depends_on: :none
  task :analyze, analyzer, depends_on: [:extract]
  task :format, formatter, depends_on: [:analyze]
end

result = network.run(message: "Process this document")
puts result.value.last_text_content
```

## Parallel Analysis Pattern

Fan-out / fan-in pattern where multiple robots analyze in parallel and a synthesizer merges results:

```ruby
network = RobotLab.create_network(name: "multi_analysis") do
  task :prepare, preparer, depends_on: :none

  # These run in parallel (all depend on :prepare)
  task :sentiment, sentiment_analyzer, depends_on: [:prepare]
  task :entities, entity_extractor, depends_on: [:prepare]
  task :keywords, keyword_extractor, depends_on: [:prepare]

  # Waits for all three to complete
  task :summarize, summarizer, depends_on: [:sentiment, :entities, :keywords]
end

result = network.run(message: "Analyze this text")

# Access parallel results from context
puts "Sentiment: #{result.context[:sentiment].last_text_content}"
puts "Entities: #{result.context[:entities].last_text_content}"
puts "Keywords: #{result.context[:keywords].last_text_content}"
puts "Summary: #{result.value.last_text_content}"
```

## Shared Memory in Networks

Networks provide a shared `Memory` instance that all robots can read and write. This is especially useful for parallel robots that need to coordinate:

```ruby
class AnalysisRobot < RobotLab::Robot
  def initialize(memory_key:, **opts)
    super(**opts)
    @memory_key = memory_key
  end

  def call(result)
    context = extract_run_context(result)
    network_memory = context.delete(:network_memory)
    message = context.delete(:message)

    robot_result = run(message, network_memory: network_memory, **context)

    # Write parsed results to shared memory
    if network_memory
      network_memory.current_writer = @name
      network_memory.set(@memory_key, robot_result.last_text_content)
    end

    result.with_context(@name.to_sym, robot_result).continue(robot_result)
  end
end
```

## Conditional Halting

Use `result.halt` to stop the pipeline early:

```ruby
class ValidatorRobot < RobotLab::Robot
  def call(result)
    context = extract_run_context(result)
    message = context.delete(:message)
    robot_result = run(message, **context)

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

1. **SimpleFlow Pipeline**: DAG-based execution with dependency management via `depends_on:`
2. **Optional Tasks**: Use `depends_on: :optional` for tasks activated dynamically by classifiers
3. **Robot#call Override**: Custom routing logic in classifier robots that override the `call` method
4. **extract_run_context**: Helper method to extract message and params from `SimpleFlow::Result`
5. **Context Flow**: Data passed through `result.context` and accessed by downstream robots
6. **Parallel Execution**: Tasks with the same dependencies run concurrently
7. **Shared Memory**: Network memory (`network_memory:`) enables inter-robot communication
8. **Per-Task Configuration**: Each task can have its own context, tools, and MCP servers via `Task`

## See Also

- [Creating Networks Guide](../guides/creating-networks.md)
- [Network Orchestration](../architecture/network-orchestration.md)
- [API Reference: Network](../api/core/network.md)
