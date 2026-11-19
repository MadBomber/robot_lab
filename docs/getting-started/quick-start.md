# Quick Start

Build your first RobotLab application in 5 minutes.

## Step 1: Set Up API Keys

RobotLab reads configuration from environment variables automatically. Set your API key before running any code:

```bash
export ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY="sk-ant-..."
```

Or create a config file at `./config/robot_lab.yml`:

```yaml
ruby_llm:
  anthropic_api_key: <%= ENV['ANTHROPIC_API_KEY'] %>
```

> [!IMPORTANT]
> Config files are **flat** — put the keys at the top level. Wrapping them in a
> `defaults:` key (as the gem's own bundled `defaults.yml` does) makes the whole
> file silently ignored.

See [Configuration](configuration.md) for all configuration options.

## Step 2: Create a Robot

Build a simple assistant robot using keyword arguments:

```ruby
require "robot_lab"

assistant = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful AI assistant. You provide clear, accurate, and concise answers."
)
```

## Step 3: Run It

Send a message and get a response:

```ruby
result = assistant.run("What is Ruby on Rails?")

puts result.last_text_content
```

The `run` method takes a positional string message and returns a `RobotResult`. Use `last_text_content` to extract the response text.

## Complete Example

Here is everything together in one file:

```ruby title="hello_robot.rb"
require "robot_lab"

# Build a robot with an inline system prompt
assistant = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful AI assistant. Be concise and friendly."
)

# Run the robot with a message
result = assistant.run("Hello! What can you help me with?")

# Print the response
puts result.last_text_content
```

Run it:

```bash
ruby hello_robot.rb
```

## Using Templates

Instead of inline prompts, you can use template files managed by `prompt_manager`. Templates are `.md` files with YAML front matter:

```markdown title="prompts/helper.md"
---
description: A helpful assistant
parameters:
  company_name: null
---
You are a helpful assistant for <%= company_name %>.
Be concise and friendly in your responses.
```

Create the robot with a template reference and context:

```ruby
robot = RobotLab.build(
  name: "helper",
  template: :helper,
  context: { company_name: "Acme Corp" }
)

result = robot.run("What services do you offer?")
puts result.last_text_content
```

Templates are loaded from the `prompts/` directory by default (or `app/prompts/` in Rails). You can change this in your config.

## Adding a Tool

Give your robot custom capabilities by defining a `RubyLLM::Tool` subclass:

```ruby title="hello_tools.rb"
require "robot_lab"

class CurrentTime < RubyLLM::Tool
  description "Get the current date and time"

  param :timezone,
        type: "string",
        desc: "Timezone name (e.g., 'UTC', 'US/Eastern')",
        required: false

  def execute(timezone: "UTC")
    Time.now.getlocal(timezone_offset(timezone)).strftime("%Y-%m-%d %H:%M:%S %Z")
  rescue => e
    Time.now.utc.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  private

  def timezone_offset(tz)
    case tz
    when "UTC" then "+00:00"
    when "US/Eastern" then "-05:00"
    when "US/Pacific" then "-08:00"
    else "+00:00"
    end
  end
end

# Pass tools via the local_tools: parameter
assistant = RobotLab.build(
  name: "time_bot",
  system_prompt: "You are a helpful assistant. Use the current_time tool when users ask about the time.",
  local_tools: [CurrentTime]
)

# tools: :inherit is REQUIRED -- run() sends no tools without it
result = assistant.run("What time is it right now?", tools: :inherit)
puts result.last_text_content
```

Tools are passed to the robot via the `local_tools:` keyword argument as an array of `RubyLLM::Tool` subclasses.

> [!WARNING]
> **Attaching a tool is not the same as sending it.** `Robot#run` defaults to
> `tools: :none`, which means "send zero tools this turn". Without
> `tools: :inherit` on the run, the example above builds fine, calls the LLM
> fine, and the model simply never sees `CurrentTime` — it will guess or say it
> cannot check the time. The same applies to MCP: pass
> `mcp: :inherit, tools: :inherit` to connect MCP servers and expose their tools.
>
> Do **not** try to fix this by passing `tools: :inherit` to `RobotLab.build` for
> a standalone robot like this one — at build time it resolves against the global
> `:none` and yields an allowlist matching nothing, suppressing the tools even
> when the run asks for them. Put it on the `run` call.
>
> (The one place build-time `:inherit` *is* correct is a robot in a network, where
> it opts into the network `config:`'s list — see
> [Creating Networks](../guides/creating-networks.md).)

## Method Chaining

Robots support a chaining API for runtime adjustments:

```ruby
robot = RobotLab.build(name: "writer")

result = robot
  .with_instructions("You are a creative fiction writer.")
  .with_temperature(0.9)
  .with_model("claude-sonnet-4")
  .run("Write a haiku about programming.")

puts result.last_text_content
```

The complete set of chaining methods is `with_context`, `with_headers`,
`with_instructions`, `with_model`, `with_params`, `with_schema`,
`with_temperature`, `with_thinking`, `with_tool`, `with_tools`, plus RobotLab's
own `with_template` and `with_bus`.

> [!NOTE]
> There is no `with_max_tokens`, `with_top_p`, `with_top_k`, `with_stop`,
> `with_presence_penalty`, or `with_frequency_penalty` — those raise
> `NoMethodError`. Set them as constructor keyword arguments
> (`RobotLab.build(..., max_tokens: 2000)`) or through `with_params`:
>
> ```ruby
> robot.with_params(max_tokens: 2000, top_p: 0.3).run("...")
> ```

## Multi-Robot Network

Create a pipeline of robots using `RobotLab.create_network`. Networks use `SimpleFlow::Pipeline` under the hood with `task` definitions and dependency tracking:

```ruby title="hello_network.rb"
require "robot_lab"

# Build specialized robots
analyst = RobotLab.build(
  name: "analyst",
  system_prompt: <<~PROMPT
    You are a text analyst. Analyze the given text and provide a brief
    summary of its key themes and sentiment. Be concise -- 2-3 sentences max.
  PROMPT
)

writer = RobotLab.build(
  name: "writer",
  system_prompt: <<~PROMPT
    You are a professional copywriter. Based on the analysis you receive,
    write a short, engaging summary suitable for a newsletter. Keep it
    to one paragraph.
  PROMPT
)

# Create a sequential pipeline
network = RobotLab.create_network(name: "content_pipeline") do
  task :analyst, analyst, depends_on: :none
  task :writer, writer, depends_on: [:analyst]
end

# Run the network
result = network.run(
  message: "Ruby 3.4 was released with significant performance improvements..."
)

# The final result is from the last robot in the pipeline
if result.value.is_a?(RobotLab::RobotResult)
  puts result.value.last_text_content
end

# Access intermediate results by ROBOT name (see note below)
if result.context[:analyst]
  puts "\nAnalysis: #{result.context[:analyst].last_text_content}"
end
```

> [!IMPORTANT]
> `result.context` is keyed by the **robot's** `name:`, not by the task name.
> Internally each robot writes `result.with_context(@name.to_sym, robot_result)`.
> The lookup above works only because the robot is named `"analyst"` *and* its
> task is named `:analyst`. If you register a robot under a different task name —
> `task :first_pass, analyst` — the result is still at
> `result.context[:analyst]`, not `result.context[:first_pass]`. Keeping the two
> names identical, as in this example, is the simplest way to avoid the
> surprise.

### Network Task Dependencies

Tasks declare their dependencies to control execution order:

| Dependency | Meaning |
|-----------|---------|
| `depends_on: :none` | Entry point -- runs first with no dependencies |
| `depends_on: [:task_name]` | Runs after the named task(s) complete |
| `depends_on: :optional` | Only runs if explicitly activated by a preceding task |

Tasks with non-overlapping dependencies can execute in parallel automatically.

## What's Next?

You have built your first RobotLab application. Here is where to go next:

<div class="grid cards" markdown>

-   [:octicons-gear-24: **Configuration**](configuration.md)

    Learn all configuration options

-   [:octicons-cpu-24: **Building Robots**](../guides/building-robots.md)

    Deep dive into robot creation

-   [:octicons-tools-24: **Using Tools**](../guides/using-tools.md)

    Give robots custom capabilities

-   [:octicons-git-branch-24: **Creating Networks**](../guides/creating-networks.md)

    Advanced network patterns

</div>
