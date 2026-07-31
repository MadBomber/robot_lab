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
| `simple_flow` (~> 0.4) | Pipeline workflow execution for networks |
| `myway_config` (~> 0.1) | Layered configuration (defaults, env vars, config files) |
| `ruby_llm-mcp` (~> 1.0) | Model Context Protocol client for external tool servers |
| `ruby_llm-schema` (~> 0.3) | Schema validation for structured outputs |
| `ruby_llm-semantic_cache` (~> 0.1) | Semantic caching for LLM responses |
| `zeitwerk` (~> 2.6) | Autoloading and eager loading |
| `async` (~> 2.0) | Fiber-based concurrency |
| `async-http` (~> 0.60) | MCP SSE and streamable-HTTP transports |
| `async-websocket` (~> 0.30) | MCP WebSocket transport |
| `typed_bus` (~> 0.0.1) | Typed message bus for robot-to-robot messaging |
| `ractor_queue` (~> 0.2) | Queue used by the Network bus poller |

> [!NOTE]
> `async-http` and `async-websocket` are hard runtime dependencies, not optional
> extras — they install with the gem whether or not you use MCP.

### Optional Dependencies

Several features are gated behind gems the core gem does **not** install. Add
whichever you need to your own `Gemfile`:

| Gem | Enables | Without it |
|-----|---------|------------|
| `classifier` (~> 2.3) | `robot.compress_history`, `RobotLab::Convergence` | `RobotLab::DependencyError` |
| `robot_lab-document_store` | `memory.store_document` / `search_documents` / `document_keys` / `delete_document`, and `AgentSkill` catalogs | `RobotLab::DependencyError` (skill catalogs raise `LoadError`) |
| `redis` | Redis-backed `Memory` | `Memory#redis?` is `false` and the store silently stays in-process |
| `robot_lab-ractor` | Ractor-parallel tool execution and `Network` ractor scheduling | tools run inline; a network run with `parallel_mode: :ractor` raises `RobotLab::DependencyError` |

```ruby
# Gemfile
gem "classifier", "~> 2.3"
gem "robot_lab-document_store"
gem "redis"
gem "robot_lab-ractor"
```

> [!NOTE]
> Several capabilities advertised on the [home page](../index.md) — embedding-based
> document retrieval, runtime skill matching, and CPU parallelism — depend on the
> gems above. They are genuinely optional, but the feature is unavailable until the
> gem is installed.

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
# => RobotLab version: 0.2.6
# => Installation successful!
```

## Rails Installation

> [!IMPORTANT]
> The core `robot_lab` gem ships **no Rails Engine, no Railtie, and no generators**.
> Rails integration lives in the separate
> [robot_lab-rails](https://github.com/MadBomber/robot_lab-rails) gem.

Core RobotLab only performs two bare `defined?(::Rails)` checks: it uses
`Rails.logger` as the default logger, and it resolves the template path to
`app/prompts` when `Rails.root` is present. Nothing else is Rails-aware.

For generators, an `ActiveJob` base class, and Turbo Stream broadcasting, add the
extension gem:

```ruby
# Gemfile
gem "robot_lab"
gem "robot_lab-rails"
```

Then follow that gem's own installation instructions for its generators and
migrations.

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

If you see a `LoadError` (or a `RobotLab::DependencyError`) naming a gem RobotLab
does not depend on, add it yourself:

```bash
# e.g. compress_history / Convergence need the classifier gem
bundle add classifier
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
