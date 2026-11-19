# RobotResult

`RobotResult` is returned by every `robot.run()` call. It carries the LLM output, tool call results, token usage, timing, and delegation metadata for that execution.

## Accessing the Response

```ruby
result = robot.run("What is the capital of France?")

result.reply              # => "The capital of France is Paris."
result.last_text_content  # => reply is an alias for this
result.output             # => [TextMessage] — see below
result.tool_calls         # => [] in practice — see below
```

`last_text_content` returns the content of the last text message in `output`;
`reply` is an alias for it. This is the string you want for the vast majority of
use cases.

!!! note "`output` is not the full turn"
    `output` is built as `[TextMessage.new(role: "assistant", content: text)]`
    from the **final response text only** — a one-element array, or an empty
    array when there is no text. It never contains the user message, the tool
    calls, or the intermediate assistant turns. Read `robot.messages` for the
    real conversation.

    The text is resolved in this order: `response.content`; then
    `response.thinking.text` (for models that route all output through reasoning
    content, e.g. `qwen3` on Ollama); then the most recent assistant text from
    *the current turn only* in the chat history.

!!! note "`tool_calls` is effectively always empty"
    It is populated from the **final** assistant message, which no longer carries
    tool calls once ruby_llm's tool loop has completed. Consequently
    `has_tool_calls?` is also normally `false`. To observe tool activity, use the
    `on_tool_call:` / `on_tool_result:` callbacks or the `:tool_call` hook family.

There is **no** `text?` predicate and **no** `content` accessor on `RobotResult`.

## Token & Cost Tracking

```ruby
result.input_tokens   # => Integer — tokens sent to the LLM this run
result.output_tokens  # => Integer — tokens generated this run
```

Token counts are zero for providers that do not return usage data.

## Timing

`duration` is set when the result travels through a network pipeline or a `delegate` call. It is `nil` when calling `robot.run()` directly.

```ruby
result.duration  # => Float (elapsed seconds) or nil
```

## Delegation Metadata

When a result comes back through `robot.delegate(to:, task:)`, two additional fields are populated:

```ruby
result.delegated_by  # => "manager"  (the robot that issued the delegation)
result.duration      # => 2.34       (always set by delegate)
```

## Identity & Status

```ruby
result.robot_name   # => "analyst"
result.id           # => "550e8400-e29b-..."  (UUID, unique per run)
result.created_at   # => Time instance
result.stop_reason  # => nil — always, for results built by Robot#run
```

!!! warning "`stop_reason` is always `nil` here"
    `build_result` sets it with
    `response.respond_to?(:stop_reason) ? response.stop_reason : nil`, and
    `RubyLLM::Message` does **not** define `stop_reason`. So every
    `robot.run` result carries `nil`, and `export` drops the key entirely.
    (`RobotLab::Message::VALID_STOP_REASONS` is `["tool", "stop"]`, but that
    constant governs the message classes you construct yourself — it is not
    what a `RobotResult` reports.)

## Inspecting the Output

```ruby
result.output.each do |message|
  puts message.role     # "assistant"
  puts message.content  # String
end

result.has_tool_calls?  # => output.any?(&:tool_call?) || tool_calls.any?
result.stopped?         # => true if execution ended naturally (not mid-tool-call)
```

Because `stop_reason` is always `nil` on a `Robot#run` result, `stopped?`
collapses to `!has_tool_calls?` in practice — and since `tool_calls` is
effectively always empty, it is normally `true`.

## Persistence

Export for serialization (excludes the debug fields):

```ruby
hash = result.export
# {
#   robot_name: "analyst",
#   delegated_by: "manager",
#   output: [...],
#   tool_calls: [...],
#   created_at: "2026-04-18T12:00:00Z",
#   id: "550e8400-...",
#   checksum: "a1b2c3...",
#   # stop_reason is absent — it is nil, and export is .compact-ed
#   duration: 2.34,
#   input_tokens: 512,
#   output_tokens: 128
# }

json = result.to_json   # uses export

hash_with_debug = result.to_h  # export + prompt/history/raw, also compacted

# Reconstruct from hash
restored = RobotLab::RobotResult.from_hash(hash)
```

