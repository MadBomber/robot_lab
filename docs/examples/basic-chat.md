# Basic Chat

A simple conversational robot example.

## Overview

This example demonstrates the minimal setup for a conversational robot that can respond to user messages using `robot.run("message")`.

The closest runnable file in this repository is
[`examples/01_simple_robot.rb`](https://github.com/MadBomber/robot_lab/blob/main/examples/01_simple_robot.rb).
The snippets below wrap that same API in a small REPL.

## Complete Example

```ruby
#!/usr/bin/env ruby

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

Pass a block to `run` to receive each `RubyLLM::Chunk` as it arrives.

> [!WARNING]
> The yielded object is a `RubyLLM::Chunk`. Read its text with `chunk.content`.
> There is no `chunk.text` method — a guard like `if chunk.respond_to?(:text)`
> silently prints nothing.

```ruby
#!/usr/bin/env ruby

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
  assistant.run(input) { |chunk| print chunk.content }
  puts
end

puts "\nGoodbye!"
```

You can also wire streaming once at build time with the `on_content:` callback,
which fires on every `run`:

```ruby
assistant = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful assistant.",
  on_content: ->(chunk) { print chunk.content }
)

assistant.run("Tell me a one-sentence fact about Ruby.")
```

When both are supplied, the stored `on_content` callback fires first, then the
block. See [`examples/05_streaming.rb`](https://github.com/MadBomber/robot_lab/blob/main/examples/05_streaming.rb)
for all four variations (stored callback, per-call block, both, and via `RunConfig`).

## With Template

Templates are `.md` files with YAML front matter, resolved from the configured
prompts directory (`ROBOT_LAB_TEMPLATE_PATH`). Parameters declared `null` in the
front matter are required and are supplied via `context:`.

```ruby
#!/usr/bin/env ruby

require "bundler/setup"
require "robot_lab"

# Template file: prompts/support.md
# ---
# description: Support assistant
# parameters:
#   company_name: null
#   tone: friendly
# ---
# You are a <%= tone %> support assistant for <%= company_name %>.

assistant = RobotLab.build(
  name: "assistant",
  template: :support,
  context: { company_name: "Acme Corp", tone: "friendly" },
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

A full template-driven network lives in
[`examples/06_prompt_templates.rb`](https://github.com/MadBomber/robot_lab/blob/main/examples/06_prompt_templates.rb).

## With Memory

```ruby
#!/usr/bin/env ruby

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

The full Memory API — subscriptions, `StateProxy`, blocking reads, clone and
reset — is demonstrated in
[`examples/10_memory.rb`](https://github.com/MadBomber/robot_lab/blob/main/examples/10_memory.rb).

## Bare Robot with Chaining

```ruby
#!/usr/bin/env ruby

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

> [!NOTE]
> Only the `with_*` methods that `RubyLLM::Chat` exposes are delegated:
> `with_context`, `with_headers`, `with_instructions`, `with_model`, `with_params`,
> `with_schema`, `with_temperature`, `with_thinking`, `with_tool`, `with_tools`
> (plus RobotLab's own `with_template` and `with_bus`).
> There is no `with_max_tokens` / `with_top_p` / `with_top_k` — use a constructor
> kwarg (`max_tokens: 2000`) or `with_params(max_tokens: 2000, top_p: 0.3)`.

`examples/09_chaining.rb` walks through chaining and reconfiguration without
making any LLM calls.

## Running

```bash
# Set API key
export ANTHROPIC_API_KEY="your-key"

# Simplest runnable robot
ruby examples/01_simple_robot.rb

# Streaming
ruby examples/05_streaming.rb

# with_* chaining and reconfiguration (no LLM calls)
ruby examples/09_chaining.rb
```

## Key Concepts

1. **Robot Building**: Use `RobotLab.build(name:, system_prompt:)` or `RobotLab.build(name:, template:)` to create a robot
2. **Execution**: Call `robot.run("message")` to send a message and get a response
3. **Response**: Access the text via `result.last_text_content` (aliased as `result.reply`)
4. **Streaming**: Pass a block to `robot.run("message") { |chunk| print chunk.content }`, or set `on_content:` at build time
5. **Memory**: Access inherent memory via `robot.memory[:key]`
6. **Chaining**: Configure with the delegated `with_*` methods, which return `self`
7. **Conversation History**: The persistent `@chat` maintains history across multiple `run` calls

## See Also

- [Building Robots Guide](../guides/building-robots.md)
- [Streaming Guide](../guides/streaming.md)
- [Robot API Reference](../api/core/robot.md)
