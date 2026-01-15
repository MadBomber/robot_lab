# Configuration

RobotLab provides flexible configuration options at global, network, and robot levels.

## Global Configuration

Configure RobotLab globally using the `configure` block:

```ruby
RobotLab.configure do |config|
  # LLM Provider API Keys
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.gemini_api_key = ENV["GEMINI_API_KEY"]

  # Default settings
  config.default_provider = :anthropic
  config.default_model = "claude-sonnet-4"

  # Execution limits
  config.max_iterations = 10        # Max robots per network run
  config.max_tool_iterations = 10   # Max tool calls per robot run

  # Streaming
  config.streaming_enabled = true

  # Logging
  config.logger = Logger.new($stdout)

  # Template path for prompt files
  config.template_path = "prompts"
end
```

## Configuration Options

### API Keys

| Option | Description |
|--------|-------------|
| `anthropic_api_key` | Anthropic Claude API key |
| `openai_api_key` | OpenAI API key |
| `gemini_api_key` | Google Gemini API key |
| `bedrock_api_key` | AWS Bedrock API key |
| `openrouter_api_key` | OpenRouter API key |

### Defaults

| Option | Default | Description |
|--------|---------|-------------|
| `default_provider` | `:anthropic` | Default LLM provider |
| `default_model` | `"claude-sonnet-4"` | Default model |
| `max_iterations` | `10` | Max robots per network run |
| `max_tool_iterations` | `10` | Max tool calls per robot |
| `streaming_enabled` | `true` | Enable streaming by default |

### Templates

| Option | Default | Description |
|--------|---------|-------------|
| `template_path` | `"prompts"` (or `"app/prompts"` in Rails) | Directory for prompt templates |

### Global MCP & Tools

```ruby
RobotLab.configure do |config|
  # Global MCP servers available to all networks
  config.mcp = [
    { name: "github", transport: { type: "stdio", command: "github-mcp" } }
  ]

  # Global tool whitelist
  config.tools = %w[search_code create_issue]
end
```

## Network-Level Configuration

Override global settings at the network level:

```ruby
network = RobotLab.create_network do
  name "my_network"

  # Override default model for this network
  default_model "claude-sonnet-4"

  # Network-specific MCP servers
  mcp [
    { name: "filesystem", transport: { type: "stdio", command: "mcp-fs" } }
  ]

  # Network-specific tool whitelist
  tools %w[read_file write_file]

  # Or inherit from global
  mcp :inherit
  tools :inherit
end
```

## Robot-Level Configuration

Configure individual robots:

```ruby
robot = RobotLab.build do
  name "specialist"

  # Robot-specific model
  model "claude-sonnet-4"

  # Robot-specific MCP (overrides network)
  mcp :inherit  # Use network's MCP servers
  # or
  mcp :none     # No MCP servers for this robot
  # or
  mcp [...]     # Specific servers

  # Robot-specific tools
  tools :inherit  # Use network's tools
end
```

## Configuration Hierarchy

Configuration cascades from global to network to robot:

```
Global (RobotLab.configure)
  └── Network (create_network)
        └── Robot (build)
              └── Runtime (robot.run)
```

Each level can:

- `:inherit` - Use parent level's configuration
- `:none` or `nil` or `[]` - No items allowed
- `[items]` - Specific items only

## Rails Configuration

In Rails, configure in an initializer:

```ruby title="config/initializers/robot_lab.rb"
RobotLab.configure do |config|
  # Use Rails credentials
  config.anthropic_api_key = Rails.application.credentials.anthropic_api_key

  # Use Rails logger
  config.logger = Rails.logger

  # Template path is automatically set to app/prompts
end
```

Or use `config/application.rb`:

```ruby title="config/application.rb"
module MyApp
  class Application < Rails::Application
    config.robot_lab.default_model = "claude-sonnet-4"
    config.robot_lab.default_provider = :anthropic
  end
end
```

## Environment-Specific Configuration

```ruby title="config/initializers/robot_lab.rb"
RobotLab.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]

  case Rails.env
  when "development"
    config.logger = Logger.new($stdout, level: :debug)
    config.default_model = "claude-haiku-3"  # Faster/cheaper for dev
  when "test"
    config.streaming_enabled = false
  when "production"
    config.logger = Rails.logger
    config.default_model = "claude-sonnet-4"
  end
end
```

## Using Environment Variables

Recommended environment variables:

```bash
# Required - at least one provider
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
GEMINI_API_KEY=...

# Optional - override defaults
ROBOT_LAB_DEFAULT_MODEL=claude-sonnet-4
ROBOT_LAB_DEFAULT_PROVIDER=anthropic
ROBOT_LAB_MAX_ITERATIONS=20
```

Load them in configuration:

```ruby
RobotLab.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.default_model = ENV.fetch("ROBOT_LAB_DEFAULT_MODEL", "claude-sonnet-4")
  config.max_iterations = ENV.fetch("ROBOT_LAB_MAX_ITERATIONS", 10).to_i
end
```

## Accessing Configuration

```ruby
# Get current configuration
config = RobotLab.configuration

# Check settings
config.default_model      # => "claude-sonnet-4"
config.default_provider   # => :anthropic
config.streaming_enabled  # => true
```

## Next Steps

- [Building Robots](../guides/building-robots.md) - Create custom robots
- [Creating Networks](../guides/creating-networks.md) - Network configuration
- [MCP Integration](../guides/mcp-integration.md) - Configure MCP servers
