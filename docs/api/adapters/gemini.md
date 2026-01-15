# Gemini Adapter

Adapter for Gemini models via Google AI API.

## Class: `RobotLab::Adapters::Gemini`

```ruby
# Automatically used for Gemini models
robot = RobotLab.build do
  model "gemini-1.5-pro"
end
```

## Supported Models

| Model | Description |
|-------|-------------|
| `gemini-1.5-pro` | Most capable Gemini |
| `gemini-1.5-flash` | Fast, efficient model |
| `gemini-1.5-flash-8b` | Lightweight model |
| `gemini-2.0-flash-exp` | Experimental next-gen |

## Configuration

### API Key

```bash
export GOOGLE_AI_API_KEY="..."
```

### Options

```ruby
RobotLab.configure do |config|
  config.adapter_options = {
    gemini: {
      base_url: "https://generativelanguage.googleapis.com",
      timeout: 120,
      max_tokens: 8192
    }
  }
end
```

### Vertex AI

```ruby
RobotLab.configure do |config|
  config.adapter_options = {
    gemini: {
      base_url: "https://us-central1-aiplatform.googleapis.com",
      project_id: "your-project",
      location: "us-central1"
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

Tools are automatically converted to Gemini's format:

```ruby
robot = RobotLab.build do
  model "gemini-1.5-pro"

  tool :search_products do
    description "Search product catalog"
    parameter :query, type: :string, required: true
    parameter :category, type: :string
    handler { |query:, category: nil, **_| Catalog.search(query, category) }
  end
end
```

### Long Context

Gemini supports very long contexts:

```ruby
robot = RobotLab.build do
  model "gemini-1.5-pro"
  # Supports up to 2M tokens context
end
```

## Response Format

```ruby
{
  content: [TextMessage, ...],
  tool_calls: [ToolCallMessage, ...],
  usage: {
    input_tokens: 150,
    output_tokens: 250
  },
  stop_reason: "STOP"
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
  logger.error("Gemini API error: #{e.message}")
end
```

## See Also

- [Adapters Overview](index.md)
- [Streaming Guide](../../guides/streaming.md)
- [Google AI Documentation](https://ai.google.dev/docs)
