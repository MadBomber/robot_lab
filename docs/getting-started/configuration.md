# Configuration

RobotLab uses a layered configuration system powered by [MywayConfig](https://github.com/MadBomber/myway_config). Configuration is loaded automatically from multiple sources with no block-style `configure` method required.

## How Configuration Works

Configuration values are loaded in priority order (lowest to highest):

1. **Bundled defaults** -- `lib/robot_lab/config/defaults.yml` (shipped with the gem)
2. **Environment-specific overrides** -- `development`, `test`, or `production` sections in defaults.yml
3. **User config file** -- `~/.config/robot_lab/robot_lab.yml`
4. **Project config file** -- `./config/robot_lab.yml`
5. **Environment variables** -- `ROBOT_LAB_*` prefix
6. **Runtime attributes** -- e.g., `RobotLab.config.logger = ...`

Higher-priority sources override lower-priority ones. You only need to set the values you want to change.

> [!IMPORTANT]
> The user config file is `~/.config/robot_lab/**robot_lab**.yml` — the filename
> repeats the application name. `~/.config/robot_lab/config.yml` is **never
> read**, and RobotLab gives no warning when it is present but ignored.

## Accessing Configuration

Use `RobotLab.config` to access the configuration object:

```ruby
# Access nested values with dot notation
RobotLab.config.ruby_llm.model            #=> "claude-sonnet-4"
RobotLab.config.ruby_llm.anthropic_api_key #=> "sk-ant-..."
RobotLab.config.ruby_llm.request_timeout  #=> 120
RobotLab.config.template_path              #=> nil (auto-detected)

# Check the environment
RobotLab.config.development?  #=> true/false
```

!!! tip "configure block"
    `RobotLab.configure` yields the config object for block-style setup — useful for setting runtime-only attributes like the logger. For static settings (API keys, timeouts, model defaults) prefer config files or environment variables.

    ```ruby
    RobotLab.configure do |c|
      c.logger = Logger.new(File::NULL)   # silence all RobotLab logging
    end
    ```

## Environment Variables

Environment variables use the `ROBOT_LAB_` prefix. Use double underscores (`__`) for nested values:

```bash
# Top-level settings
export ROBOT_LAB_TEMPLATE_PATH=prompts

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
ROBOT_LAB_TEMPLATE_PATH                -->  template_path
```

> [!WARNING]
> **Nested values arrive as Strings.** Only top-level keys are type-coerced.
> With `ROBOT_LAB_RUBY_LLM__REQUEST_TIMEOUT=180` set,
> `RobotLab.config.ruby_llm.request_timeout` returns the String `"180"`, not the
> Integer `180`. If a numeric nested setting matters to your code, set it in a
> config file instead, or coerce it yourself with `.to_i` / `.to_f`.

## Config Files

> [!WARNING]
> **A `defaults:` wrapper is always ignored in your own files.** The `defaults:`
> key you see inside the gem's bundled `lib/robot_lab/config/defaults.yml` applies
> **only to that bundled file**. Wrap your own settings in it and every value
> silently falls back to the default — no error, no warning.
>
> ```yaml
> # WRONG — silently ignored in a user or project config file
> defaults:
>   template_path: prompts
>
> # RIGHT
> template_path: prompts
> ```
>
> Sections named for the **current environment** (`development:`, `test:`,
> `production:`) are a different matter, and the two files disagree:
>
> | File | Flat keys | `development:` section |
> |------|-----------|------------------------|
> | `~/.config/robot_lab/robot_lab.yml` | honoured | honoured |
> | `./config/robot_lab.yml` (no Rails) | honoured | ignored |
> | `./config/robot_lab.yml` (under Rails) | **ignored** | **honoured** |
>
> The user file checks for a section matching the current environment and falls
> back to the file root, so both forms work. The project file is read by
> anyway_config, which only treats it as environmental once
> `Anyway::Settings.current_environment` is set — which is precisely what Rails
> does (it sets it to `Rails.env`). See [Rails Integration](#rails-integration).

### Project Config

Create `./config/robot_lab.yml` in your project root. Outside Rails, write the
keys at the top level (under Rails they must be nested under the environment name
instead — see [Rails Integration](#rails-integration)):

```yaml title="config/robot_lab.yml"
ruby_llm:
  anthropic_api_key: <%= ENV['ANTHROPIC_API_KEY'] %>
  model: claude-sonnet-4
  request_timeout: 120
  max_retries: 3
  log_level: info

template_path: prompts
```

> [!NOTE]
> **ERB works here, and only here.** The project config file is read through ERB,
> so `<%= ENV['ANTHROPIC_API_KEY'] %>` is expanded before the YAML is parsed. The
> user config file described below is **not** — see the warning there.

> [!WARNING]
> **No YAML symbols in the project config file.** It is parsed with an empty
> permitted-classes list, so `log_level: :info` raises
> `Psych::DisallowedClass: Tried to load unspecified class: Symbol` and your
> application fails to boot. Write the plain string `log_level: info`. (Symbols
> *are* permitted in the bundled `defaults.yml` and in the user config file,
> which is why you will see `:debug` there.)

### User Config

Create `~/.config/robot_lab/robot_lab.yml` for personal defaults that apply
across all your projects. Keys go at the top level here too:

```yaml title="~/.config/robot_lab/robot_lab.yml"
ruby_llm:
  model: claude-sonnet-4
  request_timeout: 120
```

> [!WARNING]
> **Do not put ERB in the user config file.** It is parsed with
> `YAML.safe_load` and never passed through ERB, so
> `anthropic_api_key: <%= ENV['ANTHROPIC_API_KEY'] %>` is stored as the literal
> nine-character-plus string `"<%= ENV['ANTHROPIC_API_KEY'] %>"` and sent to the
> provider as your API key. Put secrets in environment variables
> (`ANTHROPIC_API_KEY` or `ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY`), or in the
> project config file where ERB is evaluated.

> [!NOTE]
> The user config file honours **both** forms: flat keys at the root, or a
> top-level section named for the current environment (`development:`, `test:`,
> `production:`). The loader looks for the environment section first and falls back
> to the root. Only `defaults:` is ignored here.

## Configuration Reference

### Core Settings

| Key | Default | Description |
|-----|---------|-------------|
| `template_path` | `null` (auto-detected) | Directory for prompt templates |
| `mcp` | `:none` | Global MCP server configuration |
| `tools` | `:none` | Global tool allowlist |
| `sandbox.*` | see below | Skill-script confinement ceiling |

> [!WARNING]
> **Reserved / not implemented.** `defaults.yml` also ships `max_iterations`,
> `max_tool_iterations`, `streaming_enabled`, and an entire `chat:` tree
> (`chat.with_model`, `chat.with_temperature`, `chat.with_tools`,
> `chat.with_params.*`). These keys resolve — `RobotLab.config.max_iterations`
> returns `10` — but **nothing in the library reads them**. Setting them has zero
> effect. They are placeholders; do not build on them.
>
> The real equivalents are:
>
> | Dead key | Use instead |
> |----------|-------------|
> | `max_tool_iterations` | `max_tool_rounds:` on a robot or `RunConfig` |
> | `streaming_enabled` | `on_content:` callback, or a block passed to `run` |
> | `chat.with_temperature` | `temperature:` on a robot or `RunConfig` |
> | `chat.with_params.*` | `top_p:` / `max_tokens:` / etc. on a robot or `RunConfig` |
> | `max_iterations` | no equivalent — networks are bounded by their task graph |

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
| `ruby_llm.model` | `claude-sonnet-4` | Default model for robots that do not set `model:` |
| `ruby_llm.default_model` | `null` | RubyLLM default model override |
| `ruby_llm.default_embedding_model` | `null` | Default embedding model |
| `ruby_llm.default_image_model` | `null` | Default image model |

> [!NOTE]
> `defaults.yml` also carries `ruby_llm.provider: :anthropic` and
> `ruby_llm.assume_model_exists: false`, but neither is read. A robot's provider
> comes from its own `provider:` keyword argument, and `assume_model_exists` is
> derived from whether that argument was given. Model ids must be full RubyLLM
> ids — an unknown id raises `RubyLLM::ModelNotFoundError` when the robot is
> constructed.

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

### Chat Configuration (`chat:` section) — not implemented

The `chat:` tree in `defaults.yml` (`chat.with_temperature`,
`chat.with_params.top_p`, `chat.with_params.max_tokens`, `chat.with_tools`, …)
is **reserved and has no consumers**. Values set there are parsed and then
ignored.

To set LLM parameters globally, pass a `RunConfig` to each robot, or set them per
robot with constructor keyword arguments:

```ruby
robot = RobotLab.build(
  name: "bot",
  system_prompt: "You are helpful.",
  temperature: 0.7,
  max_tokens: 2000,
  top_p: 0.9
)
```

### Skill-Script Sandboxing (`sandbox:` section)

Opt-in confinement for the scripts a [skill bundle](../guides/using-tools.md#skill-scripts-and-sandboxing) exposes as tools. Disabled by default — scripts run exactly as before until you turn it on:

| Key | Default | Description |
|-----|---------|-------------|
| `sandbox.enabled` | `false` | Turn on OS-level confinement for skill scripts |
| `sandbox.fs_read` | `["."]` | Ceiling: paths any skill script may read (relative to cwd) |
| `sandbox.fs_write` | `[]` | Ceiling: paths any skill script may write |
| `sandbox.network` | `false` | Ceiling: whether any skill script may use the network |
| `sandbox.timeout` | `60` | Ceiling: max seconds a skill script may run |

These are a **ceiling**, not a grant — the actual permissions a script runs with are the intersection of this ceiling and what the individual SKILL.md declares for itself. See [Skill Scripts and Sandboxing](../guides/using-tools.md#skill-scripts-and-sandboxing) for how the two combine and which platforms actually enforce confinement.

## Runtime-Only Attributes

Some attributes can only be set at runtime, not through config files. Use direct assignment on `RobotLab.config` or the `RobotLab.configure` block:

```ruby
# Direct assignment
RobotLab.config.logger = Logger.new(nil)          # silence logging
RobotLab.config.logger = Logger.new("robot.log")  # log to file

# Block-style configure (equivalent, useful when setting multiple values)
RobotLab.configure do |c|
  c.logger = Logger.new(File::NULL)
end
```

`RobotLab.configure` yields the same `Config` object returned by `RobotLab.config`.

## Reloading Configuration

To reload configuration from all sources:

```ruby
RobotLab.reload_config!
```

This clears the cached config and reloads from all sources on next access.

## Environment-Specific Configuration

The `defaults.yml` shipped with RobotLab includes environment-specific overrides.
This is what the gem actually ships:

=== "Development"

    ```yaml
    development:
      ruby_llm:
        log_level: :debug
    ```

=== "Test"

    ```yaml
    test:
      max_iterations: 3          # reserved, no effect
      streaming_enabled: false   # reserved, no effect
      ruby_llm:
        model: claude-3-haiku-20240307
        request_timeout: 30
        max_retries: 1
        log_level: :warn
    ```

=== "Production"

    ```yaml
    production:
      streaming_enabled: false   # reserved, no effect
      max_iterations: 20         # reserved, no effect
      ruby_llm:
        request_timeout: 180
        max_retries: 5
        log_level: :warn
    ```

The current environment is determined automatically (via `RAILS_ENV`, `RACK_ENV`, or defaults to `development`).

> [!NOTE]
> Under `test`, the effective default model is `claude-3-haiku-20240307` — a full
> dated model id. Short aliases like `claude-haiku-3-5` are **not** valid RubyLLM
> model ids and raise `RubyLLM::ModelNotFoundError` at robot construction.

## Rails Integration

> [!NOTE]
> Core RobotLab ships **no Railtie and no Engine**. It performs two bare
> `defined?(::Rails)` checks: the default logger becomes `Rails.logger`, and
> `template_path` resolves to `Rails.root/app/prompts` when left unset. Generators,
> `RobotLab::Job`, and Turbo broadcasting live in the separate
> [robot_lab-rails](https://github.com/MadBomber/robot_lab-rails) gem.

> [!WARNING]
> **Under Rails, `./config/robot_lab.yml` must be environment-sectioned — a flat
> file is ignored.** Rails' anyway_config integration sets
> `Anyway::Settings.current_environment` to `Rails.env`, which switches the project
> config loader into environmental mode. Keys then have to live under
> `development:` / `test:` / `production:`; anything written at the root of the file
> is dropped. Outside Rails the rule is exactly inverted — flat keys are read and an
> environment section is ignored.

```yaml title="config/robot_lab.yml (under Rails)"
development:
  ruby_llm:
    anthropic_api_key: <%= Rails.application.credentials.anthropic_api_key %>
    model: claude-sonnet-4
    request_timeout: 180
    max_retries: 5
  template_path: null  # auto-detects app/prompts in Rails

production:
  ruby_llm:
    anthropic_api_key: <%= Rails.application.credentials.anthropic_api_key %>
    model: claude-sonnet-4
    request_timeout: 180
    max_retries: 5
```

The same file outside Rails would instead be written flat:

```yaml title="config/robot_lab.yml (no Rails)"
ruby_llm:
  model: claude-sonnet-4
  request_timeout: 180

template_path: prompts
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

`./config/robot_lab.yml` is evaluated through ERB, so credentials can be
referenced inline as shown above. Note that this only works in the **project**
config file — the `~/.config/robot_lab/robot_lab.yml` user file is not run
through ERB.

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

# Network-level config
network = RobotLab.create_network(name: "pipeline", config: shared) do
  task :analyzer, analyzer_robot, depends_on: :none
  task :writer, writer_robot, depends_on: [:analyzer]
end
```

> [!WARNING]
> **A network-level `config:` propagates only `mcp` and `tools`** — and only when
> the member robot opts in by passing `mcp: :inherit` / `tools: :inherit` on its
> `run`. LLM fields (`model`, `temperature`, `max_tokens`, …) and callbacks
> (`on_content`, `on_tool_call`, `on_tool_result`) are read from each robot's
> **own** config at construction time and are never inherited from the network.
> The only field the network itself consumes is `max_concurrent_robots`.
>
> If you want a whole team on one model, pass the same `config:` to each robot:
>
> ```ruby
> shared  = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.5)
> analyst = RobotLab.build(name: "analyst", system_prompt: "...", config: shared)
> writer  = RobotLab.build(name: "writer",  system_prompt: "...", config: shared)
> ```
>
> A per-task `config:` is merged into the network config and is subject to the
> same `mcp`/`tools`-only limitation.

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
| **Callbacks** | `on_tool_call`, `on_tool_result`, `on_content` |
| **Infrastructure** | `bus`, `enable_cache`, `max_tool_rounds`, `token_budget`, `cost_budget`, `max_tools`, `ractor_pool_size`, `max_concurrent_robots`, `doom_loop_threshold`, `auto_compact`, `compact_threshold` |

`cost_budget` mirrors `token_budget` for cumulative dollar spend — see [Budgets](../guides/observability.md#budgets-token-cost). `max_tools` overrides the default 128-tool ceiling enforced on every turn before tools are handed to the provider — see [Tool Capping](../guides/using-tools.md#tool-capping-and-per-turn-filtering).

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
  model: "claude-3-haiku-20240307",
  temperature: 0.3,
  max_tokens: 500
)

# Or use chaining at runtime
robot.with_temperature(0.9).with_params(max_tokens: 2000).run("Tell me a story.")
```

> [!WARNING]
> There is **no `with_max_tokens`, `with_top_p`, `with_top_k`, `with_stop`,
> `with_presence_penalty`, or `with_frequency_penalty`** — calling them raises
> `NoMethodError`. The complete chainable set is `with_context`, `with_headers`,
> `with_instructions`, `with_model`, `with_params`, `with_schema`,
> `with_temperature`, `with_thinking`, `with_tool`, `with_tools`, plus RobotLab's
> own `with_template` and `with_bus`. For everything else use a constructor
> keyword argument or `with_params(...)`.

## Hierarchical MCP and Tools

MCP servers and tools use a hierarchical configuration: `runtime > robot > network > global`. Each level can specify:

- `:inherit` -- Use the parent level's configuration
- `:none` -- No MCP servers or tools at this level
- An explicit array -- A name **allowlist** (not a local-vs-MCP switch). Entries are
  compared as strings against each attached tool's `name`, so they must match the
  form the tool was attached in: a tool attached as a class matches `[RefundTool]`
  or `%w[RefundTool]`, while one attached as an instance matches `%w[refund]`

> [!WARNING]
> **`tools:` and `mcp:` both default to `:none` — including on `run()` itself.**
> `Robot#run` is declared `run(message = nil, ..., mcp: :none, tools: :none, ...)`,
> and an explicit `:none` means "send zero tools this turn". So a plain
> `robot.run("...")` sends the LLM **no tools and connects no MCP servers**, even
> when you passed `local_tools:` or `mcp:` at build time.
>
> The fix goes on the **run**, not the build:
>
> ```ruby
> robot.run("...", tools: :inherit)                  # send the attached local tools
> robot.run("...", mcp: :inherit, tools: :inherit)   # connect MCP and send its tools
> ```
>
> `mcp: :inherit` triggers the connection; `tools: :inherit` is additionally
> required for the MCP tools to actually be handed to the model.

> [!IMPORTANT]
> **For a standalone robot, do not pass `tools: :inherit` at build time.** Build-time
> `:inherit` resolves against the parent level, and for a standalone robot the parent
> is the global `:none` — producing an allowlist of `["none"]` that matches nothing
> and suppresses the tools even when the run asks for `:inherit`. Verified
> resolution for a standalone robot:
>
> | build `tools:` | run `tools:` | tools sent |
> |---|---|---|
> | unset | `:none` (default) | none |
> | unset | `:inherit` | the attached tools ✅ |
> | `:inherit` | `:inherit` | **none** ❌ |
> | `:inherit` | `:none` | none |
> | `:none` | `:inherit` | the attached tools ✅ |
>
> Leave `tools:` unset at build time — unless the robot is a member of a network.

> [!NOTE]
> **Inside a network, build-time `:inherit` is the opt-in, not a bug.** The parent
> is resolved at run time as the network's `config:`, so `:inherit` is how a robot
> asks for the network-level allowlist. With
> `RobotLab::RunConfig.new(tools: %w[RefundTool])` on the network and a robot
> holding `local_tools: [RefundTool, InvoiceTool]`:
>
> | build `tools:` | task `tools:` | tools sent |
> |---|---|---|
> | unset | omitted (`:none`) | none |
> | unset | `:inherit` | `refund`, `invoice` — the network allowlist is **not** applied |
> | `:inherit` | `:inherit` | `refund` — the network allowlist **is** applied ✅ |
> | `:inherit` | omitted (`:none`) | none |
>
> The same reasoning applies to `mcp:`.

```ruby
# Correct: attach tools at build time, request them at run time
robot = RobotLab.build(
  name: "calculator",
  system_prompt: "You solve math problems.",
  local_tools: [Calculator]
)

robot.run("What is 17 * 23?", tools: :inherit)

# Robot with MCP servers attached at build time
robot = RobotLab.build(
  name: "agent",
  system_prompt: "You are helpful.",
  mcp: [{ name: "filesystem", transport: { type: "stdio", command: "mcp-server-filesystem" } }]
)

robot.run("List the files in ./lib", mcp: :inherit, tools: :inherit)
```

See [Runtime Tool Filtering](../guides/using-tools.md#runtime-tool-filtering) for the full `:inherit`/`:none`/array semantics.

## Next Steps

- [Building Robots](../guides/building-robots.md) - Create custom robots
- [Creating Networks](../guides/creating-networks.md) - Network configuration
- [MCP Integration](../guides/mcp-integration.md) - Configure MCP servers
