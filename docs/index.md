# RobotLab

> [!CAUTION]
> This gem is under active development. APIs and features may change without notice. See the [CHANGELOG](https://github.com/MadBomber/robot_lab/blob/main/CHANGELOG.md) for details.

<table>
<tr>
<td width="50%" align="center" valign="top">
<img src="assets/images/robot_lab.jpg" alt="RobotLab"><br>
<em>"Build robots. Solve problems."</em>
</td>
<td width="50%" valign="top">
RobotLab is a Ruby gem that enables you to build sophisticated AI applications using multiple specialized robots (LLM agents) that work together to accomplish complex tasks.<br><br>
Each robot is backed by a persistent LLM chat, configured with keyword arguments, and run with a simple positional message. Robots can be orchestrated through networks with task-based pipelines, share information through a reactive memory system, and connect to external tools via the Model Context Protocol (MCP).
</td>
</tr>
</table>

## Key Features

<div class="grid cards" markdown>

-   :material-robot:{ .lg .middle } **Multi-Robot Architecture**

    ---

    Build applications with multiple specialized Robots (AI agents), each with persistent chat and memory.

    [:octicons-arrow-right-24: Learn more](architecture/core-concepts.md)

-   :material-transit-connection-variant:{ .lg .middle } **Network Orchestration**

    ---

    Connect robots in task-based pipelines using SimpleFlow with sequential, parallel, and conditional execution.

    [:octicons-arrow-right-24: Creating Networks](guides/creating-networks.md)

-   :material-file-document-outline:{ .lg .middle } **Prompt Templates**

    ---

    Self-contained `.md` files with YAML front matter that define a complete robot: prompt, tools, MCP, model, and skills.

    [:octicons-arrow-right-24: Building Robots](guides/building-robots.md)

-   :material-puzzle-outline:{ .lg .middle } **Composable Skills**

    ---

    Mix reusable prompt behaviors into any robot. Skills expand depth-first with automatic cycle detection and config cascading.

    [:octicons-arrow-right-24: Skills Guide](guides/building-robots.md#skills)

-   :material-tools:{ .lg .middle } **Extensible Tools**

    ---

    Give robots custom capabilities via `RobotLab::Tool` subclasses with graceful error handling. Errors are returned to the LLM as plain text.

    [:octicons-arrow-right-24: Using Tools](guides/using-tools.md)

-   :material-account-question:{ .lg .middle } **Human-in-the-Loop**

    ---

    The `AskUser` tool lets robots ask users questions interactively with open-ended text, multiple choice, and default values.

    [:octicons-arrow-right-24: Using Tools](guides/using-tools.md)

-   :material-play-speed:{ .lg .middle } **Content Streaming**

    ---

    Stream LLM responses in real-time via stored `on_content:` callbacks, per-call blocks, or both together.

    [:octicons-arrow-right-24: Streaming Guide](guides/streaming.md)

-   :material-server-network:{ .lg .middle } **MCP Integration**

    ---

    Connect to Model Context Protocol servers to extend robot capabilities with external tools.

    [:octicons-arrow-right-24: MCP Guide](guides/mcp-integration.md)

-   :material-memory:{ .lg .middle } **Reactive Memory**

    ---

    Robots share data through a reactive key-value memory system with subscriptions, blocking reads, and optional Redis backend.

    [:octicons-arrow-right-24: Memory System](guides/memory.md)

-   :material-message-arrow-right-outline:{ .lg .middle } **Message Bus**

    ---

    Bidirectional, cyclic communication between robots via TypedBus for negotiation loops and convergence patterns.

    [:octicons-arrow-right-24: Message Bus](architecture/core-concepts.md#message-bus)

-   :material-creation:{ .lg .middle } **Dynamic Spawning**

    ---

    Robots create new specialist robots at runtime using `spawn`. The bus is created lazily with no upfront wiring required.

    [:octicons-arrow-right-24: Examples](examples/index.md#spawning-robots)

-   :material-layers-outline:{ .lg .middle } **Layered Configuration**

    ---

    Cascading config from YAML files, environment variables, and `RunConfig` objects that flow through the network-robot hierarchy.

    [:octicons-arrow-right-24: Configuration](getting-started/configuration.md)

-   :material-train-car-container:{ .lg .middle } **Rails Integration**

    ---

    Generators, background jobs, and Turbo Stream token broadcasting for real-time streaming to the browser.

    [:octicons-arrow-right-24: Rails Guide](guides/rails-integration.md)

</div>

## Quick Example

```ruby
require "robot_lab"

# Configuration is automatic via environment variables, YAML files, or defaults.
# Set API keys via env vars:
#   ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...
#
# Or place a config file at ~/.config/robot_lab/config.yml
# Access config values: RobotLab.config.ruby_llm.model  #=> "claude-sonnet-4"

# Create a robot with keyword arguments
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful assistant. Answer questions clearly and concisely.",
  model: "claude-sonnet-4"
)

# Run the robot with a positional string argument
result = robot.run("What is the capital of France?")

puts result.last_text_content
# => "The capital of France is Paris."

# Memory persists across runs
robot.run("Remember that my favorite color is blue.")
result = robot.run("What is my favorite color?")
puts result.last_text_content
# => "Your favorite color is blue."

# Chaining configuration
robot.with_instructions("Be extra concise.").with_temperature(0.3).run("Explain Ruby in one sentence.")
```

## Supported LLM Providers

RobotLab supports multiple LLM providers through the [ruby_llm](https://github.com/crmne/ruby_llm) library:

| Provider | Models |
|----------|--------|
| **Anthropic** | Claude Opus 4, Claude Sonnet 4, Claude Haiku 3.5 |
| **OpenAI** | GPT-4o, GPT-4, o1, o3 |
| **Google** | Gemini 2.5 Pro, Gemini 2.5 Flash |
| **DeepSeek** | DeepSeek V3, DeepSeek R1 |
| **AWS Bedrock** | Claude models via AWS Bedrock |
| **Google Vertex AI** | Gemini models via Vertex AI |
| **Ollama** | Local models via Ollama |
| **OpenRouter** | Multi-provider routing |
| **Mistral** | Mistral Large, Mistral Medium |
| **xAI** | Grok models |

## Installation

Add RobotLab to your Gemfile:

```ruby
gem "robot_lab"
```

Or install directly:

```bash
gem install robot_lab
```

[:octicons-arrow-right-24: Full Installation Guide](getting-started/installation.md)

## Next Steps

<div class="grid cards" markdown>

-   [:octicons-rocket-24: **Quick Start**](getting-started/quick-start.md)

    Get up and running in 5 minutes

-   [:octicons-book-24: **Concepts**](concepts.md)

    Understand the core concepts

-   [:octicons-code-24: **Examples**](examples/index.md)

    See RobotLab in action

-   [:octicons-gear-24: **API Reference**](api/index.md)

    Detailed API documentation

</div>

## License

RobotLab is released under the [MIT License](https://opensource.org/licenses/MIT).
