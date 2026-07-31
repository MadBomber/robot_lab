# Tool Usage

Robots with external capabilities through tools.

## Overview

This example demonstrates how to give robots access to external systems through tools. Tools are defined as `RubyLLM::Tool` subclasses or `RobotLab::Tool` instances and passed to robots via the `local_tools:` parameter.

> [!WARNING]
> **Attaching a tool is not the same as sending it.** `Robot#run` defaults to
> `tools: :none`, so a plain `robot.run("...")` sends the LLM zero tools even when
> `local_tools:` were supplied at build time. Pass `tools: :inherit` on every call
> that should be able to use them:
>
> ```ruby
> robot.run("What is 15 * 7?", tools: :inherit)
> ```
>
> For a **standalone** robot, do not pass `tools: :inherit` in the constructor:
> at build time it resolves against the parent level (`:none`) and yields an
> allowlist matching nothing, suppressing the tools even when the run asks for
> them. Leave `tools:` unset there.
>
> Inside a **network**, the opposite holds — build-time `tools: :inherit` is how a
> robot opts into the network `config:`'s allowlist. See
> [Creating Networks](../guides/creating-networks.md).
>
> An explicit array (`tools: [Calculator]`) is an allowlist, not a local-vs-MCP
> switch, and its entries must match how each tool was attached — this page
> attaches classes, so use class names.

## RubyLLM::Tool Subclass Pattern

The primary way to define tools is by subclassing `RubyLLM::Tool`:

```ruby
#!/usr/bin/env ruby
# Tool definitions mirror examples/02_tools.rb

require "bundler/setup"
require "robot_lab"

# Define tools as RubyLLM::Tool subclasses
class Calculator < RubyLLM::Tool
  description "Performs basic arithmetic operations"

  param :operation,
        type: "string",
        desc: "The operation to perform (add, subtract, multiply, divide)"

  param :a,
        type: "number",
        desc: "First operand"

  param :b,
        type: "number",
        desc: "Second operand"

  def execute(operation:, a:, b:)
    case operation
    when "add" then a + b
    when "subtract" then a - b
    when "multiply" then a * b
    when "divide" then a.to_f / b
    else "Unknown operation: #{operation}"
    end
  end
end

class FortuneCookie < RubyLLM::Tool
  description "Get a fortune cookie message with wisdom and lucky numbers"

  param :category,
        type: "string",
        desc: "The category of fortune (wisdom, love, career, adventure)"

  FORTUNES = {
    "wisdom" => [
      "The obstacle in the path becomes the path.",
      "A journey of a thousand miles begins with a single step."
    ],
    "career" => [
      "Opportunity dances with those already on the dance floor.",
      "Your work is your signature. Sign it with excellence."
    ]
  }.freeze

  def execute(category:)
    {
      category: category,
      fortune: FORTUNES.fetch(category, FORTUNES["wisdom"]).sample,
      lucky_numbers: Array.new(6) { rand(1..49) }.sort
    }
  end
end

# Create robot with tools via local_tools
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You help with math and dispense fortune cookies.",
  local_tools: [Calculator, FortuneCookie],
  model: "claude-sonnet-4"
)

# Run the robot -- tools: :inherit is what actually sends Calculator and
# FortuneCookie to the LLM
result = robot.run(
  "What is 15 multiplied by 7? Also, give me a career fortune.",
  tools: :inherit
)

# Display results
puts "Response: #{result.last_text_content}"

# Confirm which tools were sent for this turn
puts "Tools sent: #{robot.chat.tools.keys.join(', ')}"
```

> [!NOTE]
> `result.tool_calls` is effectively always empty. It reads the *final* assistant
> message, and by the time ruby_llm's tool loop has finished that message contains
> only text. To observe tool activity, use the `on_tool_call:` callback (below) or
> the `:tool_call` hooks.

## RobotLab::Tool.create Pattern

For simpler tools that do not need their own class, use `RobotLab::Tool.create`:

```ruby
require "robot_lab"

# Define an inline tool
get_time = RobotLab::Tool.create(
  name: "get_time",
  description: "Get the current time"
) { |_args| Time.now.to_s }

# Define a tool with parameters (JSON Schema)
weather_tool = RobotLab::Tool.create(
  name: "get_weather",
  description: "Get weather for a city",
  parameters: {
    type: "object",
    properties: {
      city: { type: "string", description: "City name" }
    },
    required: ["city"]
  }
) { |args| { city: args[:city], temperature: "72F", condition: "sunny" } }

robot = RobotLab.build(
  name: "weather_bot",
  system_prompt: "You provide weather and time information.",
  local_tools: [get_time, weather_tool],
  model: "claude-sonnet-4"
)

result = robot.run("What time is it and what's the weather in New York?", tools: :inherit)
puts result.last_text_content
```

The block receives a single hash of symbol-keyed arguments.

> [!NOTE]
> `RobotLab::Tool.create(parameters:)` accepts a JSON-Schema-shaped hash, but only
> `type` and `description` are read off each property, plus the top-level `required`
> list. Anything else (`enum`, `default`, nested `items`) is ignored — ruby_llm's
> `param` DSL supports only `type:`, `desc:`/`description:`, and `required:`.

