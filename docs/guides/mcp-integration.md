# MCP Integration

RobotLab supports the Model Context Protocol (MCP) for connecting to external tool servers.

## What is MCP?

MCP is a protocol that allows LLM applications to connect to external servers that provide tools, resources, and context. This enables:

- Reusable tool servers across applications
- Separation of tool logic from AI logic
- Dynamic tool discovery

## Configuring MCP Servers

### At Network Level

```ruby
network = RobotLab.create_network do
  name "dev_assistant"

  mcp [
    {
      name: "filesystem",
      transport: {
        type: "stdio",
        command: "mcp-server-filesystem",
        args: ["--root", "/home/user/projects"]
      }
    },
    {
      name: "github",
      transport: {
        type: "stdio",
        command: "mcp-server-github"
      }
    }
  ]
end
```

### At Robot Level

```ruby
robot = RobotLab.build do
  name "coder"

  # Use network's MCP servers
  mcp :inherit

  # Or specific servers
  mcp [
    { name: "filesystem", transport: { type: "stdio", command: "mcp-fs" } }
  ]

  # Or disable MCP
  mcp :none
end
```

### Global Configuration

```ruby
RobotLab.configure do |config|
  config.mcp = [
    { name: "common_tools", transport: { type: "stdio", command: "common-mcp" } }
  ]
end
```

## Transport Types

### Stdio Transport

Communicate via stdin/stdout with a subprocess:

```ruby
{
  name: "server_name",
  transport: {
    type: "stdio",
    command: "mcp-server-command",
    args: ["--option", "value"],
    env: { "API_KEY" => ENV["API_KEY"] }
  }
}
```

### WebSocket Transport

Connect via WebSocket:

```ruby
{
  name: "remote_server",
  transport: {
    type: "websocket",
    url: "ws://localhost:8080/mcp"
  }
}
```

!!! note "Dependency Required"
    WebSocket transport requires the `async-websocket` gem.

### SSE Transport

Server-Sent Events transport:

```ruby
{
  name: "sse_server",
  transport: {
    type: "sse",
    url: "http://localhost:8080/sse"
  }
}
```

### HTTP Transport

Streamable HTTP transport with session support:

```ruby
{
  name: "http_server",
  transport: {
    type: "streamable_http",
    url: "https://api.example.com/mcp",
    session_id: "optional_session_id",
    auth_provider: -> { "Bearer #{fetch_token}" }
  }
}
```

## Using MCP Tools

Once configured, MCP tools are automatically available to robots:

```ruby
network = RobotLab.create_network do
  mcp [
    { name: "github", transport: { type: "stdio", command: "mcp-server-github" } }
  ]

  add_robot RobotLab.build {
    name "helper"
    template <<~PROMPT
      You can help users with GitHub tasks.
      Use available tools to search repositories, create issues, etc.
    PROMPT
  }
end

# The robot can now use GitHub MCP tools
state = RobotLab.create_state(message: "Find repositories about machine learning")
network.run(state: state)
```

## Filtering MCP Tools

Restrict which MCP tools are available:

```ruby
robot = RobotLab.build do
  name "reader"
  mcp :inherit

  # Only allow specific MCP tools
  tools %w[read_file search_code list_directory]
end
```

## MCP Server Configuration

### Server Object

```ruby
server = RobotLab::MCP::Server.new(
  name: "my_server",
  transport: {
    type: "stdio",
    command: "my-mcp-server"
  }
)

server.name           # => "my_server"
server.transport_type # => "stdio"
server.to_h           # Hash representation
```

### Client Object

```ruby
client = RobotLab::MCP::Client.new(server: server)
client.connect

client.connected?     # => true
client.to_h           # Client info
```

## Common MCP Servers

### Filesystem

```ruby
{
  name: "filesystem",
  transport: {
    type: "stdio",
    command: "mcp-server-filesystem",
    args: ["--root", "/path/to/files"]
  }
}
```

Tools: `read_file`, `write_file`, `list_directory`, `search_files`

### GitHub

```ruby
{
  name: "github",
  transport: {
    type: "stdio",
    command: "mcp-server-github",
    env: { "GITHUB_TOKEN" => ENV["GITHUB_TOKEN"] }
  }
}
```

Tools: `search_repositories`, `create_issue`, `get_file_contents`, etc.

### Database

```ruby
{
  name: "postgres",
  transport: {
    type: "stdio",
    command: "mcp-server-postgres",
    env: { "DATABASE_URL" => ENV["DATABASE_URL"] }
  }
}
```

Tools: `query`, `list_tables`, `describe_table`

## Error Handling

### Connection Errors

```ruby
begin
  network.run(state: state)
rescue RobotLab::MCPError => e
  puts "MCP Error: #{e.message}"
  # Handle gracefully
end
```

### Missing Dependencies

```ruby
# If async-websocket not installed
rescue RobotLab::MCPError => e
  if e.message.include?("async-websocket")
    puts "Install async-websocket gem for WebSocket support"
  end
end
```

## Disconnecting

Robots automatically disconnect from MCP servers when done:

```ruby
robot.disconnect  # Manually disconnect
```

Networks handle this automatically at the end of a run.

## Patterns

### Development vs Production

```ruby
network = RobotLab.create_network do
  mcp_config = if Rails.env.development?
    [{ name: "local_fs", transport: { type: "stdio", command: "mcp-fs", args: ["--root", "."] } }]
  else
    [{ name: "s3", transport: { type: "stdio", command: "mcp-s3" } }]
  end

  mcp mcp_config
end
```

### Dynamic Server Selection

```ruby
def mcp_servers_for_user(user)
  servers = []
  servers << github_server if user.github_connected?
  servers << slack_server if user.slack_connected?
  servers
end

network = RobotLab.create_network do
  mcp mcp_servers_for_user(current_user)
end
```

## Best Practices

### 1. Use Environment Variables for Credentials

```ruby
{
  name: "github",
  transport: {
    type: "stdio",
    command: "mcp-server-github",
    env: {
      "GITHUB_TOKEN" => ENV["GITHUB_TOKEN"],
      "GITHUB_ORG" => ENV["GITHUB_ORG"]
    }
  }
}
```

### 2. Limit Tool Access

```ruby
# Don't expose all tools
robot = RobotLab.build do
  mcp :inherit
  tools %w[read_file search_files]  # No write access
end
```

### 3. Handle Disconnections

```ruby
begin
  result = network.run(state: state)
rescue RobotLab::MCPError
  # Retry without MCP
  result = network.run(state: state, mcp: :none)
end
```

## Next Steps

- [Using Tools](using-tools.md) - Local tool patterns
- [Creating Networks](creating-networks.md) - Network configuration
- [API Reference: MCP](../api/mcp/index.md) - Complete MCP API
