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
Each robot has its own system prompt, tools, and capabilities. Robots can be orchestrated through networks with customizable routing logic, share information through a hierarchical memory system, and connect to external tools via the Model Context Protocol (MCP).
</td>
</tr>
</table>

## Key Features

<div class="grid cards" markdown>

-   :material-robot:{ .lg .middle } **Multi-Robot Architecture**

    ---

    Build applications with multiple specialized AI agents, each with unique capabilities and personalities.

    [:octicons-arrow-right-24: Learn more](architecture/core-concepts.md)

-   :material-transit-connection-variant:{ .lg .middle } **Network Orchestration**

    ---

    Connect robots in networks with flexible routing to handle complex, multi-step workflows.

    [:octicons-arrow-right-24: Creating Networks](guides/creating-networks.md)

-   :material-tools:{ .lg .middle } **Extensible Tools**

    ---

    Give robots custom tools to interact with external systems, databases, and APIs.

    [:octicons-arrow-right-24: Using Tools](guides/using-tools.md)

-   :material-server-network:{ .lg .middle } **MCP Integration**

    ---

    Connect to Model Context Protocol servers to extend robot capabilities with external tools.

    [:octicons-arrow-right-24: MCP Guide](guides/mcp-integration.md)

-   :material-memory:{ .lg .middle } **Shared Memory**

    ---

    Robots can share information through a hierarchical memory system with namespaced scopes.

    [:octicons-arrow-right-24: Memory System](guides/memory.md)

-   :material-history:{ .lg .middle } **Conversation History**

    ---

    Persist and restore conversation threads for long-running interactions.

    [:octicons-arrow-right-24: History Guide](guides/history.md)

</div>

## Quick Example

```ruby
require "robot_lab"

# Configure RobotLab
RobotLab.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.default_model = "claude-sonnet-4"
end

# Create a simple robot
robot = RobotLab.build do
  name "assistant"
  description "A helpful AI assistant"
  template <<~PROMPT
    You are a helpful assistant. Answer questions clearly and concisely.
  PROMPT
end

# Create a network with the robot
network = RobotLab.create_network do
  name "simple_network"
  add_robot robot
end

# Run the network
state = RobotLab.create_state(message: "What is the capital of France?")
result = network.run(state: state)

puts result.last_result.output.first.content
# => "The capital of France is Paris."
```

## Supported LLM Providers

RobotLab supports multiple LLM providers through the [ruby_llm](https://github.com/crmne/ruby_llm) library:

| Provider | Models |
|----------|--------|
| **Anthropic** | Claude 4, Claude Sonnet, Claude Haiku |
| **OpenAI** | GPT-4o, GPT-4, GPT-3.5 Turbo |
| **Google** | Gemini Pro, Gemini Ultra |
| **Azure OpenAI** | All Azure-hosted OpenAI models |
| **Bedrock** | Claude models via AWS Bedrock |
| **Ollama** | Local models via Ollama |

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
