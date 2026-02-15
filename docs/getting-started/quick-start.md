# Quick Start

Build your first RobotLab application in 5 minutes.

## Step 1: Set Up API Keys

RobotLab reads configuration from environment variables automatically. Set your API key before running any code:

```bash
export ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY="sk-ant-..."
```

Or create a config file at `./config/robot_lab.yml`:

```yaml
defaults:
  ruby_llm:
    anthropic_api_key: <%= ENV['ANTHROPIC_API_KEY'] %>
```

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

result = assistant.run("What time is it right now?")
puts result.last_text_content
```

Tools are passed to the robot via the `local_tools:` keyword argument as an array of `RubyLLM::Tool` subclasses.

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

Available chaining methods include `with_instructions`, `with_temperature`, `with_model`, `with_max_tokens`, `with_top_p`, `with_tools`, and more.

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

# Access intermediate results by task name
if result.context[:analyst]
  puts "\nAnalysis: #{result.context[:analyst].last_text_content}"
end
```

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
