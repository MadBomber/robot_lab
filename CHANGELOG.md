# Changelog

> [!CAUTION]
> This gem is under active development. APIs and features may change without notice.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

## [0.0.4] - 2026-02-16 [unreleased]

### Added

- **`AskUser` tool** for human-in-the-loop interactions
  - Supports open-ended text, multiple choice, and default values
  - IO sourced from `robot.input`/`robot.output` (defaults to `$stdin`/`$stdout`)
  - Full test suite (`test/robot_lab/ask_user_test.rb`)
- **`Robot#input` / `Robot#output` accessors** for configurable IO streams
- **`reply` alias** for `RobotResult#last_text_content` — shorter, more natural API
- **`.irbrc`** for loading RobotLab in project-level IRB sessions
- **`wait_until` test helper** replacing flaky `sleep`-based assertions in async tests
- Documentation for AskUser tool across API reference, guides, and examples

### Changed

- Bumped version to 0.0.4
- **Made Rails dependencies optional** — removed `railties`, `activerecord`, `state_machines`, `state_machines-activemodel`, `state_machines-activerecord` from gemspec hard dependencies; moved to Gemfile `:test` group
- Replaced `require 'active_support'` with targeted `require 'active_support/core_ext/module/delegation'` — only loads what ruby_llm actually needs
- Added `activesupport >= 7.0` as explicit gemspec dependency with comment explaining it's required by ruby_llm (undeclared upstream)
- **Tool JSON schema keys are now symbolized** via `deep_symbolize_keys` in `Tool#to_json_schema`
- Updated all examples to use `reply` alias instead of `last_text_content`
- Replaced `sleep`-based test assertions with `wait_until` helper in memory, waiter, and robot tests
- Disabled branch coverage in SimpleCov except in CI

### Fixed

- Gem install conflict (`activesupport` version mismatch) when running outside Bundler
- IRB loading issue where `require_relative` was a no-op due to partial load in `$LOADED_FEATURES` — switched to `load`
- Robot tests for `send_message` now register a message handler on the receiver to avoid TypedBus warnings

## [0.0.3] - 2026-02-15 [unreleased]

### Added

- **Self-contained templates** with extended YAML front matter support
  - `robot_name` — override robot name from template
  - `description` — set robot description from template
  - `tools` — declare tool class names (resolved via `Object.const_get` at build time)
  - `mcp` — declare MCP server configurations
  - Constructor-provided values always take precedence over front matter
- **Editorial pipeline example** (`15_memory_network_and_bus/`) demonstrating multi-stage workflow with network, memory, and bus coordination
  - OS-specific writer robots, editor, and editor-in-chief roles
  - New prompt templates: `os_advocate`, `os_editor`, `os_chief`
- Rakefile support for running subdirectory-based examples with `SUBDIR_ENTRY_POINTS` mapping

### Changed

- Bumped version to 0.0.3
- Refactored Comic and Scout classes to use `attr_accessor` instead of `instance_variable_set`/`instance_variable_get`
- Extensive documentation updates across README, guides, API reference, and examples for front matter extras

## [0.0.2] - 2026-02-15 (unreleased)

### Added

- **TypedBus message bus** for robot-to-robot communication
  - `RobotMessage` immutable data class (`Data.define`) with `id`, `from`, `content`, `in_reply_to`
  - Optional `bus:` parameter on Robot constructor — purely additive
  - `on_message` handler with auto-ACK (1-arg block) and manual ACK/NACK (2-arg block)
  - `publish_to_bus` with Async-aware fiber wrapping
  - Typed channels accepting only `RobotMessage` objects
- **Dynamic robot spawning** via `Robot#spawn` method for creating child robots at runtime
- **`with_bus` configuration method** for connecting robots to a message bus after creation
- **Comic robot class** with dynamic comedy tools (`reinvent_style`, `adjust_energy`, `get_coaching`)
- New examples:
  - `12_message_bus.rb` — two-robot joke critique workflow
  - `13_spawn.rb` — dynamic robot spawning
  - `14_rusty_circuit/` — multi-robot comedy open mic with bus-based coordination
- New prompt templates: `comedian`, `comedy_critic`, `dispatcher`, `open_mic_comic`, `open_mic_heckler`, `open_mic_scout`, `configurable`, `llm_config_demo`
- Rake tasks for building documentation sites
- GitHub Actions workflow for YARD documentation deployment

### Changed

- Bumped version to 0.0.2
- Replaced `ruby_llm-template` dependency with `prompt_manager` (~> 1.0)
- Updated `ruby_llm` dependency to ~> 1.12
- Added `typed_bus` as a core dependency
- Added `myway_config` (~> 0.1) dependency
- Added `amazing_print` and `hashdiff` as development dependencies
- Migrated all prompt templates from directory-based format (`system.txt.erb` / `user.txt.erb`) to single `.md` files with YAML front matter
- Refactored `Robot` class for simplified configuration
- Refactored `Config` class
- Extensive documentation updates across all guide, architecture, and API reference pages

### Fixed

- GitHub Actions platform limitation (`arm64-darwin` only in lockfile)

## [0.0.1] - 2026-01-16

- refactored the network concept
- refactored the memory concept

### Needs Refactoring

- **Network concept is unhinged and needs complete refactoring.** The current implementation has several design issues:
  - Robots have separate memory when standalone vs in a network, causing confusion about what `robot.reset_memory` affects
  - Sequential execution only - no concurrent robot support despite infrastructure hints
  - Memory thread-safety is implemented but untested in practice
  - Unclear ownership model - robots don't know they're in a network
  - The relationship between Robot, Network, NetworkRun, and Memory needs simplification

### Added

- `Network#add_robot(robot)` - adds a robot, raises if name already exists
- `Network#replace_robot(robot)` - replaces existing robot, raises if not found
- `Network#remove_robot(name_or_robot)` - removes by name (String/Symbol) or Robot instance
- `Memory#enable_cache` parameter - allows disabling semantic caching
- `RobotLab.build`, `RobotLab.create_network`, `RobotLab.create_memory` now accept `enable_cache:` parameter
- Documentation for memory behavior (standalone vs network contexts)
- Documentation explaining what a Network is and when to use one
- Full MkDocs documentation site with Material theme
  - Getting Started guides (installation, quick start, configuration)
  - Architecture documentation (core concepts, robot execution, network orchestration, state management, message flow)
  - How-to guides (building robots, creating networks, using tools, MCP integration, streaming, history, memory, Rails integration)
  - Complete API reference (Robot, Network, State, Tool, Memory, Messages, Adapters, MCP, Streaming, History)
  - Working examples (basic chat, multi-robot network, tool usage, MCP server, Rails application)
- Documentation site logo and branding
- README.md redesign with top table layout pattern
- Network memory with concurrent robots example

### Changed

- Updated README.md with new tagline: "Build robots. Solve problems."
- Enhanced Rakefile with bundler/gem_tasks and test_helper preloading
- Updated gemspec summary and description for accuracy

## [0.0.0] - 2026-01-13

- Initial design
