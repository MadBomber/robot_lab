# MCP (Model Context Protocol)

Integration with MCP servers for extended tool capabilities.

## Overview

MCP allows robots to connect to external tool servers, extending their capabilities without modifying robot code.

```ruby
robot = RobotLab.build do
  name "developer"
  template "You help with coding tasks."

  mcp [
    {
      name: "filesystem",
      transport: { type: "stdio", command: "npx @modelcontextprotocol/server-filesystem" }
    }
  ]
end
```

## Components

| Component | Description |
|-----------|-------------|
| [Client](client.md) | Connects to MCP servers |
| [Server](server.md) | Exposes tools via MCP |
| [Transports](transports.md) | Communication methods |

## Quick Start

### Using MCP Tools

```ruby
network = RobotLab.create_network do
  name "with_mcp"

  mcp [
    { name: "github", transport: { type: "stdio", command: "mcp-server-github" } }
  ]

  add_robot RobotLab.build {
    name "assistant"
    template "You help with GitHub tasks."
    mcp :inherit  # Use network's MCP servers
  }
end
```

### Creating an MCP Server

```ruby
server = RobotLab::MCP::Server.new(name: "my_tools")

server.add_tool(
  name: "get_user",
  description: "Get user by ID",
  parameters: { id: { type: "string", required: true } },
  handler: ->(id:) { User.find(id).to_h }
)

server.start(transport: :stdio)
```

## Transport Types

| Type | Use Case |
|------|----------|
| `stdio` | Local command execution |
| `websocket` | Real-time bidirectional |
| `sse` | Server-sent events |
| `http` | HTTP request/response |

## Configuration Levels

### Network Level

```ruby
network = RobotLab.create_network do
  mcp [
    { name: "server1", transport: { type: "stdio", command: "..." } }
  ]
end
```

### Robot Level

```ruby
robot = RobotLab.build do
  mcp :inherit  # Use network's servers
  # or
  mcp :none     # No MCP servers
  # or
  mcp [...]     # Specific servers
end
```

### Tool Filtering

```ruby
robot = RobotLab.build do
  mcp :inherit
  tools %w[read_file write_file]  # Only allow these tools
end
```

## See Also

- [MCP Integration Guide](../../guides/mcp-integration.md)
- [Tool](../core/tool.md)
