# Adapters

LLM provider adapters for unified API access.

## Overview

Adapters provide a consistent interface to different LLM providers, handling the translation between RobotLab's message format and provider-specific APIs.

```ruby
# Configure globally
RobotLab.configure do |config|
  config.default_model = "claude-sonnet-4"
  # Adapter is selected automatically based on model
end

# Or configure per-robot
robot = RobotLab.build do
  model "gpt-4o"  # Uses OpenAI adapter
end
```

## Adapter Selection

Adapters are automatically selected based on model name:

| Model Pattern | Adapter |
|---------------|---------|
| `claude-*`, `anthropic/*` | Anthropic |
| `gpt-*`, `o1-*`, `openai/*` | OpenAI |
| `gemini-*`, `google/*` | Gemini |

## Common Interface

All adapters implement:

```ruby
adapter.chat(
  messages: messages,
  model: model,
  tools: tools,
  system: system_prompt,
  streaming: callback
)
# => Response with content and usage
```

## Available Adapters

| Adapter | Description |
|---------|-------------|
| [Anthropic](anthropic.md) | Claude models via Anthropic API |
| [OpenAI](openai.md) | GPT models via OpenAI API |
| [Gemini](gemini.md) | Gemini models via Google AI |

## Configuration

### API Keys

Set via environment variables:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export GOOGLE_AI_API_KEY="..."
```

### Custom Endpoints

```ruby
RobotLab.configure do |config|
  config.adapter_options = {
    anthropic: { base_url: "https://custom.anthropic.endpoint" },
    openai: { base_url: "https://custom.openai.endpoint" }
  }
end
```

## Creating Custom Adapters

Implement the adapter interface:

```ruby
class MyAdapter
  def chat(messages:, model:, tools: [], system: nil, streaming: nil)
    # Translate messages to provider format
    # Make API call
    # Translate response back

    Response.new(
      content: content,
      tool_calls: tool_calls,
      usage: { input_tokens: x, output_tokens: y }
    )
  end
end

# Register the adapter
RobotLab.register_adapter(:my_provider, MyAdapter)
```

## See Also

- [Configuration Guide](../../getting-started/configuration.md)
- [Streaming Guide](../../guides/streaming.md)
