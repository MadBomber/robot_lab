# Guides

Practical guides for building applications with RobotLab.

## Getting Started

If you're new to RobotLab, start here:

<div class="grid cards" markdown>

-   [:octicons-cpu-24: **Building Robots**](building-robots.md)

    Create specialized AI agents with personalities and tools

-   [:octicons-git-branch-24: **Creating Networks**](creating-networks.md)

    Orchestrate multiple robots for complex workflows

</div>

## Core Features

<div class="grid cards" markdown>

-   [:octicons-tools-24: **Using Tools**](using-tools.md)

    Give robots custom capabilities to interact with external systems

-   [:octicons-server-24: **MCP Integration**](mcp-integration.md)

    Connect to Model Context Protocol servers

-   [:octicons-broadcast-24: **Streaming Responses**](streaming.md)

    Real-time streaming of LLM responses

-   [:octicons-cpu-24: **Memory System**](memory.md)

    Share data between robots with the memory system

-   [:octicons-pulse-24: **Observability & Safety**](observability.md)

    Token tracking, circuit breakers, and learning accumulation

</div>

## Guide Index

| Guide | Description | Time |
|-------|-------------|------|
| [Building Robots](building-robots.md) | Create and configure robots | 10 min |
| [Creating Networks](creating-networks.md) | Multi-robot orchestration | 15 min |
| [Using Tools](using-tools.md) | Add custom capabilities | 10 min |
| [MCP Integration](mcp-integration.md) | External tool servers | 10 min |
| [Streaming](streaming.md) | Real-time responses | 5 min |
| [Memory](memory.md) | Shared data store | 5 min |
| [Observability & Safety](observability.md) | Token tracking, circuit breaker, learning loop | 10 min |

## Extension Gems

Additional capabilities are available as separate gems:

| Gem | Description | Docs |
|-----|-------------|------|
| [robot_lab-rails](https://github.com/MadBomber/robot_lab-rails) | Rails generators, background jobs, Turbo Stream broadcasting | [Rails Integration guide](https://github.com/MadBomber/robot_lab-rails/blob/main/docs/guides/rails-integration.md) |
| [robot_lab-ractor](https://github.com/MadBomber/robot_lab-ractor) | True CPU parallelism for tools and robot pipelines via Ruby Ractors | [Ractor Parallelism guide](https://github.com/MadBomber/robot_lab-ractor/blob/main/docs/guides/ractor-parallelism.md) |
| [robot_lab-durable](https://github.com/MadBomber/robot_lab-durable) | Cross-session knowledge persistence with YAML-backed storage | [robot_lab-durable README](https://github.com/MadBomber/robot_lab-durable) |
| [robot_lab-document_store](https://github.com/MadBomber/robot_lab-document_store) | Embedding-based semantic document search via fastembed | [robot_lab-document_store README](https://github.com/MadBomber/robot_lab-document_store) |
