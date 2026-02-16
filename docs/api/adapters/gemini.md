# Gemini Adapter

Adapter for Gemini models via Google AI API.

## Class: `RobotLab::Adapters::Gemini`

```ruby
# Automatically used for Gemini models
robot = RobotLab.build(name: "assistant", model: "gemini-1.5-pro")
result = robot.run("Hello!")
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
# Direct RubyLLM env var
export GOOGLE_AI_API_KEY="..."

# Or via RobotLab config
export ROBOT_LAB_RUBY_LLM__GEMINI_API_KEY="..."
```

### Options

Provider options are configured via environment variables or YAML config files:

```yaml
# In config/robot_lab.yml
ruby_llm:
  gemini_api_key: "..."
  gemini_api_base: "https://generativelanguage.googleapis.com"
  request_timeout: 120
```

```ruby
# Access configuration values
RobotLab.config.ruby_llm.gemini_api_key
RobotLab.config.ruby_llm.gemini_api_base
```

### Vertex AI

```bash
export ROBOT_LAB_RUBY_LLM__VERTEXAI_PROJECT_ID="your-project"
export ROBOT_LAB_RUBY_LLM__VERTEXAI_LOCATION="us-central1"
```

```yaml
# Or in config/robot_lab.yml
ruby_llm:
  vertexai_project_id: "your-project"
  vertexai_location: "us-central1"
```

## Features

### Tool Use

Tools are automatically converted to Gemini's format by the adapter. Define tools as RubyLLM tool classes and pass them when building the robot:

```ruby
robot = RobotLab.build(
  name: "catalog_bot",
  model: "gemini-1.5-pro",
  system_prompt: "You are a helpful product search assistant.",
  local_tools: [SearchProductsTool]
)

result = robot.run("Find me wireless headphones under $100")
```

### Long Context

Gemini supports very long contexts (up to 2M tokens for some models):

```ruby
robot = RobotLab.build(
  name: "document_reader",
  model: "gemini-1.5-pro",
  system_prompt: "You are a document analysis assistant."
)

result = robot.run("Summarize this document: #{long_text}")
```

### Adapter-Specific Formatting

The Gemini adapter is also used for VertexAI.

```ruby
adapter = RobotLab::Adapters::Registry.for(:gemini)

adapter.format_messages(messages)       # => Gemini-specific message format
adapter.format_tools(tools)             # => Gemini-specific tool format
adapter.format_tool_choice("auto")      # => provider-specific tool choice
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
- [Google AI Documentation](https://ai.google.dev/docs)
