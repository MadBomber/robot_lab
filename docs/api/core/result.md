# RobotResult

`RobotResult` is returned by every `robot.run()` call. It carries the LLM output, tool call results, token usage, timing, and delegation metadata for that execution.

## Accessing the Response

```ruby
result = robot.run("What is the capital of France?")

result.reply              # => "The capital of France is Paris."
result.last_text_content  # => alias for reply
result.output             # => Array of Message objects (full turn)
result.tool_calls         # => Array of ToolResultMessage objects
```

`reply` / `last_text_content` returns the content of the last text message in `output`. This is the string you want for the vast majority of use cases.

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
result.stop_reason  # => "end_turn", "tool_use", or nil
```

## Inspecting the Full Output

```ruby
result.output.each do |message|
  puts message.role     # :assistant, :tool, etc.
  puts message.content  # String or Array
end

result.has_tool_calls?  # => true if the LLM called any tools
result.stopped?         # => true if execution ended naturally (not mid-tool-call)
```

## Persistence

Export for serialization (excludes debug fields):

```ruby
hash = result.export
# {
#   robot_name: "analyst",
#   output: [...],
#   tool_calls: [...],
#   created_at: "2026-04-18T12:00:00Z",
#   id: "550e8400-...",
#   checksum: "a1b2c3...",
#   stop_reason: "end_turn",
#   duration: 2.34,
#   input_tokens: 512,
#   output_tokens: 128
# }

json = result.to_json

# Reconstruct from hash
restored = RobotLab::RobotResult.from_hash(hash)
```

`checksum` is a SHA-256 digest of `output + tool_calls + created_at`. Use it for deduplication when persisting results.

## Debug Fields

These are `nil` by default and only populated when explicitly set for debugging:

```ruby
result.prompt   # Array<Message> — prompt sent to the LLM
result.history  # Array<Message> — history used
result.raw      # raw LLM response object from ruby_llm
```

## Attribute Reference

| Attribute | Type | Description |
|-----------|------|-------------|
| `robot_name` | String | Name of the robot that produced this result |
| `reply` | String, nil | Last text content (alias: `last_text_content`) |
| `output` | Array\<Message\> | All output messages from this run |
| `tool_calls` | Array\<ToolResultMessage\> | Tool call results |
| `input_tokens` | Integer | Tokens sent to LLM |
| `output_tokens` | Integer | Tokens generated |
| `duration` | Float, nil | Elapsed seconds (set by delegate/pipeline) |
| `delegated_by` | String, nil | Delegating robot's name |
| `id` | String | UUID |
| `created_at` | Time | Creation timestamp |
| `stop_reason` | String, nil | LLM stop reason |
| `checksum` | String | SHA-256 of output content |

## Related

- [Robot API](robot.md) — `run`, `delegate`, `compress_history`
- [Building Robots](../../guides/building-robots.md) — Robot construction patterns
- [Structured Delegation](../../guides/building-robots.md#structured-delegation) — `DelegationFuture` and async fan-out
