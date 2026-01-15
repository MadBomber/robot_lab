# Tool Usage

Robots with external API integration.

## Overview

This example demonstrates how to give robots access to external systems through tools, including API calls, database queries, and calculations.

## Complete Example

```ruby
#!/usr/bin/env ruby
# examples/weather_assistant.rb

require "bundler/setup"
require "robot_lab"
require "http"
require "json"

RobotLab.configure do |config|
  config.default_model = "claude-sonnet-4"
end

# Weather assistant with API integration
weather_bot = RobotLab.build do
  name "weather_assistant"
  description "Provides weather information"

  template <<~PROMPT
    You are a helpful weather assistant. You can look up current weather
    conditions for any city. When users ask about weather, use the
    get_weather tool to fetch real data.

    Always provide temperatures in both Fahrenheit and Celsius.
    Include relevant advice based on conditions (umbrella, sunscreen, etc).
  PROMPT

  tool :get_weather do
    description "Get current weather for a city"

    parameter :city, type: :string, required: true,
              description: "City name (e.g., 'New York', 'London')"

    handler do |city:, **_|
      # Using wttr.in API (free, no key required)
      response = HTTP.get("https://wttr.in/#{URI.encode_www_form_component(city)}?format=j1")

      if response.status.success?
        data = JSON.parse(response.body)
        current = data["current_condition"].first

        {
          city: city,
          temperature_f: current["temp_F"],
          temperature_c: current["temp_C"],
          condition: current["weatherDesc"].first["value"],
          humidity: current["humidity"],
          wind_mph: current["windspeedMiles"],
          feels_like_f: current["FeelsLikeF"],
          uv_index: current["uvIndex"]
        }
      else
        { error: "Could not fetch weather for #{city}" }
      end
    rescue HTTP::Error => e
      { error: "Network error: #{e.message}" }
    end
  end

  tool :get_forecast do
    description "Get weather forecast for upcoming days"

    parameter :city, type: :string, required: true
    parameter :days, type: :integer, default: 3

    handler do |city:, days: 3, **_|
      response = HTTP.get("https://wttr.in/#{URI.encode_www_form_component(city)}?format=j1")

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
end

# Run interactive session
puts "Weather Assistant (type 'quit' to exit)"
puts "-" * 50

loop do
  print "\nYou: "
  input = gets&.chomp

  break if input.nil? || input.downcase == "quit"
  next if input.empty?

  state = RobotLab.create_state(message: input)

  print "\nAssistant: "
  weather_bot.run(state: state) do |event|
    case event.type
    when :text_delta
      print event.text
    when :tool_call
      puts "\n[Checking weather for #{event.input[:city]}...]"
    end
  end
  puts
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

order_bot = RobotLab.build do
  name "order_assistant"
  template "You help customers check their orders."

  tool :get_order do
    description "Look up an order by ID"
    parameter :order_id, type: :string, required: true

    handler do |order_id:, state:, **_|
      # Verify user owns this order
      user_id = state.data[:user_id]
      order = ORDERS[order_id.upcase]

      if order
        order
      else
        { error: "Order not found" }
      end
    end
  end

  tool :list_orders do
    description "List user's recent orders"
    parameter :limit, type: :integer, default: 5

    handler do |limit:, state:, **_|
      user_id = state.data[:user_id]
      # Filter by user in real implementation
      ORDERS.values.take(limit)
    end
  end

  tool :cancel_order do
    description "Cancel an order"
    parameter :order_id, type: :string, required: true
    parameter :reason, type: :string

    handler do |order_id:, reason: nil, state:, **_|
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
end

# Run with user context
state = RobotLab.create_state(
  message: "What's the status of order ORD001?",
  data: { user_id: "user_123" }
)

result = order_bot.run(state: state)
puts result.output.first.content
```

## Calculator Tool

```ruby
# examples/math_assistant.rb

require "robot_lab"
require "dentaku"

calculator = Dentaku::Calculator.new

math_bot = RobotLab.build do
  name "math_assistant"
  template "You help with mathematical calculations."

  tool :calculate do
    description "Evaluate a mathematical expression"
    parameter :expression, type: :string, required: true,
              description: "Math expression like '2 + 2' or 'sqrt(16)'"

    handler do |expression:, **_|
      result = calculator.evaluate(expression)
      { expression: expression, result: result }
    rescue => e
      { error: "Invalid expression: #{e.message}" }
    end
  end

  tool :solve_equation do
    description "Solve for a variable"
    parameter :equation, type: :string, required: true
    parameter :variable, type: :string, required: true

    handler do |equation:, variable:, **_|
      result = calculator.solve(equation, variable.to_sym)
      { equation: equation, variable: variable, solutions: result }
    rescue => e
      { error: "Could not solve: #{e.message}" }
    end
  end
end
```

## Multi-Tool Example

```ruby
# examples/research_assistant.rb

research_bot = RobotLab.build do
  name "research_assistant"
  template "You help with research tasks."

  tool :web_search do
    description "Search the web"
    parameter :query, type: :string, required: true
    handler { |query:, **_| SearchAPI.search(query) }
  end

  tool :read_url do
    description "Read content from a URL"
    parameter :url, type: :string, required: true
    handler { |url:, **_| HTTP.get(url).body.to_s }
  end

  tool :summarize do
    description "Summarize text"
    parameter :text, type: :string, required: true
    parameter :length, type: :string, enum: %w[short medium long], default: "medium"
    handler { |text:, length:, **_| Summarizer.summarize(text, length) }
  end

  tool :save_note do
    description "Save a research note"
    parameter :title, type: :string, required: true
    parameter :content, type: :string, required: true
    handler do |title:, content:, state:, **_|
      notes = state.memory.recall("notes") || []
      notes << { title: title, content: content, created: Time.now }
      state.memory.remember("notes", notes)
      { saved: true, total_notes: notes.size }
    end
  end
end
```

## Running

```bash
export ANTHROPIC_API_KEY="your-key"

# Weather assistant
ruby examples/weather_assistant.rb

# Order lookup
ruby examples/order_assistant.rb
```

## Key Concepts

1. **Tool Definition**: Use the `tool` DSL with description and parameters
2. **Handler**: Receives parameters plus state, robot, network context
3. **Error Handling**: Return error hashes for graceful failures
4. **State Access**: Tools can read/write state and memory

## See Also

- [Using Tools Guide](../guides/using-tools.md)
- [Tool API](../api/core/tool.md)
- [Memory Guide](../guides/memory.md)
