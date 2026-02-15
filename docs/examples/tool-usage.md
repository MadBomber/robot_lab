# Tool Usage

Robots with external capabilities through tools.

## Overview

This example demonstrates how to give robots access to external systems through tools. Tools are defined as `RubyLLM::Tool` subclasses or `RobotLab::Tool` instances and passed to robots via the `local_tools:` parameter.

## RubyLLM::Tool Subclass Pattern

The primary way to define tools is by subclassing `RubyLLM::Tool`:

```ruby
#!/usr/bin/env ruby
# examples/tool_usage.rb

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

# Run the robot
result = robot.run("What is 15 multiplied by 7? Also, give me a career fortune.")

# Display results
puts "Response: #{result.last_text_content}"

if result.tool_calls.any?
  puts "\nTool calls made:"
  result.tool_calls.each do |tc|
    tool_info = tc.respond_to?(:tool) ? tc.tool : tc
    puts "  #{tool_info[:name] || tool_info}"
  end
end
```

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

result = robot.run("What time is it and what's the weather in New York?")
puts result.last_text_content
```

## Weather API Integration

```ruby
#!/usr/bin/env ruby
# examples/weather_assistant.rb

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

  result = weather_bot.run(input)
  puts "\nAssistant: #{result.last_text_content}"
end

puts "\nGoodbye!"
```

## Database Integration

```ruby
# examples/order_assistant.rb

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
result = order_bot.run("What's the status of order ORD001?")
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
  on_tool_result: ->(tool_call, result) {
    puts "[Tool Result] #{tool_call.name}: #{result}"
  }
)

result = robot.run("What is 42 * 17?")
```

## Running

```bash
export ANTHROPIC_API_KEY="your-key"

# Tool usage example
ruby examples/tool_usage.rb

# Weather assistant
ruby examples/weather_assistant.rb

# Order lookup
ruby examples/order_assistant.rb
```

## Key Concepts

1. **RubyLLM::Tool subclass**: Define a class with `description`, `param`, and `execute` method
2. **RobotLab::Tool subclass**: Same DSL plus `robot` accessor for robot-aware tools
3. **RobotLab::Tool.create**: Use `RobotLab::Tool.create(name:, description:, &block)` for dynamic tools
4. **local_tools**: Pass tool classes/instances via `local_tools:` parameter to `RobotLab.build` or `Robot.new`
4. **Error Handling**: Return error hashes (e.g., `{ error: "message" }`) for graceful failures
5. **Callbacks**: Use `on_tool_call:` and `on_tool_result:` for monitoring
6. **Result Access**: Check `result.tool_calls` for tool call history, `result.last_text_content` for the final response

## See Also

- [Using Tools Guide](../guides/using-tools.md)
- [Tool API](../api/core/tool.md)
- [Robot API](../api/core/robot.md)