## Weather API Integration

```ruby
#!/usr/bin/env ruby

require "bundler/setup"
require "robot_lab"
require "http"
require "json"

class GetWeather < RubyLLM::Tool
  description "Get current weather for a city"

  param :city,
        type: "string",
        desc: "City name (e.g., 'New York', 'London')"

  def execute(city:)
    response = HTTP.get(
      "https://wttr.in/#{URI.encode_www_form_component(city)}?format=j1"
    )

    if response.status.success?
      data = JSON.parse(response.body)
      current = data["current_condition"].first

      {
        city: city,
        temperature_f: current["temp_F"],
        temperature_c: current["temp_C"],
        condition: current["weatherDesc"].first["value"],
        humidity: current["humidity"],
        wind_mph: current["windspeedMiles"]
      }
    else
      { error: "Could not fetch weather for #{city}" }
    end
  rescue HTTP::Error => e
    { error: "Network error: #{e.message}" }
  end
end

class GetForecast < RubyLLM::Tool
  description "Get weather forecast for upcoming days"

  param :city, type: "string", desc: "City name"
  param :days, type: "integer", desc: "Number of days (default 3)"

  def execute(city:, days: 3)
    response = HTTP.get(
      "https://wttr.in/#{URI.encode_www_form_component(city)}?format=j1"
    )

    if response.status.success?
      data = JSON.parse(response.body)
      data["weather"].take(days).map do |day|
        {
          date: day["date"],
          high_f: day["maxtempF"],
          low_f: day["mintempF"],
          condition: day["hourly"].first["weatherDesc"].first["value"]
        }
      end
    else
      { error: "Could not fetch forecast" }
    end
  rescue HTTP::Error => e
    { error: "Network error: #{e.message}" }
  end
end

# Create weather assistant
weather_bot = RobotLab.build(
  name: "weather_assistant",
  description: "Provides weather information",
  system_prompt: <<~PROMPT,
    You are a helpful weather assistant. Use your tools to look up weather.
    Always provide temperatures in both Fahrenheit and Celsius.
    Include relevant advice based on conditions (umbrella, sunscreen, etc).
  PROMPT
  local_tools: [GetWeather, GetForecast],
  model: "claude-sonnet-4"
)

# Interactive session
puts "Weather Assistant (type 'quit' to exit)"
puts "-" * 50

loop do
  print "\nYou: "
  input = gets&.chomp

  break if input.nil? || input.downcase == "quit"
  next if input.empty?

  result = weather_bot.run(input, tools: :inherit)
  puts "\nAssistant: #{result.last_text_content}"
end

puts "\nGoodbye!"
```

## Database Integration

```ruby
require "robot_lab"

# Mock database
ORDERS = {
  "ORD001" => { id: "ORD001", status: "shipped", items: ["Widget"], total: 29.99 },
  "ORD002" => { id: "ORD002", status: "processing", items: ["Gadget", "Gizmo"], total: 89.99 }
}

class GetOrder < RubyLLM::Tool
  description "Look up an order by ID"

  param :order_id, type: "string", desc: "The order ID to look up"

  def execute(order_id:)
    order = ORDERS[order_id.upcase]
    order || { error: "Order not found" }
  end
end

class ListOrders < RubyLLM::Tool
  description "List recent orders"

  param :limit, type: "integer", desc: "Maximum number of orders to return"

  def execute(limit: 5)
    ORDERS.values.take(limit)
  end
end

class CancelOrder < RubyLLM::Tool
  description "Cancel an order"

  param :order_id, type: "string", desc: "The order ID to cancel"
  param :reason, type: "string", desc: "Reason for cancellation"

  def execute(order_id:, reason: nil)
    order = ORDERS[order_id.upcase]

    if order.nil?
      { success: false, error: "Order not found" }
    elsif order[:status] == "shipped"
      { success: false, error: "Cannot cancel shipped orders" }
    else
      order[:status] = "cancelled"
      order[:cancel_reason] = reason
      { success: true, message: "Order #{order_id} cancelled" }
    end
  end
end

order_bot = RobotLab.build(
  name: "order_assistant",
  system_prompt: "You help customers check and manage their orders.",
  local_tools: [GetOrder, ListOrders, CancelOrder],
  model: "claude-sonnet-4"
)

# Run with a question
result = order_bot.run("What's the status of order ORD001?", tools: :inherit)
puts result.last_text_content
```

## Tool Call Callbacks

Use `on_tool_call` and `on_tool_result` to monitor tool execution:

```ruby
robot = RobotLab.build(
  name: "monitored_bot",
  system_prompt: "You help with calculations.",
  local_tools: [Calculator],
  model: "claude-sonnet-4",
  on_tool_call: ->(tool_call) {
    puts "[Tool Call] #{tool_call.name}: #{tool_call.arguments}"
  },
  # NOTE: one argument -- the result. There is no tool_call parameter here.
  on_tool_result: ->(result) {
    puts "[Tool Result] #{result}"
  }
)

result = robot.run("What is 42 * 17?", tools: :inherit)
```

