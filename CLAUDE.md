# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RobotLab is a Ruby framework for building and orchestrating multi-robot LLM workflows. It provides:
- **Robots**: LLM agents with tools, templates, and memory
- **Networks**: Orchestration of multiple robots with routing logic
- **MCP Integration**: Model Context Protocol servers (tools, resources, prompts) through ruby_llm's built-in `RubyLLM::MCP` client
- **Rails Integration**: Generators and ActiveRecord support for conversation history

Built on top of [ruby_llm](https://rubyllm.com) and uses Zeitwerk for autoloading.

## Commands

```bash
# Run all tests
bundle exec rake test

# Run a single test file
bundle exec rake test_file[robot_lab/robot_test.rb]

# Run tests with verbose output
bundle exec rake test_verbose

# Run integration tests only
bundle exec rake integration

# Lint with RuboCop
bundle exec rubocop

# Auto-fix RuboCop offenses
bundle exec rubocop -a

# Run all examples
bundle exec rake examples:all

# Run specific example by number (e.g., 01, 02)
bundle exec rake examples:run[1]
```

## Architecture

### Core Classes

- **`RobotLab`** (`lib/robot_lab.rb`): Module entry point with factory methods `build()` for robots and `create_network()` for networks
- **`Robot`** (`lib/robot_lab/robot.rb`): Subclass of `RubyLLM::Agent` with template-based prompts, tools, MCP servers, and memory. Creates a persistent chat on initialization. Use `robot.run("...")` to interact. When standalone uses its own memory; when in a network uses shared network memory
- **`Network`** (`lib/robot_lab/network.rb`): Orchestrates multiple robots with routing logic. Robots execute sequentially sharing memory. Router is a lambda that returns robot names
- **`NetworkRun`** (`lib/robot_lab/network_run.rb`): Stateful execution of a network run with isolated memory clone

### RunConfig

- **`RunConfig`** (`lib/robot_lab/run_config.rb`): Shared configuration object for LLM, tools, callbacks, and infrastructure settings. Flows through the hierarchy: `RobotLab.config -> Network -> Robot -> Template front matter -> Task -> Runtime`. Supports keyword construction, block DSL, merge semantics (more-specific wins), and `apply_to(chat)` for LLM field application. Both Robot and Network accept `config:` parameter. Infrastructure fields include: `bus`, `enable_cache`, `max_tool_rounds`, `token_budget`, `ractor_pool_size`, `max_concurrent_robots`, `doom_loop_threshold`, `auto_compact`, `compact_threshold`, `tool_approval`. Callback fields: `on_tool_call`, `on_tool_result`, `on_content`, `on_tool_approval`, `on_input_request`.

### Memory System

- **`Memory`** (`lib/robot_lab/memory.rb`): Key-value store with reserved keys (`:data`, `:results`, `:messages`, `:session_id`, `:cache`). Supports Redis backend. Semantic caching via RubyLLM::SemanticCache when the optional ruby_llm-semantic_cache gem is installed (`memory.cache` is nil otherwise)

### MCP (Model Context Protocol)

The MCP client is ruby_llm 2.1's `RubyLLM::MCP` (stdio and Streamable HTTP only; no SSE/WebSocket). robot_lab adds:

- **`RobotLab::MCP`** (`lib/robot_lab/mcp.rb`): `build(spec)` turns a config Hash into a `RubyLLM::MCP` instance (instances and subclasses pass through); `define(config)` returns the anonymous class; `name_of`, `seconds`. `sse`/`ws` transports raise `MCPError`
- **`MCP::Server`** (`lib/robot_lab/mcp/server.rb`): `RubyLLM::MCP` subclass with a `description` macro and `connected?`
- **`MCP::Registry`** (`lib/robot_lab/mcp/registry.rb`): a robot's servers by name; re-adding the same spec returns the existing server
- **`Robot::MCPManagement`** (`lib/robot_lab/robot/mcp_management.rb`): `mcp` (Registry), `with_mcp`, `connect_mcp!`, `mcp_tools`, `mcp_failures`, `mcp_server_for`, `disconnect`. Each run attaches the selected servers' `RubyLLM::MCP::Tool`s via `with_tools`
- **`Robot::ToolCallGating`** (`lib/robot_lab/robot/tool_call_gating.rb`): `:tool_call` hook bridge for non-`RobotLab::Tool` tools and settlement of approvals (`tool_approval:` `:deny` default / `:approve`, `on_tool_approval:`), input requests (`on_input_request:`) and MCP tasks
- **`MCP::ServerDiscovery`** (`lib/robot_lab/mcp/server_discovery.rb`): per-message server selection when `mcp_discovery: true`

### Built-in Tools

- **`AskUser`** (`lib/robot_lab/ask_user.rb`): Tool that lets a robot ask the user a question via the terminal. Supports open-ended text, multiple choice, and default values. IO sourced from `robot.input`/`robot.output` (defaults to `$stdin`/`$stdout`)

### Adapters

Provider adapters in `lib/robot_lab/adapters/`: Anthropic, OpenAI, Gemini (for provider-specific formatting)

### Configuration Hierarchy

Tools and MCP servers use hierarchical configuration: `runtime > robot > network > global config`. Values can be `:none`, `:inherit`, or explicit arrays (for `mcp:`, an array mixes config Hashes, `RubyLLM::MCP` instances and `RubyLLM::MCP` subclasses). `run()` defaults both to `:none`; pass `mcp: :inherit, tools: :inherit` to send MCP tools.

## Key Patterns

### Creating Robots

```ruby
# Bare robot (no template or prompt)
robot = RobotLab.build
robot.with_instructions("You are helpful.").run("Hello!")

# With template (.md file in prompts directory with YAML front matter)
robot = RobotLab.build(name: "helper", template: :helper, context: { key: "value" })
result = robot.run("Hello!")

# With inline system prompt
robot = RobotLab.build(name: "bot", system_prompt: "You are helpful.")
result = robot.run("What can you do?")

# With tools
robot = RobotLab.build(name: "bot", system_prompt: "...", local_tools: [my_tool])

# Chaining with_* methods
robot.with_temperature(0.9).with_model("claude-sonnet-4").run("Be creative!")
```

### Creating Networks

Networks are declared with a task DSL; there is no `robots:`/`router:` form.
`depends_on:` is `:none` (entry point), `:optional` (routed to only when a
prior robot selects it), or a list of task names (runs after those finish;
siblings sharing a dependency run in parallel).

```ruby
network = RobotLab.create_network(name: "support") do
  task :classifier, classifier_robot, depends_on: :none
  task :billing,    billing_robot,    depends_on: :optional
  task :technical,  technical_robot,  depends_on: :optional
end
result = network.run(message: "Hello")
```

`create_network` also accepts `concurrency:` (`:auto`, `:threads`, `:async`) and `config:`.

## Testing

- Uses Minitest with SimpleCov for coverage
- Test helper at `test/test_helper.rb` provides `build_robot`, `build_network`, `build_tool` helpers
- Templates for tests are in `examples/prompts/`
- VCR and WebMock for HTTP stubbing

## Dependencies

Core: zeitwerk, ruby_llm (>= 2.1.1, < 3 — its built-in `RubyLLM::MCP` is the MCP client), prompt_manager, async, simple_flow, state_machines

Optional: ruby_llm-semantic_cache (Memory#cache; no ruby_llm 2.0-compatible release yet — Memory runs with caching disabled when absent), classifier (compress_history), ruby_llm-providers-lms (local LM Studio provider used by the examples: qwen/qwen3.8-27b for complex work, openai/gpt-oss-20b for simple demos)

### Templates

Templates use prompt_manager format: single `.md` files with YAML front matter in the configured prompts directory.

```markdown
---
description: A helpful assistant
parameters:
  company_name: null
  tone: friendly
---
You are a helpful assistant for <%= company_name %>.
Respond in a <%= tone %> manner.
```

Front matter supports: `description`, `parameters` (null = required), LLM config keys (`model`, `temperature`, `top_p`, `top_k`, `max_tokens`, etc.), and robot extras (`robot_name`, `tools`, `mcp`). Constructor-provided values always override front matter.
