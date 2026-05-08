# Configuration

RobotLab uses a layered configuration system powered by [MywayConfig](https://github.com/MadBomber/myway_config). Configuration is loaded automatically from multiple sources with no block-style `configure` method required.

## How Configuration Works

Configuration values are loaded in priority order (lowest to highest):

1. **Bundled defaults** -- `lib/robot_lab/config/defaults.yml` (shipped with the gem)
2. **Environment-specific overrides** -- `development`, `test`, or `production` sections in defaults.yml
3. **User config file** -- `~/.config/robot_lab/config.yml`
4. **Project config file** -- `./config/robot_lab.yml`
5. **Environment variables** -- `ROBOT_LAB_*` prefix
6. **Runtime attributes** -- e.g., `RobotLab.config.logger = ...`

Higher-priority sources override lower-priority ones. You only need to set the values you want to change.

## Accessing Configuration

Use `RobotLab.config` to access the configuration object:

```ruby
# Access nested values with dot notation
RobotLab.config.ruby_llm.model            #=> "claude-sonnet-4"
RobotLab.config.ruby_llm.anthropic_api_key #=> "sk-ant-..."
RobotLab.config.ruby_llm.request_timeout  #=> 120
RobotLab.config.max_iterations             #=> 10
RobotLab.config.streaming_enabled          #=> true

# Check the environment
RobotLab.config.development?  #=> true/false
```

!!! warning "No configure block"
    RobotLab does **not** use a `RobotLab.configure do |config| ... end` pattern. All configuration comes from config files, environment variables, or direct assignment on `RobotLab.config`.

## Environment Variables

Environment variables use the `ROBOT_LAB_` prefix. Use double underscores (`__`) for nested values:

```bash
# Top-level settings
export ROBOT_LAB_MAX_ITERATIONS=20
export ROBOT_LAB_STREAMING_ENABLED=false

# Nested ruby_llm settings (note the double underscore)
export ROBOT_LAB_RUBY_LLM__MODEL=claude-sonnet-4
export ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...
export ROBOT_LAB_RUBY_LLM__OPENAI_API_KEY=sk-...
export ROBOT_LAB_RUBY_LLM__GEMINI_API_KEY=...
export ROBOT_LAB_RUBY_LLM__REQUEST_TIMEOUT=180
export ROBOT_LAB_RUBY_LLM__MAX_RETRIES=5
```

The double underscore convention maps to nested YAML structure:

```
ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY  -->  ruby_llm.anthropic_api_key
ROBOT_LAB_RUBY_LLM__MODEL              -->  ruby_llm.model
ROBOT_LAB_MAX_ITERATIONS               -->  max_iterations
```

## Config Files

### Project Config

Create `./config/robot_lab.yml` in your project root:

```yaml title="config/robot_lab.yml"
defaults:
  ruby_llm:
    anthropic_api_key: <%= ENV['ANTHROPIC_API_KEY'] %>
    model: claude-sonnet-4
    request_timeout: 120

  max_iterations: 15
  template_path: prompts

development:
  ruby_llm:
    log_level: :debug

test:
  max_iterations: 3
  streaming_enabled: false
  ruby_llm:
    model: claude-haiku-3-5
    request_timeout: 30
    max_retries: 1

production:
  max_iterations: 20
  ruby_llm:
    request_timeout: 180
    max_retries: 5
    log_level: :warn
```

!!! tip "ERB support"
    Config files support ERB templating, so you can reference environment variables with `<%= ENV['...'] %>`. This is useful for keeping secrets out of config files while still using YAML structure.

### User Config

Create `~/.config/robot_lab/config.yml` for personal defaults that apply across all your projects:

```yaml title="~/.config/robot_lab/config.yml"
defaults:
  ruby_llm:
    anthropic_api_key: <%= ENV['ANTHROPIC_API_KEY'] %>
    model: claude-sonnet-4
```

## Configuration Reference

### Core Settings

| Key | Default | Description |
|-----|---------|-------------|
| `max_iterations` | `10` | Maximum robots per network run |
| `max_tool_iterations` | `10` | Maximum tool calls per robot run |
| `streaming_enabled` | `true` | Enable streaming by default |
| `template_path` | `null` (auto-detected) | Directory for prompt templates |
| `mcp` | `:none` | Global MCP server configuration |
| `tools` | `:none` | Global tool whitelist |

### RubyLLM Settings (`ruby_llm:` section)

All settings under the `ruby_llm:` key are applied to `RubyLLM.configure` automatically on startup.

#### Provider API Keys

| Key | Description |
|-----|-------------|
| `ruby_llm.anthropic_api_key` | Anthropic Claude API key |
| `ruby_llm.openai_api_key` | OpenAI API key |
| `ruby_llm.gemini_api_key` | Google Gemini API key |
| `ruby_llm.deepseek_api_key` | DeepSeek API key |
| `ruby_llm.mistral_api_key` | Mistral API key |
| `ruby_llm.openrouter_api_key` | OpenRouter API key |
| `ruby_llm.bedrock_api_key` | AWS Bedrock access key |
| `ruby_llm.bedrock_secret_key` | AWS Bedrock secret key |
| `ruby_llm.bedrock_region` | AWS Bedrock region |
| `ruby_llm.xai_api_key` | xAI (Grok) API key |

#### Model Defaults

| Key | Default | Description |
|-----|---------|-------------|
| `ruby_llm.provider` | `:anthropic` | Default LLM provider |
| `ruby_llm.model` | `claude-sonnet-4` | Default model for robots |
| `ruby_llm.default_model` | `null` | RubyLLM default model override |
| `ruby_llm.default_embedding_model` | `null` | Default embedding model |
| `ruby_llm.default_image_model` | `null` | Default image model |

#### Connection Settings

| Key | Default | Description |
|-----|---------|-------------|
| `ruby_llm.request_timeout` | `120` | Request timeout in seconds |
| `ruby_llm.max_retries` | `3` | Maximum retry attempts |
| `ruby_llm.retry_interval` | `1` | Seconds between retries |
| `ruby_llm.retry_backoff_factor` | `2` | Exponential backoff factor |
| `ruby_llm.http_proxy` | `null` | HTTP proxy URL |

#### Provider Endpoints (self-hosted models)

| Key | Description |
|-----|-------------|
| `ruby_llm.openai_api_base` | Custom OpenAI-compatible endpoint |
| `ruby_llm.gemini_api_base` | Custom Gemini endpoint |
| `ruby_llm.ollama_api_base` | Ollama endpoint (e.g., `http://localhost:11434`) |
| `ruby_llm.gpustack_api_base` | GPUStack endpoint |

#### Logging

| Key | Default | Description |
|-----|---------|-------------|
| `ruby_llm.log_file` | `null` | Path to log file |
| `ruby_llm.log_level` | `:info` | Log level (`:debug`, `:info`, `:warn`, `:error`) |
| `ruby_llm.log_stream_debug` | `false` | Log streaming debug output |

### Chat Configuration (`chat:` section)

Default chat parameters applied to all robots unless overridden:

| Key | Default | Description |
|-----|---------|-------------|
| `chat.with_temperature` | `0.7` | Controls randomness (0.0-2.0) |
| `chat.with_params.top_p` | `null` | Nucleus sampling threshold |
| `chat.with_params.top_k` | `null` | Top-k sampling |
| `chat.with_params.max_tokens` | `null` | Maximum tokens in response |
| `chat.with_params.presence_penalty` | `null` | Presence penalty (-2.0 to 2.0) |
| `chat.with_params.frequency_penalty` | `null` | Frequency penalty (-2.0 to 2.0) |
| `chat.with_params.stop` | `null` | Stop sequences |

## Runtime-Only Attributes

Some attributes can only be set at runtime, not through config files:

```ruby
# Logger (defaults to Rails.logger in Rails, or Logger.new($stdout) otherwise)
RobotLab.config.logger = Logger.new(nil)        # silence logging
RobotLab.config.logger = Logger.new("robot.log") # log to file
```

## Reloading Configuration

To reload configuration from all sources:

```ruby
RobotLab.reload_config!
```

This clears the cached config and reloads from all sources on next access.

## Environment-Specific Configuration

The `defaults.yml` shipped with RobotLab includes environment-specific overrides:

=== "Development"

    ```yaml
    development:
      ruby_llm:
        log_level: :debug
    ```

=== "Test"

    ```yaml
    test:
      max_iterations: 3
      streaming_enabled: false
      ruby_llm:
        model: claude-haiku-3-5
        request_timeout: 30
        max_retries: 1
        log_level: :warn
    ```

=== "Production"

    ```yaml
    production:
      streaming_enabled: false
      max_iterations: 20
      ruby_llm:
        request_timeout: 180
        max_retries: 5
        log_level: :warn
    ```

The current environment is determined automatically (via `RAILS_ENV`, `RACK_ENV`, or defaults to `development`).

## Rails Integration

In Rails, RobotLab is configured automatically via its Railtie. The logger defaults to `Rails.logger`, and templates default to `app/prompts/`.

Create a project config file for Rails-specific settings:

```yaml title="config/robot_lab.yml"
defaults:
  ruby_llm:
    anthropic_api_key: <%= Rails.application.credentials.anthropic_api_key %>
    model: claude-sonnet-4

  template_path: null  # auto-detects app/prompts in Rails

production:
  ruby_llm:
    request_timeout: 180
    max_retries: 5
```

You can also use Rails credentials:

```bash
rails credentials:edit
```

```yaml
# config/credentials.yml.enc
anthropic_api_key: sk-ant-...
openai_api_key: sk-...
```

Then reference them in your config file with ERB:

```yaml title="config/robot_lab.yml"
defaults:
  ruby_llm:
    anthropic_api_key: <%= Rails.application.credentials.anthropic_api_key %>
```

## RunConfig: Shared Operational Defaults

`RunConfig` is a configuration object that lets you express operational defaults for LLM settings, tools, callbacks, and infrastructure. Unlike `RobotLab.config` (which is global and static), RunConfig flows through the hierarchy and can be customized at each level:

```
RobotLab.config (global) -> Network RunConfig -> Robot RunConfig -> Template front matter -> Task RunConfig -> Runtime
```

### Creating a RunConfig

```ruby
# Keyword construction
config = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.7)

# Block DSL
config = RobotLab::RunConfig.new do |c|
  c.model "claude-sonnet-4"
  c.temperature 0.7
  c.max_tokens 2000
end

# Chaining
config = RobotLab::RunConfig.new
  .model("claude-sonnet-4")
  .temperature(0.7)
```

### Applying RunConfig

Pass `config:` to robots and networks. Explicit constructor kwargs always override the RunConfig:

```ruby
# Shared config for a team of robots
shared = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.5)

# Robot uses shared config
robot = RobotLab.build(
  name: "writer",
  system_prompt: "You are a creative writer.",
  config: shared,
  temperature: 0.9  # overrides shared config's 0.5
)

# Network applies config to all member robots
network = RobotLab.create_network(name: "pipeline", config: shared) do
  task :analyzer, analyzer_robot, depends_on: :none
  task :writer, writer_robot, depends_on: [:analyzer]
end
```

### Merging Configs

RunConfig supports merge semantics where the more-specific config's values win:

```ruby
network_config = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.5)
robot_config   = RobotLab::RunConfig.new(temperature: 0.9)
effective      = network_config.merge(robot_config)
effective.model        #=> "claude-sonnet-4" (inherited)
effective.temperature  #=> 0.9 (overridden)
```

### Available Fields

| Category | Fields |
|----------|--------|
| **LLM** | `model`, `temperature`, `top_p`, `top_k`, `max_tokens`, `presence_penalty`, `frequency_penalty`, `stop` |
| **Tools** | `mcp`, `tools` |
| **Callbacks** | `on_tool_call`, `on_tool_result` |
| **Infrastructure** | `bus`, `enable_cache`, `max_tool_rounds`, `token_budget`, `ractor_pool_size`, `max_concurrent_robots`, `doom_loop_threshold`, `auto_compact`, `compact_threshold` |

### RunConfig vs RobotLab.config

| | `RobotLab.config` | `RunConfig` |
|---|---|---|
| **Scope** | Global (all robots) | Per-network, per-robot, or per-task |
| **Source** | YAML files, env vars | Code (constructor, block DSL) |
| **Mutability** | Loaded once, rarely changed | Created per use case, merged |
| **Purpose** | API keys, timeouts, defaults | Model, temperature, tools per workflow |

## Robot-Level Configuration

Individual robots can override the global model and other settings:

```ruby
# Override model for a specific robot
robot = RobotLab.build(
  name: "fast_bot",
  system_prompt: "You are a quick responder.",
  model: "claude-haiku-3-5",
  temperature: 0.3,
  max_tokens: 500
)

# Or use chaining at runtime
robot.with_temperature(0.9).with_max_tokens(2000).run("Tell me a story.")
```

## Hierarchical MCP and Tools

MCP servers and tools use a hierarchical configuration: `runtime > robot > network > global`. Each level can specify:

- `:inherit` -- Use the parent level's configuration
- `:none` -- No MCP servers or tools at this level
- An explicit array -- Specific servers or tools

```ruby
# Robot inheriting network MCP config
robot = RobotLab.build(
  name: "agent",
  system_prompt: "You are helpful.",
  mcp: :inherit,
  tools: :inherit
)

# Robot with no MCP, specific tools
robot = RobotLab.build(
  name: "calculator",
  system_prompt: "You solve math problems.",
  mcp: :none,
  local_tools: [Calculator]
)
```

## Next Steps

- [Building Robots](../guides/building-robots.md) - Create custom robots
- [Creating Networks](../guides/creating-networks.md) - Network configuration
- [MCP Integration](../guides/mcp-integration.md) - Configure MCP servers
