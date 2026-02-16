# OpenAI Adapter

Adapter for GPT models via OpenAI API.

## Class: `RobotLab::Adapters::OpenAI`

```ruby
# Automatically used for GPT models
robot = RobotLab.build(name: "assistant", model: "gpt-4o")
result = robot.run("Hello!")
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
# Direct RubyLLM env var
export OPENAI_API_KEY="sk-..."

# Or via RobotLab config
export ROBOT_LAB_RUBY_LLM__OPENAI_API_KEY="sk-..."
```

### Options

Provider options are configured via environment variables or YAML config files:

```yaml
# In config/robot_lab.yml
ruby_llm:
  openai_api_key: "sk-..."
  openai_api_base: "https://api.openai.com/v1"
  openai_organization_id: "org-..."
  request_timeout: 120
```

```ruby
# Access configuration values
RobotLab.config.ruby_llm.openai_api_key
RobotLab.config.ruby_llm.openai_api_base
RobotLab.config.ruby_llm.openai_organization_id
```

### Azure OpenAI

```bash
export ROBOT_LAB_RUBY_LLM__OPENAI_API_BASE="https://your-resource.openai.azure.com"
export ROBOT_LAB_RUBY_LLM__OPENAI_API_KEY="your-azure-key"
```

```yaml
# Or in config/robot_lab.yml
ruby_llm:
  openai_api_base: "https://your-resource.openai.azure.com"
  openai_api_key: "your-azure-key"
```

## Features

### Tool Use

Tools are automatically converted to OpenAI's function calling format by the adapter. Define tools as RubyLLM tool classes and pass them when building the robot:

```ruby
robot = RobotLab.build(
  name: "weather_bot",
  model: "gpt-4o",
  system_prompt: "You are a helpful weather assistant.",
  local_tools: [GetWeatherTool]
)

result = robot.run("What's the weather in San Francisco?")
```

### Adapter-Specific Formatting

The OpenAI adapter uses the base class defaults for tool choice formatting:

```ruby
adapter = RobotLab::Adapters::Registry.for(:openai)

# Format tool choice
adapter.format_tool_choice("auto")       # => "auto"
adapter.format_tool_choice("any")        # => "required"
adapter.format_tool_choice("get_weather") # => { type: "function", function: { name: "get_weather" } }
```

The OpenAI adapter is also used for compatible providers: Azure OpenAI, Grok, Ollama, and OpenRouter.

## Response Format

The adapter's `parse_response` method returns internal message objects:

```ruby
# TextMessage for text content
# ToolCallMessage for tool calls
# Each with normalized attributes regardless of provider
```

## Error Handling

RobotLab uses its own error hierarchy. Provider-specific errors from RubyLLM are raised as-is:

```ruby
begin
  result = robot.run("Hello!")
rescue RobotLab::InferenceError => e
  logger.error("Inference failed: #{e.message}")
rescue RobotLab::ConfigurationError => e
  logger.error("Configuration error: #{e.message}")
end
```

## See Also

- [Adapters Overview](index.md)
- [Streaming Guide](../../guides/streaming.md)
- [OpenAI API Documentation](https://platform.openai.com/docs/)
