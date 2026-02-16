# Adapters

LLM provider adapters for unified API access.

## Overview

Adapters provide a consistent interface to different LLM providers, handling the translation between RobotLab's message format and provider-specific APIs. RobotLab delegates actual chat/completion calls to [RubyLLM](https://rubyllm.com); adapters handle provider-specific formatting of messages, tools, and responses.

```ruby
# Adapter is selected automatically based on the provider/model.
# Configuration uses RobotLab.config (MywayConfig), not a block DSL.
robot = RobotLab.build(name: "assistant", model: "gpt-4o")  # Uses OpenAI adapter
result = robot.run("Hello!")
```

## Adapter Selection

Adapters are automatically selected based on provider:

| Provider | Adapter |
|----------|---------|
| `:anthropic` | `RobotLab::Adapters::Anthropic` |
| `:openai` | `RobotLab::Adapters::OpenAI` |
| `:gemini` | `RobotLab::Adapters::Gemini` |
| `:azure_openai`, `:grok`, `:ollama`, `:openrouter` | `RobotLab::Adapters::OpenAI` |
| `:bedrock` | `RobotLab::Adapters::Anthropic` |
| `:vertexai` | `RobotLab::Adapters::Gemini` |

## Common Interface

All adapters inherit from `RobotLab::Adapters::Base` and implement:

```ruby
adapter = RobotLab::Adapters::Registry.for(:anthropic)

adapter.format_messages(messages)       # => Array<Hash> (provider-specific format)
adapter.parse_response(raw_response)    # => Array<Message> (internal format)
adapter.format_tools(tools)             # => Array<Hash> (provider-specific tool format)
adapter.format_tool_choice(choice)      # => provider-specific tool choice value
```

Chat/completion calls are handled by RubyLLM, not by the adapters directly.

## Available Adapters

| Adapter | Description |
|---------|-------------|
| [Anthropic](anthropic.md) | Claude models via Anthropic API |
| [OpenAI](openai.md) | GPT models via OpenAI API |
| [Gemini](gemini.md) | Gemini models via Google AI |

## Configuration

### API Keys

Set via environment variables (directly for RubyLLM, or via `ROBOT_LAB_` prefix):

```bash
# Direct RubyLLM env vars
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export GOOGLE_AI_API_KEY="..."

# Or via RobotLab config env vars
export ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY="sk-ant-..."
export ROBOT_LAB_RUBY_LLM__OPENAI_API_KEY="sk-..."
export ROBOT_LAB_RUBY_LLM__GEMINI_API_KEY="..."
```

### Custom Endpoints

Set via environment variables or YAML config files:

```bash
# Via environment variables
export ROBOT_LAB_RUBY_LLM__OPENAI_API_BASE="https://custom.openai.endpoint"
export ROBOT_LAB_RUBY_LLM__GEMINI_API_BASE="https://custom.gemini.endpoint"
```

```yaml
# Or in config/robot_lab.yml
ruby_llm:
  openai_api_base: "https://custom.openai.endpoint"
  gemini_api_base: "https://custom.gemini.endpoint"
```

## Creating Custom Adapters

Implement the adapter interface by subclassing `RobotLab::Adapters::Base`:

```ruby
class MyAdapter < RobotLab::Adapters::Base
  def initialize
    super(:my_provider)
  end

  def format_messages(messages)
    # Translate internal messages to provider format
    conversation_messages(messages).map { |msg| { role: msg.role, content: msg.content } }
  end

  def parse_response(response)
    # Translate provider response to internal message format
    [TextMessage.new(role: "assistant", content: response.content)]
  end

  def format_tools(tools)
    # Format tools for provider's function calling API
    tools.map(&:to_json_schema)
  end

  def format_tool_choice(choice)
    # Format tool choice for provider
    choice.to_s
  end
end

# Register the adapter
RobotLab::Adapters::Registry.register(:my_provider, MyAdapter)
```

## See Also

- [Configuration Guide](../../getting-started/configuration.md)
- [Streaming Guide](../../guides/streaming.md)
