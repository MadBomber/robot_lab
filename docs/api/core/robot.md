# Robot

LLM-powered agent with template-based prompts, tools, memory, and MCP integration.

## Class Hierarchy

```
RubyLLM::Agent
  └── RobotLab::Robot
        └── Your custom subclasses (e.g., ClassifierRobot)
```

`Robot` inherits from `RubyLLM::Agent`, which creates a persistent `@chat` on initialization. The robot adds template-based prompts, shared memory, hierarchical MCP configuration, and SimpleFlow pipeline integration on top of the base agent.

## Constructor

```ruby
Robot.new(
  name:,
  template: nil,
  system_prompt: nil,
  context: {},
  description: nil,
  local_tools: [],
  model: nil,
  mcp_servers: [],
  mcp: :none,
  tools: :none,
  on_tool_call: nil,
  on_tool_result: nil,
  enable_cache: true,
  temperature: nil,
  top_p: nil,
  top_k: nil,
  max_tokens: nil,
  presence_penalty: nil,
  frequency_penalty: nil,
  stop: nil
)
```

### Parameters

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `String` | **required** | Unique identifier for the robot |
| `template` | `Symbol`, `nil` | `nil` | Prompt template (e.g., `:assistant` loads `prompts/assistant.md`) |
| `system_prompt` | `String`, `nil` | `nil` | Inline system prompt (appended after template if both given) |
| `context` | `Hash`, `Proc` | `{}` | Variables passed to the template |
| `description` | `String`, `nil` | `nil` | Human-readable description of what the robot does |
| `local_tools` | `Array` | `[]` | Tools defined locally (`RubyLLM::Tool` subclasses or `RobotLab::Tool` instances) |
| `model` | `String`, `nil` | `nil` | LLM model ID (falls back to `RobotLab.config.ruby_llm.model`) |
| `mcp_servers` | `Array` | `[]` | Legacy MCP server configurations |
| `mcp` | `Symbol`, `Array` | `:none` | Hierarchical MCP config (`:none`, `:inherit`, or server array) |
| `tools` | `Symbol`, `Array` | `:none` | Hierarchical tools config (`:none`, `:inherit`, or tool name array) |
| `on_tool_call` | `Proc`, `nil` | `nil` | Callback invoked when a tool is called |
| `on_tool_result` | `Proc`, `nil` | `nil` | Callback invoked when a tool returns a result |
| `enable_cache` | `Boolean` | `true` | Whether to enable semantic caching |
| `temperature` | `Float`, `nil` | `nil` | Controls randomness (0.0-1.0) |
| `top_p` | `Float`, `nil` | `nil` | Nucleus sampling threshold |
| `top_k` | `Integer`, `nil` | `nil` | Top-k sampling |
| `max_tokens` | `Integer`, `nil` | `nil` | Maximum tokens in response |
| `presence_penalty` | `Float`, `nil` | `nil` | Penalize based on presence |
| `frequency_penalty` | `Float`, `nil` | `nil` | Penalize based on frequency |
| `stop` | `String`, `Array`, `nil` | `nil` | Stop sequences |

## Factory Method

```ruby
robot = RobotLab.build(
  name: nil,          # Auto-generates "robot_XXXXXXXX" if nil
  template: nil,
  system_prompt: nil,
  context: {},
  enable_cache: true,
  **options           # All other Robot.new parameters
)
# => RobotLab::Robot
```

If `name` is omitted, a unique name is generated automatically using `SecureRandom.hex(4)`.

## Attributes (Read-Only)

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | `String` | Unique identifier |
| `description` | `String`, `nil` | Human-readable description |
| `template` | `Symbol`, `nil` | Prompt template identifier |
| `system_prompt` | `String`, `nil` | Inline system prompt |
| `local_tools` | `Array` | Locally defined tools |
| `mcp_clients` | `Hash<String, MCP::Client>` | Connected MCP clients, keyed by server name |
| `mcp_tools` | `Array<Tool>` | Tools discovered from MCP servers |
| `memory` | `Memory` | Inherent memory (used when standalone, not in network) |
| `mcp_config` | `Symbol`, `Array` | Build-time MCP configuration (raw, unresolved) |
| `tools_config` | `Symbol`, `Array` | Build-time tools configuration (raw, unresolved) |

## Methods

### run

```ruby
result = robot.run(message, **kwargs)
# => RobotResult
```

Primary execution method. Sends a message to the LLM with memory/MCP/tools resolution and returns a `RobotResult`.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `message` | `String` | **required** | The user message to send |
| `network` | `NetworkRun`, `nil` | `nil` | Network context (passed internally) |
| `network_memory` | `Memory`, `nil` | `nil` | Shared network memory |
| `memory` | `Memory`, `Hash`, `nil` | `nil` | Runtime memory to merge |
| `mcp` | `Symbol`, `Array` | `:none` | Runtime MCP override |
| `tools` | `Symbol`, `Array` | `:none` | Runtime tools override |
| `**kwargs` | `Hash` | `{}` | Additional keyword arguments passed to `Agent#ask` |

**Returns:** `RobotResult`

**Examples:**

```ruby
# Simple message
result = robot.run("What is 2+2?")

# With runtime memory
result = robot.run("Summarize the data", memory: { data: report })

# With streaming block
result = robot.run("Tell me a story") { |event| print event.text }

# With runtime overrides
result = robot.run("Help me", mcp: :none, tools: :none)
```

### model

```ruby
robot.model  # => "claude-sonnet-4" or nil
```

Returns the model ID string. Resolves through the underlying chat object.

