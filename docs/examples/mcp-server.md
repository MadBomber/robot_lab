# MCP Server

Creating and using Model Context Protocol servers.

## Overview

This example demonstrates how to create MCP servers to expose tools and how to connect robots to external MCP servers.

## Creating an MCP Server

```ruby
#!/usr/bin/env ruby
# examples/mcp_server.rb

require "bundler/setup"
require "robot_lab"
require "json"

# Create an MCP server with database tools
server = RobotLab::MCP::Server.new(
  name: "database_tools",
  version: "1.0.0"
)

# Mock database
USERS = {
  "1" => { id: "1", name: "Alice", email: "alice@example.com", plan: "pro" },
  "2" => { id: "2", name: "Bob", email: "bob@example.com", plan: "free" }
}

ORDERS = {
  "ORD001" => { id: "ORD001", user_id: "1", total: 99.99, status: "shipped" },
  "ORD002" => { id: "ORD002", user_id: "1", total: 49.99, status: "pending" },
  "ORD003" => { id: "ORD003", user_id: "2", total: 29.99, status: "delivered" }
}

# Add tools to the server
server.add_tool(
  name: "get_user",
  description: "Get user by ID",
  parameters: {
    user_id: { type: "string", required: true, description: "User ID" }
  },
  handler: ->(user_id:) {
    user = USERS[user_id]
    user || { error: "User not found" }
  }
)

server.add_tool(
  name: "list_users",
  description: "List all users",
  parameters: {
    plan: { type: "string", enum: ["free", "pro"], description: "Filter by plan" }
  },
  handler: ->(plan: nil) {
    users = USERS.values
    users = users.select { |u| u[:plan] == plan } if plan
    users
  }
)

server.add_tool(
  name: "get_orders",
  description: "Get orders for a user",
  parameters: {
    user_id: { type: "string", required: true },
    status: { type: "string", enum: ["pending", "shipped", "delivered"] }
  },
  handler: ->(user_id:, status: nil) {
    orders = ORDERS.values.select { |o| o[:user_id] == user_id }
    orders = orders.select { |o| o[:status] == status } if status
    orders
  }
)

server.add_tool(
  name: "update_order_status",
  description: "Update an order's status",
  parameters: {
    order_id: { type: "string", required: true },
    status: { type: "string", required: true, enum: ["pending", "shipped", "delivered"] }
  },
  handler: ->(order_id:, status:) {
    order = ORDERS[order_id]
    return { error: "Order not found" } unless order
    order[:status] = status
    { success: true, order: order }
  }
)

# Start the server (stdio for local use)
puts "Starting MCP server..."
server.start(transport: :stdio)
```

## Using MCP Server in Robot

```ruby
#!/usr/bin/env ruby
# examples/mcp_client.rb

require "bundler/setup"
require "robot_lab"

RobotLab.configure do |config|
  config.default_model = "claude-sonnet-4"
end

# Robot that uses the MCP server
admin_bot = RobotLab.build do
  name "admin_assistant"
  description "Helps with administrative tasks"

  template <<~PROMPT
    You are an administrative assistant with access to user and order data.
    Help users look up information and manage orders.
  PROMPT

  mcp [
    {
      name: "database",
      transport: {
        type: "stdio",
        command: "ruby",
        args: ["examples/mcp_server.rb"]
      }
    }
  ]
end

# Interactive session
puts "Admin Assistant (uses MCP server)"
puts "-" * 50

state = RobotLab.create_state(message: "List all pro users and their orders")

admin_bot.run(state: state) do |event|
  case event.type
  when :text_delta
    print event.text
  when :tool_call
    puts "\n[MCP: #{event.name}]"
  end
end

puts
admin_bot.disconnect
```

## Network with MCP

```ruby
# examples/network_with_mcp.rb

network = RobotLab.create_network do
  name "support_with_mcp"

  # MCP servers available to all robots
  mcp [
    {
      name: "database",
      transport: { type: "stdio", command: "ruby examples/mcp_server.rb" }
    },
    {
      name: "filesystem",
      transport: {
        type: "stdio",
        command: "npx",
        args: ["@modelcontextprotocol/server-filesystem", "/data"]
      }
    }
  ]

  add_robot RobotLab.build {
    name "data_analyst"
    template "You analyze user data."
    mcp :inherit  # Uses network's MCP servers
  }

  add_robot RobotLab.build {
    name "file_manager"
    template "You manage files."
    mcp :inherit
    tools %w[read_file list_directory]  # Only these MCP tools
  }
end
```

## HTTP MCP Server

```ruby
#!/usr/bin/env ruby
# examples/http_mcp_server.rb

require "robot_lab"
require "sinatra"

server = RobotLab::MCP::Server.new(name: "api_tools")

server.add_tool(
  name: "get_stats",
  description: "Get system statistics",
  parameters: {},
  handler: -> {
    {
      uptime: `uptime`.strip,
      memory: `free -m 2>/dev/null || vm_stat`.strip,
      time: Time.now.iso8601
    }
  }
)

# Sinatra endpoint for MCP
post "/mcp" do
  content_type :json
  request_body = JSON.parse(request.body.read)
  response = server.handle_request(request_body)
  response.to_json
end

# Run: ruby examples/http_mcp_server.rb
# Connect with HTTP transport
```

## Connecting to HTTP Server

```ruby
robot = RobotLab.build do
  name "remote_assistant"
  template "You have access to remote tools."

  mcp [
    {
      name: "remote",
      transport: {
        type: "http",
        url: "https://mcp.example.com/mcp",
        headers: { "Authorization" => "Bearer #{ENV['MCP_TOKEN']}" }
      }
    }
  ]
end
```

## WebSocket Server

```ruby
#!/usr/bin/env ruby
# examples/websocket_mcp_server.rb

require "robot_lab"

server = RobotLab::MCP::Server.new(name: "realtime_tools")

server.add_tool(
  name: "subscribe_events",
  description: "Subscribe to real-time events",
  parameters: { channel: { type: "string", required: true } },
  handler: ->(channel:) { { subscribed: channel } }
)

# Start WebSocket server
server.start(transport: :websocket, port: 8765)
```

## Running

```bash
# Start MCP server in one terminal
ruby examples/mcp_server.rb

# Run client in another terminal
export ANTHROPIC_API_KEY="your-key"
ruby examples/mcp_client.rb
```

## Key Concepts

1. **Server Creation**: Use `RobotLab::MCP::Server.new`
2. **Tool Registration**: Add tools with `server.add_tool`
3. **Transport**: Choose stdio, http, websocket, or sse
4. **Client Connection**: Configure in robot's `mcp` block
5. **Tool Filtering**: Use `tools` whitelist for security

## See Also

- [MCP Integration Guide](../guides/mcp-integration.md)
- [MCP API Reference](../api/mcp/index.md)
- [Transports](../api/mcp/transports.md)
