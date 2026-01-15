# Anthropic Adapter

Adapter for Claude models via Anthropic API.

## Class: `RobotLab::Adapters::Anthropic`

```ruby
# Automatically used for Claude models
robot = RobotLab.build do
  model "claude-sonnet-4"
end
```

## Supported Models

| Model | Description |
|-------|-------------|
| `claude-sonnet-4` | Latest Sonnet (recommended) |
| `claude-opus-4` | Most capable model |
| `claude-3-5-sonnet-latest` | Claude 3.5 Sonnet |
| `claude-3-5-haiku-latest` | Fast, efficient model |

## Configuration

### API Key

```bash
export ANTHROPIC_API_KEY="sk-ant-api03-..."
```

### Options

```ruby
RobotLab.configure do |config|
  config.adapter_options = {
    anthropic: {
      base_url: "https://api.anthropic.com",
      api_version: "2024-01-01",
      timeout: 120,
      max_tokens: 4096
    }
  }
end
```

## Features

### Streaming

```ruby
result = robot.run(state: state) do |event|
  case event
  when :text_delta
    print event.text
  when :tool_call
    puts "Calling: #{event.name}"
  end
end
```

### Tool Use

Tools are automatically converted to Anthropic's format:

```ruby
robot = RobotLab.build do
  model "claude-sonnet-4"

  tool :search do
    description "Search the database"
    parameter :query, type: :string, required: true
    handler { |query:, **_| Database.search(query) }
  end
end
```

### Extended Thinking

For complex reasoning tasks:

```ruby
robot = RobotLab.build do
  model "claude-sonnet-4"
  # Extended thinking is automatically enabled for supported models
end
```

## Response Format

```ruby
{
  content: [TextMessage, ...],
  tool_calls: [ToolCallMessage, ...],
  usage: {
    input_tokens: 150,
    output_tokens: 250,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0
  },
  stop_reason: "end_turn"
}
```

## Error Handling

```ruby
begin
  result = robot.run(state: state)
rescue RobotLab::Adapters::RateLimitError => e
  sleep(e.retry_after)
  retry
rescue RobotLab::Adapters::APIError => e
  logger.error("Anthropic API error: #{e.message}")
end
```

## See Also

- [Adapters Overview](index.md)
- [Streaming Guide](../../guides/streaming.md)
- [Anthropic API Documentation](https://docs.anthropic.com/)