> [!WARNING]
> `on_tool_result` receives **exactly one** argument, the tool's return value.
> Writing `->(tool_call, result)` raises
> `ArgumentError: wrong number of arguments (given 1, expected 2)` the first time a
> tool runs.
>
> Both callbacks map onto ruby_llm's legacy hooks and are deprecated as of
> ruby_llm 1.16 — wiring either one emits
> ``` `on_tool_call` is deprecated and will be removed in RubyLLM 2.0. Use `before_tool_call` instead. ```
> The additive replacements are `before_message`, `after_message`,
> `before_tool_call`, and `after_tool_result`. RobotLab's own
> [Hook system](../guides/hooks.md) is the supported way to observe tool activity.

## Running

```bash
export ANTHROPIC_API_KEY="your-key"

# Tool definitions and a robot that uses them
ruby examples/02_tools.rb

# Tool loop circuit breaker (max_tool_rounds)
ruby examples/20_circuit_breaker.rb

# Ractor-safe CPU tools (no LLM calls)
ruby examples/29_ractor_tools.rb
```

## Interactive User Input

Use the built-in `RobotLab::AskUser` tool to let robots ask the user questions during execution:

```ruby
require "robot_lab"

robot = RobotLab.build(
  name: "interviewer",
  system_prompt: <<~PROMPT,
    You are a project setup assistant. Interview the user to understand their
    needs, then summarize the project plan. Use the robot_lab--ask_user tool to
    gather information one question at a time.
  PROMPT
  model: "claude-sonnet-4"
)

# Attach an INSTANCE bound to the robot so the tool uses robot.input/robot.output
robot.local_tools << RobotLab::AskUser.new(robot: robot)

result = robot.run("Help me plan a new web application", tools: :inherit)
puts "\nProject Plan:\n#{result.last_text_content}"
```

> [!WARNING]
> Pass an **instance**, not the class. `RobotLab::Tool` derives its LLM-visible
> name from the full class name, so `RobotLab::AskUser` is presented to the model
> as **`robot_lab--ask_user`**, not `ask_user` — name it that way in your system
> prompt.
>
> An instance created without `robot:` has `tool.robot == nil`, so it ignores
> `robot.input` / `robot.output`, falls back to `$stdin` / `$stdout`, and labels
> every prompt `[Robot]` instead of the robot's name. Always use
> `RobotLab::AskUser.new(robot: robot)`.

The robot will ask questions interactively:

```
[interviewer] What programming language would you like to use?
  1. Ruby
  2. Python
  3. TypeScript
> 1

[interviewer] Will you need a database?
> [yes]

[interviewer] What's the main purpose of the application?
> Customer support portal
```

For testing, inject `StringIO` objects on the robot *before* building the tool
instance (the tool reads them through its `robot` reference at call time):

```ruby
robot.input  = StringIO.new("Ruby\nyes\nCustomer portal\n")
robot.output = StringIO.new
```

`RobotLab::AskUser` can also be driven directly, outside an LLM turn — see
[`examples/06_prompt_templates.rb`](https://github.com/MadBomber/robot_lab/blob/main/examples/06_prompt_templates.rb),
which calls `RobotLab::AskUser.new.call("question" => ..., "default" => ...)` to
collect a value before any robot is built.

## Key Concepts

1. **RubyLLM::Tool subclass**: Define a class with `description`, `param`, and `execute` method
2. **RobotLab::Tool subclass**: Same DSL plus a `robot` accessor for robot-aware tools
3. **RobotLab::Tool.create**: Use `RobotLab::Tool.create(name:, description:, &block)` for dynamic tools
4. **Built-in tools**: `RobotLab::AskUser` (LLM-visible name `robot_lab--ask_user`) for interactive terminal input
5. **local_tools**: Pass tool classes/instances via `local_tools:` to `RobotLab.build` or `Robot.new` — this *attaches* them
6. **tools: :inherit**: Required on `run` to actually *send* the attached tools; the default is `tools: :none`
7. **Frontmatter tools**: Declare tool class names in template YAML front matter (`tools: [Calculator]`); they populate `local_tools`, and still need `tools: :inherit` at run time. Constructor `local_tools:` overrides the front-matter list
8. **Error Handling**: Raised exceptions are caught and returned to the LLM as text (`"Error (tool_name): message"`); a `RobotLab::ToolError` with `retryable: true` appends `" (retryable)"`. Set `self.raise_on_error = true` on a class to opt out — note this is per-class and is *not* inherited by subclasses
9. **Tool cap**: At most `DEFAULT_MAX_TOOLS` (128) tools are sent. Setting `max_tools` to nil, 0, or a negative number falls back to 128 — the cap cannot be disabled
10. **Result Access**: Use `result.last_text_content` (alias `result.reply`) for the final response. `result.tool_calls` is effectively always empty — observe tool activity with `on_tool_call:` or the Hook system instead

## See Also

- [Using Tools Guide](../guides/using-tools.md)
- [Tool API](../api/core/tool.md)
- [Robot API](../api/core/robot.md)
