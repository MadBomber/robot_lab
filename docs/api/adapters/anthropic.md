# Anthropic Adapter

Adapter for Claude models via Anthropic API.

## Class: `RobotLab::Adapters::Anthropic`

```ruby
# Automatically used for Claude models
robot = RobotLab.build(name: "assistant", model: "claude-sonnet-4")
result = robot.run("Hello!")
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
# Direct RubyLLM env var
export ANTHROPIC_API_KEY="sk-ant-api03-..."

# Or via RobotLab config
export ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY="sk-ant-api03-..."
```

### Options

Provider options are configured via environment variables or YAML config files:

```yaml
# In config/robot_lab.yml
ruby_llm:
  anthropic_api_key: "sk-ant-api03-..."
  request_timeout: 120
```

```ruby
# Access configuration values
RobotLab.config.ruby_llm.anthropic_api_key
RobotLab.config.ruby_llm.request_timeout
```

## Features

### Tool Use

Tools are automatically converted to Anthropic's format by the adapter. Define tools as RubyLLM tool classes and pass them when building the robot:

```ruby
robot = RobotLab.build(
  name: "searcher",
  model: "claude-sonnet-4",
  system_prompt: "You are a helpful search assistant.",
  local_tools: [SearchTool]
)

result = robot.run("Search for Ruby LLM libraries")
```

### Adapter-Specific Formatting

The Anthropic adapter handles:

- System message as a top-level parameter (not in the messages array)
- `tool_use` / `tool_result` content block format
- Anthropic-specific tool choice format (`{ type: "auto" }`, `{ type: "any" }`, `{ type: "tool", name: "..." }`)

```ruby
adapter = RobotLab::Adapters::Registry.for(:anthropic)

# Format tools for Anthropic's API
formatted = adapter.format_tools(tools)
# => [{ name: "search", description: "...", input_schema: { ... } }]

# Format tool choice
adapter.format_tool_choice("auto")   # => { type: "auto" }
adapter.format_tool_choice("any")    # => { type: "any" }
adapter.format_tool_choice("search") # => { type: "tool", name: "search" }
```

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
- [Anthropic API Documentation](https://docs.anthropic.com/)
