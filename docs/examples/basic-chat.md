# Basic Chat

A simple conversational robot example.

## Overview

This example demonstrates the minimal setup for a conversational robot that can respond to user messages.

## Complete Example

```ruby
#!/usr/bin/env ruby
# examples/basic_chat.rb

require "bundler/setup"
require "robot_lab"

# Configure RobotLab
RobotLab.configure do |config|
  config.default_model = "claude-sonnet-4"
end

# Build a simple assistant
assistant = RobotLab.build do
  name "assistant"
  description "A helpful conversational assistant"

  template <<~PROMPT
    You are a helpful, friendly assistant. You provide clear,
    concise answers to questions. Be conversational but informative.
  PROMPT
end

# Simple REPL
puts "Chat with the assistant (type 'quit' to exit)"
puts "-" * 50

loop do
  print "\nYou: "
  input = gets&.chomp

  break if input.nil? || input.downcase == "quit"
  next if input.empty?

  # Create state and run
  state = RobotLab.create_state(message: input)
  result = assistant.run(state: state)

  # Display response
  response = result.output.first&.content || "No response"
  puts "\nAssistant: #{response}"
end

puts "\nGoodbye!"
```

## With Streaming

```ruby
#!/usr/bin/env ruby
# examples/streaming_chat.rb

require "bundler/setup"
require "robot_lab"

RobotLab.configure do |config|
  config.default_model = "claude-sonnet-4"
end

assistant = RobotLab.build do
  name "assistant"
  template "You are a helpful assistant."
end

puts "Chat with streaming (type 'quit' to exit)"
puts "-" * 50

loop do
  print "\nYou: "
  input = gets&.chomp

  break if input.nil? || input.downcase == "quit"
  next if input.empty?

  state = RobotLab.create_state(message: input)

  print "\nAssistant: "
  assistant.run(state: state) do |event|
    print event.text if event.type == :text_delta
  end
  puts
end

puts "\nGoodbye!"
```

## With Conversation History

```ruby
#!/usr/bin/env ruby
# examples/chat_with_memory.rb

require "bundler/setup"
require "robot_lab"

RobotLab.configure do |config|
  config.default_model = "claude-sonnet-4"
end

assistant = RobotLab.build do
  name "assistant"
  template "You are a helpful assistant with memory of our conversation."
end

# In-memory history store
HISTORY = {}

history_config = RobotLab::History::Config.new(
  create_thread: ->(state:, **) {
    id = SecureRandom.uuid
    HISTORY[id] = []
    { id: id }
  },
  get: ->(thread_id:, **) {
    HISTORY[thread_id] || []
  },
  append_results: ->(thread_id:, new_results:, **) {
    HISTORY[thread_id].concat(new_results.map(&:to_h))
  }
)

network = RobotLab.create_network do
  name "chat"
  history history_config
  add_robot assistant
end

puts "Chat with memory (type 'quit' to exit)"
puts "-" * 50

thread_id = nil

loop do
  print "\nYou: "
  input = gets&.chomp

  break if input.nil? || input.downcase == "quit"
  next if input.empty?

  message = thread_id ?
    RobotLab::UserMessage.new(input, thread_id: thread_id) :
    input

  state = RobotLab.create_state(message: message)
  result = network.run(state: state)

  thread_id ||= result.state.thread_id

  response = result.last_result&.output&.first&.content || "No response"
  puts "\nAssistant: #{response}"
end

puts "\nGoodbye!"
```

## Running

```bash
# Set API key
export ANTHROPIC_API_KEY="your-key"

# Run basic chat
ruby examples/basic_chat.rb

# Run with streaming
ruby examples/streaming_chat.rb

# Run with memory
ruby examples/chat_with_memory.rb
```

## Key Concepts

1. **Robot Building**: Use `RobotLab.build` with a template
2. **State Creation**: Use `RobotLab.create_state` with a message
3. **Execution**: Call `robot.run(state: state)`
4. **Response**: Access via `result.output.first.content`

## See Also

- [Building Robots Guide](../guides/building-robots.md)
- [Streaming Guide](../guides/streaming.md)
- [History Guide](../guides/history.md)
