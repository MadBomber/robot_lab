# MCP Integration

RobotLab supports the Model Context Protocol (MCP) for connecting to external tool servers.

## What is MCP?

MCP is a protocol that allows LLM applications to connect to external servers that provide tools, resources, and context. This enables:

- Reusable tool servers across applications
- Separation of tool logic from AI logic
- Dynamic tool discovery

## Configuring MCP Servers

### At Robot Level

Use the `mcp:` parameter on `RobotLab.build` to connect a robot to MCP servers:

```ruby
robot = RobotLab.build(
  name: "coder",
  template: :developer,
  mcp: [
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
        command: "mcp-server-github",
        env: { "GITHUB_TOKEN" => ENV["GITHUB_TOKEN"] }
      }
    }
  ]
)
```

### In Template Front Matter

MCP servers can be declared directly in a template's YAML front matter, making the template fully self-contained:

```markdown title="prompts/github_assistant.md"
---
description: GitHub assistant with MCP tool access
mcp:
  - name: github
    transport: stdio
    command: npx
    args: ["-y", "@modelcontextprotocol/server-github"]
---
You are a helpful GitHub assistant with access to GitHub tools via MCP.
```

```ruby
# MCP config comes from the template — no mcp: parameter needed
robot = RobotLab.build(template: :github_assistant)
```

Constructor `mcp:` overrides frontmatter `mcp:` when provided.

### Hierarchical Configuration

The `mcp:` parameter supports three modes:

| Value | Behavior |
|-------|----------|
| `:none` | No MCP servers (default) |
| `:inherit` | Inherit from network or global config |
| `[...]` | Explicit array of server configurations |

```ruby
# Inherit from network/config
robot = RobotLab.build(
  name: "reader",
  system_prompt: "You help read files.",
  mcp: :inherit
)

# Disable MCP explicitly
robot = RobotLab.build(
  name: "calculator",
  system_prompt: "You do math.",
  mcp: :none
)
```

### Resolution Order

MCP configuration resolves through a hierarchy: **runtime > robot build > network > global config**. Each level can override the previous:

```
Global (RobotLab.config.mcp)
  -> Network (task mcp: [...])
    -> Robot (mcp: :inherit | :none | [...])
      -> Runtime (robot.run("msg", mcp: [...]))
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

Once configured, MCP tools are automatically discovered and made available to the robot. The robot connects to MCP servers on its first `run` call and discovers tools dynamically:

```ruby
robot = RobotLab.build(
  name: "helper",
  system_prompt: <<~PROMPT
    You can help users with GitHub tasks.
    Use available tools to search repositories, create issues, etc.
  PROMPT,
  mcp: [
    { name: "github", transport: { type: "stdio", command: "mcp-server-github" } }
  ]
)

# MCP tools are automatically available
result = robot.run("Find repositories about machine learning")
puts result.last_text_content
```

## Filtering MCP Tools

Use the `tools:` parameter to restrict which tools (including MCP-discovered tools) are available to a robot:

```ruby
robot = RobotLab.build(
  name: "reader",
  system_prompt: "You help read and search files.",
  mcp: [
    { name: "filesystem", transport: { type: "stdio", command: "mcp-server-fs" } }
  ],
  tools: %w[read_file search_files list_directory]  # Only allow specific tools
)
```

## MCP in Networks

When running robots in a network, use per-task MCP configuration:

```ruby
network = RobotLab.create_network(name: "dev_pipeline") do
  task :planner, planner_robot, depends_on: :none
  task :coder, coder_robot,
       mcp: [
         { name: "filesystem", transport: { type: "stdio", command: "mcp-server-fs" } }
       ],
       depends_on: [:planner]
  task :reviewer, reviewer_robot, depends_on: [:coder]
end
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

## MCP Server and Client Objects

For programmatic access, you can work with MCP objects directly:

```ruby
# Server configuration
server = RobotLab::MCP::Server.new(
  name: "my_server",
  transport: {
    type: "stdio",
    command: "my-mcp-server"
  }
)

# Client connection
client = RobotLab::MCP::Client.new(server)
client.connect

client.connected?           # => true
client.list_tools           # => Array of tool definitions
client.call_tool("search", { query: "ruby" })
client.list_resources       # => Array of resource definitions
client.disconnect
```

## Error Handling

### Connection Errors

```ruby
begin
  result = robot.run("Search for repos")
rescue RobotLab::MCPError => e
  puts "MCP Error: #{e.message}"
end
```

!!! tip
    MCP connection failures are logged as warnings but do not raise errors by default. The robot will continue without MCP tools if a server is unreachable.

## Disconnecting

Robots can be manually disconnected from MCP servers:

```ruby
robot.disconnect  # Disconnect all MCP clients
```

## Patterns

### Development vs Production

```ruby
mcp_config = if Rails.env.development?
  [{ name: "local_fs", transport: { type: "stdio", command: "mcp-fs", args: ["--root", "."] } }]
else
  [{ name: "s3", transport: { type: "stdio", command: "mcp-s3" } }]
end

robot = RobotLab.build(
  name: "file_handler",
  system_prompt: "You manage files.",
  mcp: mcp_config
)
```

### Dynamic Server Selection

```ruby
def mcp_servers_for_user(user)
  servers = []
  servers << github_server if user.github_connected?
  servers << slack_server if user.slack_connected?
  servers
end

robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You help the user with connected services.",
  mcp: mcp_servers_for_user(current_user)
)
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

Restrict which MCP tools are available to a robot using the `tools:` parameter:

```ruby
robot = RobotLab.build(
  name: "reader",
  system_prompt: "You read and search files.",
  mcp: [{ name: "fs", transport: { type: "stdio", command: "mcp-fs" } }],
  tools: %w[read_file search_files]  # No write access
)
```

### 3. Use Appropriate Transports

| Transport | Best For |
|-----------|----------|
| `stdio` | Local servers, CLI tools |
| `websocket` | Persistent connections, bidirectional |
| `sse` | Server push, event streams |
| `streamable_http` | Remote APIs, session-based |

## Next Steps

- [Using Tools](using-tools.md) - Local tool patterns
- [Creating Networks](creating-networks.md) - Network configuration
- [API Reference: MCP](../api/mcp/index.md) - Complete MCP API
