# MCP (Model Context Protocol)

Integration with MCP servers for extended tool capabilities.

## Overview

MCP allows robots to connect to external tool servers, extending their capabilities without modifying robot code. RobotLab provides an MCP client that communicates with MCP-compliant servers over multiple transport types.

```ruby
robot = Robot.new(
  name: "developer",
  system_prompt: "You help with coding tasks.",
  mcp: [
    {
      name: "filesystem",
      transport: { type: "stdio", command: "npx @modelcontextprotocol/server-filesystem" }
    }
  ]
)
```

## Components

| Component | Description |
|-----------|-------------|
| [Client](client.md) | Connects to MCP servers, lists tools, calls tools |
| [Server](server.md) | Server configuration data structure |
| [Transports](transports.md) | Communication methods (stdio, WebSocket, SSE, HTTP) |

## Quick Start

### Using MCP with a Robot

Pass MCP server configurations via the `mcp:` parameter when creating a robot:

```ruby
robot = Robot.new(
  name: "assistant",
  template: :assistant,
  mcp: [
    { name: "github", transport: { type: "stdio", command: "mcp-server-github" } }
  ]
)

result = robot.run("List my open pull requests")
result.last_text_content
```

### MCP in Networks

Robots in a network can inherit MCP servers from the network or define their own:

```ruby
network_mcp = [
  { name: "github", transport: { type: "stdio", command: "mcp-server-github" } }
]

robot = Robot.new(
  name: "assistant",
  template: :assistant,
  mcp: :inherit  # Use network's MCP servers
)
```

### Direct Client Usage

```ruby
client = RobotLab::MCP::Client.new(
  name: "filesystem",
  transport: { type: "stdio", command: "mcp-server-filesystem", args: ["--root", "/data"] }
)

client.connect
tools = client.list_tools
result = client.call_tool("readFile", { path: "/data/config.yml" })
client.disconnect
```

## Transport Types

| Type | Config Key | Use Case |
|------|------------|----------|
| `stdio` | `"stdio"` | Local command/subprocess execution |
| `websocket` | `"ws"` or `"websocket"` | Real-time bidirectional communication |
| `sse` | `"sse"` | Server-sent events streaming |
| `streamable-http` | `"streamable-http"` or `"http"` | HTTP request/response with session support |

## MCP Parameter Values

The `mcp:` parameter on a Robot accepts three types of values:

| Value | Meaning |
|-------|---------|
| `:none` | No MCP servers (explicitly disabled) |
| `:inherit` | Use the network's MCP servers |
| `Array<Hash>` | Explicit list of server configurations |

Each server configuration hash requires:

| Key | Type | Description |
|-----|------|-------------|
| `name` | `String` | Unique server identifier |
| `transport` | `Hash` | Transport configuration (must include `type`) |

## Error Handling

MCP operations raise `RobotLab::MCPError` when:

- Connection to a server fails
- A request is made without an active connection
- An unsupported transport type is specified

```ruby
begin
  client.connect
  client.call_tool("unknown_tool", {})
rescue RobotLab::MCPError => e
  puts "MCP error: #{e.message}"
end
```

## See Also

- [MCP Client](client.md)
- [MCP Server](server.md)
- [Transports](transports.md)