### update

```ruby
robot.update(
  template: nil,
  context: nil,
  system_prompt: nil,
  model: nil,
  temperature: nil,
  **kwargs
)
# => self
```

Reconfigure the robot after construction. Returns `self` for chaining.

### with_* Methods (Chaining)

All `with_*` methods delegate to the persistent `@chat` and return `self` for chaining:

| Method | Description |
|--------|-------------|
| `with_model(model_id)` | Change the LLM model |
| `with_temperature(temp)` | Set temperature |
| `with_top_p(value)` | Set nucleus sampling |
| `with_top_k(value)` | Set top-k sampling |
| `with_max_tokens(value)` | Set max response tokens |
| `with_presence_penalty(value)` | Set presence penalty |
| `with_frequency_penalty(value)` | Set frequency penalty |
| `with_stop(sequences)` | Set stop sequences |
| `with_instructions(prompt)` | Set system instructions |
| `with_tool(tool)` | Add a single tool |
| `with_tools(*tools)` | Add multiple tools |
| `with_params(**params)` | Set additional parameters |
| `with_headers(**headers)` | Set custom headers |
| `with_schema(schema)` | Set output schema |
| `with_context(**ctx)` | Set context |
| `with_thinking(opts)` | Enable extended thinking |

**Example:**

```ruby
robot = RobotLab.build(name: "bot")
robot
  .with_model("claude-sonnet-4")
  .with_temperature(0.7)
  .with_instructions("Be concise.")
  .run("Hello")
```

### with_template

```ruby
robot.with_template(:assistant, tone: "friendly")
# => self
```

Apply a prompt_manager template. Separate from the delegated `with_*` methods because it handles template parsing and front matter config.

### call

```ruby
robot.call(result)
# => SimpleFlow::Result
```

SimpleFlow step interface. Extracts the message from `result.context[:run_params]`, calls `run`, and wraps the output in a continued `SimpleFlow::Result`.

Override this method in subclasses for custom routing logic (e.g., classifiers).

### reset_memory

```ruby
robot.reset_memory
# => self
```

Reset the robot's inherent memory to its initial state.

### disconnect

```ruby
robot.disconnect
# => self
```

Disconnect from all MCP servers.

### to_h

```ruby
robot.to_h
# => Hash
```

Returns a hash representation of the robot including name, description, template, system_prompt, local_tools, mcp_tools, mcp_config, tools_config, mcp_servers, and model.

## Memory Behavior

- **Standalone**: Robot uses its own inherent `Memory` instance (`robot.memory`).
- **In a Network**: Robot uses the network's shared memory (passed via `network_memory:`).

```ruby
# Standalone memory access
robot.memory[:user_id] = 123
robot.memory[:user_id]  # => 123

# Reset standalone memory
robot.reset_memory
```

## Templates

Templates are `.md` files with optional YAML front matter, loaded via `prompt_manager`. The `template:` parameter maps to a file path relative to the configured template directory:

```ruby
# template: :assistant  =>  prompts/assistant.md
robot = RobotLab.build(name: "bot", template: :assistant, context: { tone: "friendly" })
```

Front matter can configure chat options (`model`, `temperature`, `top_p`, `top_k`, `max_tokens`, `presence_penalty`, `frequency_penalty`, `stop`), which are automatically applied to the underlying chat.

## Configuration Hierarchy

Tools and MCP servers use hierarchical resolution: **runtime > robot > network > global config**.

```
RobotLab.config (global)
  |
  +-- Network
  |     |
  |     +-- Robot (build-time mcp:, tools:)
  |           |
  |           +-- run() call (runtime mcp:, tools:)
```

Values at each level:

- `:none` -- no tools/MCP at this level
- `:inherit` -- inherit from parent level
- `Array` -- explicit list of tool names or MCP server configs

## Examples

### Basic Robot

```ruby
robot = RobotLab.build(
  name: "greeter",
  system_prompt: "You greet users warmly."
)
result = robot.run("Hello!")
puts result.last_text_content
```

### Robot with Template

```ruby
robot = RobotLab.build(
  name: "support",
  template: :support,
  context: { company: "Acme Corp" }
)
result = robot.run("I need help with my order")
```

### Robot with Tools

```ruby
class Calculator < RubyLLM::Tool
  description "Performs basic arithmetic"
  param :operation, type: "string", desc: "add, subtract, multiply, divide"
  param :a, type: "number", desc: "First operand"
  param :b, type: "number", desc: "Second operand"

  def execute(operation:, a:, b:)
    case operation
    when "add" then a + b
    when "subtract" then a - b
    when "multiply" then a * b
    when "divide" then a.to_f / b
    end
  end
end

robot = RobotLab.build(
  name: "math_bot",
  system_prompt: "You help with math.",
  local_tools: [Calculator]
)
result = robot.run("What is 15 * 7?")
```

### Robot with MCP

```ruby
robot = RobotLab.build(
  name: "developer",
  system_prompt: "You help with coding tasks.",
  mcp: [
    {
      name: "github",
      transport: { type: "stdio", command: "github-mcp-server", args: ["stdio"] }
    }
  ]
)
result = robot.run("Search for popular Ruby repos")
robot.disconnect
```

### Bare Robot with Chaining

```ruby
robot = RobotLab.build(name: "bot")
result = robot
  .with_instructions("Be concise.")
  .with_temperature(0.3)
  .run("Explain quantum computing")
```

## See Also

- [Building Robots Guide](../../guides/building-robots.md)
- [Tool](tool.md)
- [Network](network.md)
