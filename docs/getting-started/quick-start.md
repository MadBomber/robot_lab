# Quick Start

Build your first RobotLab application in 5 minutes.

## Step 1: Configure RobotLab

First, set up your API credentials:

```ruby
require "robot_lab"

RobotLab.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.default_model = "claude-sonnet-4"
end
```

## Step 2: Create a Robot

Build a simple assistant robot:

```ruby
assistant = RobotLab.build do
  name "assistant"
  description "A helpful AI assistant"

  template <<~PROMPT
    You are a helpful AI assistant. You provide clear, accurate,
    and concise answers to questions. Be friendly but professional.
  PROMPT
end
```

## Step 3: Create a Network

Add your robot to a network:

```ruby
network = RobotLab.create_network do
  name "my_first_network"
  add_robot assistant
end
```

## Step 4: Run It!

Execute the network with a message:

```ruby
# Create state with your message
state = RobotLab.create_state(message: "What is Ruby on Rails?")

# Run the network
result = network.run(state: state)

# Get the response
response = result.last_result.output.first.content
puts response
```

## Complete Example

Here's everything together in one file:

```ruby title="hello_robot.rb"
require "robot_lab"

# Configure
RobotLab.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.default_model = "claude-sonnet-4"
end

# Build robot
assistant = RobotLab.build do
  name "assistant"
  description "A helpful AI assistant"
  template "You are a helpful AI assistant."
end

# Create network
network = RobotLab.create_network do
  name "hello_network"
  add_robot assistant
end

# Run
state = RobotLab.create_state(message: "Hello! What can you help me with?")
result = network.run(state: state)

puts result.last_result.output.first.content
```

Run it:

```bash
ruby hello_robot.rb
```

## Adding a Tool

Make your robot more capable with tools:

```ruby
assistant = RobotLab.build do
  name "assistant"
  description "An assistant that can tell time"

  template <<~PROMPT
    You are a helpful assistant. Use the current_time tool
    when users ask about the time.
  PROMPT

  tool :current_time do
    description "Get the current date and time"
    handler { Time.now.strftime("%Y-%m-%d %H:%M:%S") }
  end
end
```

Now the robot can respond to "What time is it?" by calling the tool.

## Multi-Robot Example

Create a network with multiple specialized robots:

```ruby
# Classifier robot
classifier = RobotLab.build do
  name "classifier"
  description "Classifies incoming requests"
  template <<~PROMPT
    Classify the user's request into one category:
    - QUESTION: General knowledge questions
    - MATH: Mathematical calculations
    - OTHER: Everything else

    Respond with only the category name.
  PROMPT
end

# Question answerer
answerer = RobotLab.build do
  name "answerer"
  description "Answers general questions"
  template "You answer general knowledge questions accurately."
end

# Calculator
calculator = RobotLab.build do
  name "calculator"
  description "Handles math problems"
  template "You solve mathematical problems step by step."
end

# Network with routing
network = RobotLab.create_network do
  name "smart_assistant"
  add_robot classifier
  add_robot answerer
  add_robot calculator

  router ->(args) {
    case args.call_count
    when 0
      :classifier
    when 1
      result = args.last_result&.output&.first&.content&.strip
      case result
      when "QUESTION" then :answerer
      when "MATH" then :calculator
      else :answerer
      end
    else
      nil
    end
  }
end
```

## What's Next?

You've built your first RobotLab application! Here's where to go next:

<div class="grid cards" markdown>

-   [:octicons-gear-24: **Configuration**](configuration.md)

    Learn all configuration options

-   [:octicons-cpu-24: **Building Robots**](../guides/building-robots.md)

    Deep dive into robot creation

-   [:octicons-tools-24: **Using Tools**](../guides/using-tools.md)

    Give robots custom capabilities

-   [:octicons-git-branch-24: **Creating Networks**](../guides/creating-networks.md)

    Advanced network patterns

</div>
