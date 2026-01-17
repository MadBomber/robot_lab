# Changelog

> [!CAUTION]
> This gem is under active development. APIs and features may change without notice.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

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
