# OpenAI Adapter

Adapter for GPT models via OpenAI API.

## Class: `RobotLab::Adapters::OpenAI`

```ruby
# Automatically used for GPT models
robot = RobotLab.build do
  model "gpt-4o"
end
```

## Supported Models

| Model | Description |
|-------|-------------|
| `gpt-4o` | Latest GPT-4 Omni |
| `gpt-4o-mini` | Fast, efficient GPT-4 |
| `gpt-4-turbo` | GPT-4 Turbo |
| `o1-preview` | Reasoning model |
| `o1-mini` | Fast reasoning model |

## Configuration

### API Key

```bash
export OPENAI_API_KEY="sk-..."
```

### Options

```ruby
RobotLab.configure do |config|
  config.adapter_options = {
    openai: {
      base_url: "https://api.openai.com/v1",
      organization: "org-...",
      timeout: 120,
      max_tokens: 4096
    }
  }
end
```

### Azure OpenAI

```ruby
RobotLab.configure do |config|
  config.adapter_options = {
    openai: {
      base_url: "https://your-resource.openai.azure.com",
      api_key: ENV["AZURE_OPENAI_KEY"],
      api_version: "2024-02-15-preview"
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

Tools are automatically converted to OpenAI's function calling format:

```ruby
robot = RobotLab.build do
  model "gpt-4o"

  tool :get_weather do
    description "Get current weather"
    parameter :location, type: :string, required: true
    handler { |location:, **_| WeatherAPI.fetch(location) }
  end
end
```

### JSON Mode

```ruby
robot = RobotLab.build do
  model "gpt-4o"
  template "Always respond with valid JSON."
  # Response format is automatically configured
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
    total_tokens: 400
  },
  stop_reason: "stop"
}
```

## Error Handling

```ruby
begin
  result = robot.run(state: state)
rescue RobotLab::Adapters::RateLimitError => e
  sleep(e.retry_after || 60)
  retry
rescue RobotLab::Adapters::APIError => e
  logger.error("OpenAI API error: #{e.message}")
end
```

## See Also

- [Adapters Overview](index.md)
- [Streaming Guide](../../guides/streaming.md)
- [OpenAI API Documentation](https://platform.openai.com/docs/)
