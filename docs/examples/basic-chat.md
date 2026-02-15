# Basic Chat

A simple conversational robot example.

## Overview

This example demonstrates the minimal setup for a conversational robot that can respond to user messages using `robot.run("message")`.

## Complete Example

```ruby
#!/usr/bin/env ruby
# examples/basic_chat.rb

require "bundler/setup"
require "robot_lab"

# Build a simple assistant
assistant = RobotLab.build(
  name: "assistant",
  description: "A helpful conversational assistant",
  system_prompt: <<~PROMPT,
    You are a helpful, friendly assistant. You provide clear,
    concise answers to questions. Be conversational but informative.
  PROMPT
  model: "claude-sonnet-4"
)

# Simple REPL
puts "Chat with the assistant (type 'quit' to exit)"
puts "-" * 50

loop do
  print "\nYou: "
  input = gets&.chomp

  break if input.nil? || input.downcase == "quit"
  next if input.empty?

  # Run the robot with the user's message
  result = assistant.run(input)

  # Display response
  puts "\nAssistant: #{result.last_text_content}"
end

puts "\nGoodbye!"
```

## With Streaming

```ruby
#!/usr/bin/env ruby
# examples/streaming_chat.rb

require "bundler/setup"
require "robot_lab"

assistant = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful assistant.",
  model: "claude-sonnet-4"
)

puts "Chat with streaming (type 'quit' to exit)"
puts "-" * 50

loop do
  print "\nYou: "
  input = gets&.chomp

  break if input.nil? || input.downcase == "quit"
  next if input.empty?

  print "\nAssistant: "
  result = assistant.run(input) do |event|
    print event.text if event.respond_to?(:text)
  end
  puts
end

puts "\nGoodbye!"
```

## With Template

```ruby
#!/usr/bin/env ruby
# examples/template_chat.rb

require "bundler/setup"
require "robot_lab"

# Build a robot using a prompt template file
# Template: prompts/assistant.md (Markdown with YAML front matter)
assistant = RobotLab.build(
  name: "assistant",
  template: :assistant,
  context: { tone: "friendly", domain: "general" },
  model: "claude-sonnet-4"
)

puts "Chat with template-based assistant (type 'quit' to exit)"
puts "-" * 50

loop do
  print "\nYou: "
  input = gets&.chomp

  break if input.nil? || input.downcase == "quit"
  next if input.empty?

  result = assistant.run(input)
  puts "\nAssistant: #{result.last_text_content}"
end

puts "\nGoodbye!"
```

## With Memory

```ruby
#!/usr/bin/env ruby
# examples/chat_with_memory.rb

require "bundler/setup"
require "robot_lab"

assistant = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful assistant. Use the user's name when you know it.",
  model: "claude-sonnet-4"
)

puts "Chat with memory (type 'quit' to exit)"
puts "-" * 50

# Store user info in the robot's inherent memory
assistant.memory[:user_name] = "Alice"

loop do
  print "\nYou: "
  input = gets&.chomp

  break if input.nil? || input.downcase == "quit"
  next if input.empty?

  # The robot's persistent @chat maintains conversation history automatically
  result = assistant.run(input)
  puts "\nAssistant: #{result.last_text_content}"
end

puts "\nGoodbye!"
```

## Bare Robot with Chaining

```ruby
#!/usr/bin/env ruby
# examples/bare_robot.rb

require "bundler/setup"
require "robot_lab"

# Build a bare robot with no template or prompt
robot = RobotLab.build(name: "bot")

# Configure via chaining
result = robot
  .with_model("claude-sonnet-4")
  .with_temperature(0.7)
  .with_instructions("You are a pirate. Respond in pirate speak.")
  .run("What is the weather like today?")

puts result.last_text_content
```

## Running

```bash
# Set API key
export ANTHROPIC_API_KEY="your-key"

# Run basic chat
ruby examples/basic_chat.rb

# Run with streaming
ruby examples/streaming_chat.rb
```

## Key Concepts

1. **Robot Building**: Use `RobotLab.build(name:, system_prompt:)` or `RobotLab.build(name:, template:)` to create a robot
2. **Execution**: Call `robot.run("message")` to send a message and get a response
3. **Response**: Access the text via `result.last_text_content`
4. **Streaming**: Pass a block to `robot.run("message") { |event| ... }`
5. **Memory**: Access inherent memory via `robot.memory[:key]`
6. **Chaining**: Configure with `with_*` methods that return `self`
7. **Conversation History**: The persistent `@chat` maintains history across multiple `run` calls

## See Also

- [Building Robots Guide](../guides/building-robots.md)
- [Streaming Guide](../guides/streaming.md)
- [Robot API Reference](../api/core/robot.md)
