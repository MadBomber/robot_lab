# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RobotLab is a Ruby framework for building and orchestrating multi-robot LLM workflows. It provides:
- **Robots**: LLM agents with tools, templates, and memory
- **Networks**: Orchestration of multiple robots with routing logic
- **MCP Integration**: Model Context Protocol for external tool servers
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
- **`Robot`** (`lib/robot_lab/robot.rb`): Subclass of `RubyLLM::Agent` with template-based prompts, tools, MCP clients, and memory. Creates a persistent chat on initialization. Use `robot.run("...")` to interact. When standalone uses its own memory; when in a network uses shared network memory
- **`Network`** (`lib/robot_lab/network.rb`): Orchestrates multiple robots with routing logic. Robots execute sequentially sharing memory. Router is a lambda that returns robot names
- **`NetworkRun`** (`lib/robot_lab/network_run.rb`): Stateful execution of a network run with isolated memory clone

### RunConfig

- **`RunConfig`** (`lib/robot_lab/run_config.rb`): Shared configuration object for LLM, tools, callbacks, and infrastructure settings. Flows through the hierarchy: `RobotLab.config -> Network -> Robot -> Template front matter -> Task -> Runtime`. Supports keyword construction, block DSL, merge semantics (more-specific wins), and `apply_to(chat)` for LLM field application. Both Robot and Network accept `config:` parameter. Infrastructure fields include: `bus`, `enable_cache`, `max_tool_rounds`, `token_budget`, `ractor_pool_size`, `max_concurrent_robots`, `doom_loop_threshold`, `auto_compact`, `compact_threshold`.

### Memory System

- **`Memory`** (`lib/robot_lab/memory.rb`): Key-value store with reserved keys (`:data`, `:results`, `:messages`, `:session_id`, `:cache`). Supports Redis backend. Includes semantic caching via RubyLLM::SemanticCache

### MCP (Model Context Protocol)

- **`MCP::Client`** (`lib/robot_lab/mcp/client.rb`): Connects to MCP servers
- **Transports** (`lib/robot_lab/mcp/transports/`): stdio, websocket, SSE, streamable HTTP

### Built-in Tools

- **`AskUser`** (`lib/robot_lab/ask_user.rb`): Tool that lets a robot ask the user a question via the terminal. Supports open-ended text, multiple choice, and default values. IO sourced from `robot.input`/`robot.output` (defaults to `$stdin`/`$stdout`)

### Adapters

Provider adapters in `lib/robot_lab/adapters/`: Anthropic, OpenAI, Gemini (for provider-specific formatting)

### Configuration Hierarchy

Tools and MCP servers use hierarchical configuration: `runtime > robot > network > global config`. Values can be `:none`, `:inherit`, or explicit arrays.

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

```ruby
router = ->(args) { args.call_count.zero? ? ["classifier"] : nil }
network = RobotLab.create_network(name: "support", robots: [robot1, robot2], router: router)
result = network.run(message: "Hello")
```

### Router Args

Router receives `Router::Args` with: `context`, `network`, `stack`, `call_count`, `last_result`

## Testing

- Uses Minitest with SimpleCov for coverage
- Test helper at `test/test_helper.rb` provides `build_robot`, `build_network`, `build_tool` helpers
- Templates for tests are in `examples/prompts/`
- VCR and WebMock for HTTP stubbing

## Dependencies

Core: zeitwerk, ruby_llm (~> 1.12), ruby_llm-mcp, prompt_manager, ruby_llm-schema, ruby_llm-semantic_cache, async, simple_flow, state_machines

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
