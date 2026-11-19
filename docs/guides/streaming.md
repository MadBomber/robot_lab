# Streaming Responses

Stream LLM responses in real-time for better user experience.

RobotLab has exactly two ways to receive streaming content, and both hand you a
`RubyLLM::Chunk`:

1. **`on_content:`** — a callback wired at build time (or through `RunConfig`) that fires on *every* `run`
2. **A block passed to `run`** — `robot.run(msg) { |chunk| ... }`, for one-off streaming

> [!IMPORTANT]
> Read the content off the chunk with **`chunk.content`**. `RubyLLM::Chunk`
> has no `#text` method — `chunk.text` raises `NoMethodError`.

## Streaming via `on_content:`

Wire the callback once at build time; it fires on every subsequent `run`:

```ruby
robot = RobotLab.build(
  name: "storyteller",
  system_prompt: "You are a creative storyteller.",
  on_content: ->(chunk) { print chunk.content }
)

result = robot.run("Tell me a story about a brave robot")
puts
puts result.last_text_content
```

## Streaming via a Block on `run`

For one-off streaming, pass a block straight to `run`:

```ruby
robot = RobotLab.build(
  name: "factbot",
  system_prompt: "You are concise. Answer in one sentence."
)

robot.run("What year was Ruby created?") { |chunk| print chunk.content }
```

The block goes to the same place `on_content:` does — no need to reach for
`robot.chat.ask` to get streaming, and reaching for it skips memory resolution,
tool resolution, hooks, and budget accounting.

## Using Both Together

When a robot has a stored `on_content:` *and* a block is passed to `run`, both
fire for every chunk. The **stored callback fires first**, then the block:

```ruby
stored_log = []
block_log  = []

robot = RobotLab.build(
  name: "combo",
  system_prompt: "You are concise.",
  on_content: ->(chunk) { stored_log << chunk.content }
)

robot.run("What is Matz's full name?") { |chunk| block_log << chunk.content }

stored_log == block_log   # => true — both saw the same chunks
```

## Streaming via RunConfig

`on_content` is a `RunConfig` field, so it participates in the config cascade:

```ruby
config = RobotLab::RunConfig.new(
  model: "claude-sonnet-4",
  on_content: ->(chunk) { print chunk.content }
)

robot = RobotLab.build(
  name: "config_bot",
  system_prompt: "You are concise.",
  config: config
)

robot.run("Who designed the Ruby programming language?")
```

> [!WARNING]
> `on_content` is read from the **robot's own** config when the robot is
> constructed. A network-level `config:` propagates only `mcp` and `tools` to
> member robots — it will **not** supply `on_content` to them. Put the callback
> on each robot (or on the `config:` you pass to that robot).

## Web Integration

### Rails Action Cable

```ruby
class ChatChannel < ApplicationCable::Channel
  def receive(data)
    robot = RobotLab.build(
      name: "chat_bot",
      system_prompt: "You are a helpful chat assistant.",
      on_content: ->(chunk) {
        transmit({ event: "text.delta", content: chunk.content })
      }
    )

    robot.run(data["message"])
    transmit({ event: "run.completed" })
  end
end
```

### Server-Sent Events

```ruby
class StreamController < ApplicationController
  include ActionController::Live

  def create
    response.headers["Content-Type"] = "text/event-stream"

    robot = RobotLab.build(
      name: "stream_bot",
      system_prompt: "You are helpful."
    )

    robot.run(params[:message]) do |chunk|
      response.stream.write("data: #{chunk.content}\n\n")
    end

    response.stream.write("data: [DONE]\n\n")
  ensure
    response.stream.close
  end
end
```

### WebSocket

```ruby
# Using Faye WebSocket
ws.on :message do |msg|
  robot.run(msg.data) { |chunk| ws.send(chunk.content) }
end
```

## Progress Tracking

Chunk callbacks are the right place to count characters. Tool activity is
tracked separately, through the robot's `on_tool_call:` / `on_tool_result:`
callbacks:

```ruby
class StreamProgress
  attr_reader :chars, :tools

  def initialize
    @chars = 0
    @tools = 0
  end

  # Returns the streaming block to hand to run().
  def content_callback
    ->(chunk) {
      @chars += chunk.content.to_s.length
      print "\rReceived #{@chars} characters..."
    }
  end

  def tool_callback
    ->(tool_call) {
      @tools += 1
      puts "\nTool call ##{@tools}: #{tool_call.name}"
    }
  end
end

progress = StreamProgress.new

robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are helpful.",
  local_tools: [WeatherTool],
  on_content:   progress.content_callback,
  on_tool_call: progress.tool_callback
)

robot.run("Process this complex request", tools: :inherit)
puts "\nTotal: #{progress.chars} chars, #{progress.tools} tool calls"
```

