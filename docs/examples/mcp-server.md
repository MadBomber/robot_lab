# MCP Server

Connecting robots to Model Context Protocol servers for external tool access.

## Overview

This example demonstrates how to connect robots to external MCP servers. MCP servers expose tools that robots can discover and invoke automatically. RobotLab supports stdio, HTTP, WebSocket, and SSE transports.

## Using MCP with a Robot

The primary pattern is to pass MCP server configurations via `mcp:` or `mcp_servers:` when building a robot:

```ruby
#!/usr/bin/env ruby
# examples/mcp_client.rb

require "bundler/setup"
require "robot_lab"

# MCP server configuration (stdio transport)
github_server = {
  name: "github",
  transport: {
    type: "stdio",
    command: "github-mcp-server",
    args: ["stdio"],
    env: {
      "GITHUB_PERSONAL_ACCESS_TOKEN" => ENV.fetch("GITHUB_PERSONAL_ACCESS_TOKEN", "")
    }
  }
}

# Create a robot with MCP server integration
# Tools are automatically discovered when the robot connects
robot = RobotLab.build(
  name: "github_assistant",
  system_prompt: <<~PROMPT,
    You are a GitHub assistant with access to repository tools.
    Help users search repos, manage issues, and explore code.
  PROMPT
  mcp: [github_server],
  model: "claude-sonnet-4"
)

# The robot auto-discovers MCP tools on first run
puts "MCP Servers: #{robot.mcp_clients.keys.join(", ")}"
puts "MCP Tools: #{robot.mcp_tools.size} discovered"

# Run the robot -- it can use any discovered MCP tools
result = robot.run("What are the top 3 most starred Ruby web frameworks on GitHub?")
puts result.last_text_content

# Show tool calls if any were made
if result.tool_calls.any?
  puts "\nTool calls made:"
  result.tool_calls.each do |tc|
    tool_info = tc.respond_to?(:tool) ? tc.tool : tc
    puts "  #{tool_info[:name] || tool_info}"
  end
end

# Always disconnect MCP clients when done
robot.disconnect
```

## Direct MCP Client Usage

You can also use the MCP client directly without a robot:

```ruby
require "robot_lab"

# Create and connect MCP client
github_server = {
  name: "github",
  transport: {
    type: "stdio",
    command: "github-mcp-server",
    args: ["stdio"],
    env: { "GITHUB_PERSONAL_ACCESS_TOKEN" => ENV["GITHUB_PERSONAL_ACCESS_TOKEN"] }
  }
}

client = RobotLab::MCP::Client.new(github_server)
client.connect

if client.connected?
  # List available tools
  tools = client.list_tools
  tools.each do |tool|
    puts "#{tool[:name]}: #{tool[:description]}"
  end

  # Call a tool directly
  result = client.call_tool("search_repositories", {
    query: "language:ruby stars:>1000",
    per_page: 5
  })

  puts JSON.pretty_generate(result)

  client.disconnect
end
```

## Multiple MCP Servers

A robot can connect to multiple MCP servers simultaneously:

```ruby
filesystem_server = {
  name: "filesystem",
  transport: {
    type: "stdio",
    command: "npx",
    args: ["@modelcontextprotocol/server-filesystem", "/data"]
  }
}

github_server = {
  name: "github",
  transport: {
    type: "stdio",
    command: "github-mcp-server",
    args: ["stdio"],
    env: { "GITHUB_PERSONAL_ACCESS_TOKEN" => ENV["GITHUB_PERSONAL_ACCESS_TOKEN"] }
  }
}

robot = RobotLab.build(
  name: "developer",
  system_prompt: "You help with coding tasks using GitHub and the filesystem.",
  mcp: [filesystem_server, github_server],
  model: "claude-sonnet-4"
)

result = robot.run("Search for Ruby repos with CI configs and list their workflow files")
puts result.last_text_content

robot.disconnect
```

## MCP in Networks

Networks pass MCP configuration through the hierarchical resolution system. Use `mcp: :inherit` on robots to use the network-level MCP config, or specify per-task MCP servers:

```ruby
# Create robots
data_analyst = RobotLab.build(
  name: "data_analyst",
  system_prompt: "You analyze data.",
  mcp: :inherit   # Will use whatever MCP config is resolved at runtime
)

file_manager = RobotLab.build(
  name: "file_manager",
  system_prompt: "You manage files.",
  mcp: :inherit,
  tools: :none     # Only use inherited MCP tools, no local tools
)

# Create network with per-task MCP configuration
network = RobotLab.create_network(name: "support_with_mcp") do
  task :analyst, data_analyst,
       mcp: [github_server],
       depends_on: :none

  task :files, file_manager,
       mcp: [filesystem_server],
       tools: %w[read_file list_directory],   # Whitelist only these MCP tools
       depends_on: :optional
end

result = network.run(message: "Analyze the project structure")
```

## HTTP Transport

Connect to remote MCP servers over HTTP:

```ruby
robot = RobotLab.build(
  name: "remote_assistant",
  system_prompt: "You have access to remote tools.",
  mcp: [
    {
      name: "remote_api",
      transport: {
        type: "http",
        url: "https://mcp.example.com/mcp",
        headers: { "Authorization" => "Bearer #{ENV['MCP_TOKEN']}" }
      }
    }
  ]
)

result = robot.run("Use the remote tools to check system status")
robot.disconnect
```

## WebSocket Transport

For real-time bidirectional communication:

```ruby
robot = RobotLab.build(
  name: "realtime_assistant",
  system_prompt: "You monitor real-time events.",
  mcp: [
    {
      name: "realtime",
      transport: {
        type: "websocket",
        url: "ws://localhost:8765"
      }
    }
  ]
)

result = robot.run("Subscribe to the events channel")
robot.disconnect
```

## SSE Transport

Server-Sent Events transport for streaming responses:

```ruby
robot = RobotLab.build(
  name: "sse_assistant",
  system_prompt: "You have access to streaming tools.",
  mcp: [
    {
      name: "streaming_api",
      transport: {
        type: "sse",
        url: "https://api.example.com/sse"
      }
    }
  ]
)

result = robot.run("Stream the latest metrics")
robot.disconnect
```

## Runtime MCP Overrides

Override MCP configuration at runtime via `robot.run`:

```ruby
robot = RobotLab.build(
  name: "flexible_bot",
  system_prompt: "You use available tools.",
  mcp: [github_server]
)

# Use default MCP config
result = robot.run("Search for Ruby repos")

# Override MCP at runtime -- disable all MCP
result = robot.run("Just answer from your knowledge", mcp: :none)

robot.disconnect
```

## Running

```bash
# Set API keys
export ANTHROPIC_API_KEY="your-key"
export GITHUB_PERSONAL_ACCESS_TOKEN="your-token"

# Install MCP server (example: GitHub)
brew install github-mcp-server

# Run client
ruby examples/mcp_client.rb
```

## Key Concepts

1. **MCP Configuration**: Pass server configs via `mcp:` parameter on `RobotLab.build` or `Robot.new`
2. **Auto-Discovery**: Tools are automatically discovered when the robot connects to an MCP server
3. **Transport Types**: stdio, http, websocket, sse
4. **Hierarchical Config**: `runtime > robot > network > global`, using `:none`, `:inherit`, or explicit arrays
5. **Tool Filtering**: Use `tools:` whitelist to limit which MCP tools are available
6. **Cleanup**: Always call `robot.disconnect` when done to release MCP connections

## See Also

- [MCP Integration Guide](../guides/mcp-integration.md)
- [MCP API Reference](../api/mcp/index.md)
- [Transports](../api/mcp/transports.md)