!!! warning "`export` is `.compact`ed"
    Keys whose value is `nil` are dropped entirely. `delegated_by` and
    `duration` disappear when unset, and `stop_reason` is dropped from
    **every** `Robot#run` result because it is always `nil`. `input_tokens` and
    `output_tokens` are additionally converted to `nil` (and therefore dropped)
    when they are **zero**, so a provider that reports no usage yields a hash
    with no token keys at all:

    ```ruby
    RobotLab::RobotResult.new(robot_name: "a", output: []).export
    # => { robot_name: "a", output: [], tool_calls: [],
    #      created_at: "...", id: "...", checksum: "..." }
    ```

    Only `robot_name`, `output`, `tool_calls`, `created_at`, `id`, and `checksum`
    are always present. Code reading an exported hash must tolerate missing keys.

`checksum` is a SHA-256 hex digest of `{ output:, tool_calls:, created_at: }`
(with `created_at` reduced to an integer epoch). Use it for deduplication when
persisting results.

## Debug Fields

All three are read/write and excluded from `export`/`to_json` (but included in `to_h`):

```ruby
result.prompt   # Array<Message>, nil — nil unless you assign it
result.history  # Array<Message>, nil — nil unless you assign it
result.raw      # the raw ruby_llm response; Robot#run always sets this
```

`raw` is populated by `Robot#build_result` on every run, so it is the escape
hatch for anything RobotLab does not surface (cost, provider metadata, the
untouched message object). `prompt` and `history` are never populated by the
framework.

## Attribute Reference

| Attribute | Access | Type | Description |
|-----------|--------|------|-------------|
| `robot_name` | r | String | Name of the robot that produced this result |
| `last_text_content` | r | String, nil | Content of the last text message in `output` (alias: `reply`) |
| `output` | r | Array\<TextMessage\> | The final response text, as a one-element array (or empty) |
| `tool_calls` | r | Array\<ToolResultMessage\> | Tool call results — effectively always empty |
| `input_tokens` | r | Integer | Tokens sent to LLM (0 when the provider reports no usage) |
| `output_tokens` | r | Integer | Tokens generated (0 when not reported) |
| `id` | r | String | UUID, generated per result |
| `created_at` | r | Time | Creation timestamp |
| `stop_reason` | r | String, nil | Always `nil` for `Robot#run` results (the ruby_llm response has no `stop_reason`); settable only when you build a `RobotResult` yourself |
| `duration` | rw | Float, nil | Elapsed seconds — set by `delegate` and by `Robot#call` in a pipeline; `nil` for a direct `robot.run` |
| `delegated_by` | rw | String, nil | Delegating robot's name — set by `delegate` |
| `prompt` | rw | Array\<Message\>, nil | Debug field, `nil` unless assigned |
| `history` | rw | Array\<Message\>, nil | Debug field, `nil` unless assigned |
| `raw` | rw | Object, nil | The raw ruby_llm response; set by `Robot#build_result` |

Methods: `checksum`, `export`, `to_h`, `to_json`, `has_tool_calls?`, `stopped?`,
and the class method `RobotResult.from_hash`.

## Constructor

```ruby
RobotLab::RobotResult.new(
  robot_name:,            # required
  output:,                # required — Array<Message, Hash>
  tool_calls: [],
  created_at: nil,        # defaults to Time.now
  id: nil,                # defaults to SecureRandom.uuid
  prompt: nil,
  history: nil,
  raw: nil,
  stop_reason: nil,
  input_tokens: 0,
  output_tokens: 0
)
```

`output` entries must be `Message` instances or Hashes (`Message.from_hash`);
anything else raises `ArgumentError`.

## Related

- [Robot API](robot.md) — [`run`](robot.md#run), [`delegate`](robot.md#delegate), [`compress_history`](robot.md#compress_history)
- [Building Robots](../../guides/building-robots.md) — Robot construction patterns
- [Structured Delegation](../../guides/building-robots.md#structured-delegation) — `DelegationFuture` and async fan-out
