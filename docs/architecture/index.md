# Architecture Overview

RobotLab is designed around a few core architectural principles that enable flexible, composable AI workflows.

## Design Philosophy

### 1. Separation of Concerns

Each component has a single, well-defined responsibility:

- **Robot**: LLM-powered agent (subclass of `RubyLLM::Agent`) with personality, tools, and memory
- **Network**: Orchestrates robot execution as a DAG pipeline via SimpleFlow
- **Memory**: Reactive key-value store for robot and network data
- **Tool**: Provides external capabilities to robots (inherits from `RubyLLM::Tool`)
- **Task**: Wraps a robot for pipeline execution with per-task configuration

### 2. Composability

Components are designed to be mixed and matched:

- Robots can be used standalone or within networks
- Tools can be shared across robots or scoped per-robot via `local_tools:`
- Networks define DAG pipelines with sequential, parallel, and optional execution
- Memory can be standalone (per-robot) or shared (per-network)
- `with_*` methods return `self` for fluent chaining

### 3. Provider Agnostic

RobotLab abstracts away LLM provider differences through RubyLLM:

- Unified interface across Anthropic, OpenAI, Gemini, DeepSeek, Mistral, and others
- Consistent tool calling interface
- Automatic provider detection from model names
- Easy switching between providers via configuration

## System Architecture

```mermaid
graph TB
    subgraph "Application Layer"
        A[Your Application]
    end

    subgraph "RobotLab Core"
        B[Network]
        C[Task]
        D[Robot < RubyLLM::Agent]
        E[Memory]
        F[RobotResult]
    end

    subgraph "Configuration"
        G[Config < MywayConfig::Base]
    end

    subgraph "Integration Layer"
        H[MCP Client]
        I[Tools < RubyLLM::Tool]
        J[Templates / prompt_manager]
    end

    subgraph "Execution Layer"
        K[SimpleFlow::Pipeline]
        L[RubyLLM Chat]
    end

    subgraph "Provider Layer"
        M[Anthropic]
        N[OpenAI]
        O[Gemini]
        P[MCP Servers]
    end

    A --> B
    A --> D
    B --> C
    C --> D
    B --> K
    B --> E
    D --> E
    D --> L
    D --> H
    D --> I
    D --> J
    D --> F
    G --> D
    G --> L
    L --> M
    L --> N
    L --> O
    H --> P
```

## Core Components

| Component | Description | Documentation |
|-----------|-------------|---------------|
| **Robot** | LLM agent (subclass of `RubyLLM::Agent`) with template-based prompts, tools, and memory | [Core Concepts](core-concepts.md) |
| **Network** | Orchestrates multiple robots as a SimpleFlow pipeline | [Network Orchestration](network-orchestration.md) |
| **Memory** | Reactive key-value store with pub/sub and blocking reads | [Memory Management](state-management.md) |
| **Task** | Wraps a robot for pipeline execution with per-task config | [Network Orchestration](network-orchestration.md) |
| **RobotResult** | Captures LLM output, tool calls, and metadata from a run | [Message Flow](message-flow.md) |
| **Config** | MywayConfig-based configuration with env var and file support | [Configuration](#configuration) |

## Configuration

RobotLab uses MywayConfig (`Config < MywayConfig::Base`) instead of a `configure` block. Configuration is loaded from multiple sources in priority order:

1. **Bundled defaults** (`lib/robot_lab/config/defaults.yml`)
2. **Environment overrides** (development, test, production sections)
3. **XDG user config** (`~/.config/robot_lab/config.yml`)
4. **Project config** (`./config/robot_lab.yml`)
5. **Environment variables** (`ROBOT_LAB_*` prefix, double underscore for nesting)

```ruby
# Access configuration
RobotLab.config.ruby_llm.model            #=> "claude-sonnet-4"
RobotLab.config.ruby_llm.request_timeout  #=> 120
```

## Data Flow

1. **Input**: User calls `robot.run("message")` or `network.run(message: "...")`
2. **Memory**: Robot resolves active memory (standalone or network-shared)
3. **MCP**: Robot resolves and initializes MCP clients from hierarchical config
4. **Tools**: Robot resolves and filters tools from hierarchical config
5. **Execution**: Robot delegates to `Agent#ask` which calls `@chat.ask` on RubyLLM
6. **Tool Loop**: LLM may invoke tools; RubyLLM handles the tool call/result loop
7. **Result**: Robot builds and returns a `RobotResult`
8. **Network**: If in a network, result flows to dependent tasks via SimpleFlow

## Key Patterns

### Factory Methods

Robots and networks are created via factory methods on the `RobotLab` module:

```ruby
robot = RobotLab.build(
  name: "assistant",
  template: :assistant,
  context: { tone: "friendly" }
)

network = RobotLab.create_network(name: "pipeline") do
  task :analyst, analyst_robot, depends_on: :none
  task :writer, writer_robot, depends_on: [:analyst]
end
```

### Fluent Chaining

`with_*` methods on Robot delegate to the underlying `@chat` and return `self`:

```ruby
robot = RobotLab.build(name: "bot")
  .with_instructions("Be concise.")
  .with_temperature(0.3)
  .with_model("gpt-4o")
```

### Hierarchical Configuration

Tools and MCP servers use hierarchical resolution: `runtime > robot build > network > global config`. Values can be `:none`, `:inherit`, or explicit arrays.

### SimpleFlow Pipeline

Networks are thin wrappers around `SimpleFlow::Pipeline`. Each robot is wrapped in a `Task` that implements the `call(result)` interface. Tasks define dependencies (`:none`, `[:task_names]`, or `:optional`) to control execution order.

## Next Steps

- [Core Concepts](core-concepts.md) - Deep dive into robots and tools
- [Robot Execution](robot-execution.md) - How robots process messages
- [Network Orchestration](network-orchestration.md) - Multi-robot workflows
- [Memory Management](state-management.md) - Managing memory and reactive features
- [Message Flow](message-flow.md) - How messages move through the system
