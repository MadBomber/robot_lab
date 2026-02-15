# Installation

This guide covers installing RobotLab in your Ruby project.

## Requirements

- **Ruby**: 3.2 or higher
- **Bundler**: 2.0 or higher (recommended)

## Install via Bundler

Add RobotLab to your `Gemfile`:

```ruby
gem "robot_lab"
```

Then install:

```bash
bundle install
```

## Install via RubyGems

Or install directly:

```bash
gem install robot_lab
```

## Dependencies

RobotLab automatically installs these core dependencies:

| Gem | Purpose |
|-----|---------|
| `ruby_llm` (~> 1.12) | LLM provider integrations (Anthropic, OpenAI, Gemini, etc.) |
| `prompt_manager` (~> 1.0) | Template-based prompt management with YAML front matter |
| `simple_flow` (~> 0.3) | Pipeline workflow execution for networks |
| `myway_config` (~> 0.1) | Layered configuration (defaults, env vars, config files) |
| `ruby_llm-mcp` | Model Context Protocol client for external tool servers |
| `ruby_llm-schema` | Schema validation for structured outputs |
| `ruby_llm-semantic_cache` | Semantic caching for LLM responses |
| `zeitwerk` (~> 2.6) | Autoloading and eager loading |
| `async` (~> 2.0) | Fiber-based concurrency |

### Optional Dependencies

For specific features, you may need additional gems:

=== "MCP WebSocket Transport"

    ```ruby
    gem "async-websocket"
    ```

=== "MCP HTTP Transport"

    ```ruby
    gem "async-http"
    ```

=== "Rails Integration"

    ```ruby
    # Rails is detected automatically
    gem "rails", ">= 7.0"
    ```

## Verify Installation

Create a test file to verify everything works:

```ruby
# test_robot_lab.rb
require "robot_lab"

puts "RobotLab version: #{RobotLab::VERSION}"
puts "Installation successful!"
```

Run it:

```bash
ruby test_robot_lab.rb
# => RobotLab version: 0.1.0
# => Installation successful!
```

## Rails Installation

For Rails applications, use the install generator:

```bash
rails generate robot_lab:install
```

This creates:

- `config/initializers/robot_lab.rb` - Configuration file
- `db/migrate/*_create_robot_lab_tables.rb` - Database migrations
- `app/models/robot_lab_thread.rb` - Thread model
- `app/models/robot_lab_result.rb` - Result model
- `app/robots/` - Directory for robot definitions
- `app/tools/` - Directory for tool definitions

Then run migrations:

```bash
rails db:migrate
```

## Environment Setup

RobotLab uses a layered configuration system (see [Configuration](configuration.md) for full details). The simplest way to get started is with environment variables:

=== "Anthropic (Recommended)"

    ```bash
    export ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY="sk-ant-..."
    ```

=== "OpenAI"

    ```bash
    export ROBOT_LAB_RUBY_LLM__OPENAI_API_KEY="sk-..."
    ```

=== "Google Gemini"

    ```bash
    export ROBOT_LAB_RUBY_LLM__GEMINI_API_KEY="..."
    ```

!!! tip "Using dotenv"
    For development, consider using the [dotenv](https://github.com/bkeepers/dotenv) gem to manage environment variables:

    ```ruby
    # Gemfile
    gem "dotenv", groups: [:development, :test]
    ```

    ```bash
    # .env
    ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...
    ```

!!! info "Direct provider env vars"
    RubyLLM also reads provider-specific environment variables directly (e.g., `ANTHROPIC_API_KEY`). If you already have those set, they will be picked up automatically. The `ROBOT_LAB_RUBY_LLM__*` prefix gives you explicit control through RobotLab's config layer.

## Troubleshooting

### Gem Installation Fails

If you encounter SSL or network errors:

```bash
# Update RubyGems
gem update --system

# Try installing with verbose output
gem install robot_lab --verbose
```

### Missing Dependencies

If you see "LoadError" for optional gems:

```bash
# Install the specific gem mentioned in the error
bundle add async-websocket
```

### API Key Issues

If you see authentication errors:

1. Verify your API key is set: `echo $ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY`
2. Check the key is valid in your provider's console
3. Ensure you're using the correct environment variable name

## Next Steps

Now that RobotLab is installed:

- [:octicons-arrow-right-24: Quick Start](quick-start.md) - Build your first robot
- [:octicons-arrow-right-24: Configuration](configuration.md) - Configure defaults