> [!NOTE]
> `chunk.content` can be `nil` on chunks that carry only metadata (tool-call
> deltas, usage). Guard with `to_s` when accumulating, as above.

> [!WARNING]
> `run` defaults to `tools: :none`, so the tool callback above never fires
> unless you pass `tools: :inherit` (or an explicit allowlist). See
> [Using Tools](using-tools.md#runtime-tool-filtering).

## Without Streaming

When streaming is not needed, call `run` with no `on_content:` and no block:

```ruby
result = robot.run("Hello!")
puts result.last_text_content
```

## Tool Callbacks

`on_tool_call:` and `on_tool_result:` are constructor/`RunConfig` callbacks
alongside `on_content:`. Each receives **one** argument:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are helpful.",
  local_tools: [WeatherTool],
  on_tool_call:   ->(tool_call) { puts "\n[Tool] Calling: #{tool_call.name}" },
  on_tool_result: ->(result)    { puts "[Tool] returned: #{result}" }
)

robot.run("What's the weather in Tokyo?", tools: :inherit)
```

Note that `on_tool_result` does **not** receive the originating tool call —
only the result. If you need to correlate the two, record the call in
`on_tool_call` and pair them up yourself.

> [!NOTE]
> RobotLab installs these two callbacks on the underlying chat's
> `on_tool_call` / `on_tool_result` hooks, which RubyLLM 1.16 has deprecated.
> Building a robot with either callback therefore prints a RubyLLM deprecation
> warning. The callbacks themselves work; the warning comes from the layer
> below.

## Legacy RubyLLM Chat Callbacks

`Robot` also exposes RubyLLM's chat-level callbacks
(`on_new_message`, `on_end_message`, `on_tool_call`, `on_tool_result`).

> [!CAUTION]
> All four are **deprecated in RubyLLM 1.16** and slated for removal in
> RubyLLM 2.0. Registering one emits a deprecation warning naming its
> replacement: `before_message`, `after_message`, `before_tool_call`, and
> `after_tool_result`. Prefer RobotLab's `on_content:` /
> `on_tool_call:` / `on_tool_result:` constructor callbacks instead.

Their arities are not what you might expect:

| Callback | Replacement | Arguments received |
|----------|-------------|--------------------|
| `on_new_message` | `before_message` | **none** |
| `on_end_message` | `after_message` | the completed `RubyLLM::Message` |
| `on_tool_call` | `before_tool_call` | the `ToolCall` |
| `on_tool_result` | `after_tool_result` | the **result only** |

> [!WARNING]
> `on_new_message` is **not** a streaming hook. It fires once when a message
> begins and is invoked with **zero arguments** — a block written as
> `do |message| ... end` receives `nil`, so `message.content` raises
> `NoMethodError: undefined method 'content' for nil`. Use `on_content:` or a
> `run` block for content.

```ruby
# Correct usage of the legacy hooks (still deprecated):
robot.chat.on_new_message { puts "--- message starting ---" }   # no argument
robot.chat.on_end_message { |message| puts "Length: #{message.content&.length}" }
robot.chat.on_tool_result { |result| puts "Tool returned: #{result}" }
```

## Best Practices

### 1. Wire streaming before the run

`on_content:` belongs in the constructor (or the `config:` you pass it); a
`run` block belongs on the call itself. There is no "register then run" step.

### 2. Handle errors inside the callback

An exception raised in a streaming callback propagates out of `run` and aborts
the turn. Swallow client-side failures you can survive:

```ruby
robot = RobotLab.build(
  name: "broadcaster",
  system_prompt: "You are helpful.",
  on_content: ->(chunk) do
    broadcast(chunk.content)
  rescue BroadcastError => e
    # Client disconnected, but let the run finish.
    RobotLab.config.logger.warn("Broadcast failed: #{e.message}")
  end
)
```

### 3. Clean up resources

```ruby
begin
  robot.run("Hello") { |chunk| stream_to_client(chunk.content) }
ensure
  close_stream_connection
end
```

## What About `RobotLab::Streaming`?

`RobotLab::Streaming::Context`, `Streaming::Events`, and
`Streaming::SequenceCounter` exist in the codebase and are documented in the
[API reference](../api/streaming/index.md), but **nothing in `Robot` or
`Network` constructs or publishes to them**. They are a standalone event-object
toolkit you would have to drive yourself — not the path that `run` takes. For
actual token streaming, use `on_content:` or a `run` block as shown above.

## Next Steps

- [Building Robots](building-robots.md) - Robot creation
- [Creating Networks](creating-networks.md) - Network patterns
- [examples/05_streaming.rb](https://github.com/MadBomber/robot_lab/blob/main/examples/05_streaming.rb) - Runnable streaming example
- [API Reference: Streaming](../api/streaming/index.md) - The standalone `Streaming::*` event objects
