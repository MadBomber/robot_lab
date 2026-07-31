# MCP Server Configuration

Data structure for MCP server connection configuration.

## Class: `RobotLab::MCP::Server`

`Server` is a configuration object that defines how to connect to an MCP server. It holds the server name and transport settings, and validates the configuration on construction.

This is **not** an MCP server implementation -- it is the configuration used by `MCP::Client` to establish a connection to an external MCP server.

```ruby
server = RobotLab::MCP::Server.new(
  name: "filesystem",
  description: "Read, write, and search local files and directories",
  transport: { type: "stdio", command: "mcp-server-filesystem", args: ["--root", "/data"] }
)

# With custom timeout
server = RobotLab::MCP::Server.new(
  name: "slow_server",
  transport: { type: "stdio", command: "heavy-mcp-server" },
  timeout: 30
)
```

## Constructor

```ruby
Server.new(name:, transport:, timeout: nil, description: nil, **_extra)
```

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `String` | **required** | Unique server identifier |
| `transport` | `Hash` | **required** | Transport configuration (must include `type`) |
| `timeout` | `Numeric`, `nil` | `15` | Request timeout in seconds. Values >= 1000 are auto-converted from milliseconds. Minimum 1 second |
| `description` | `String`, `nil` | `""` | Human-readable summary of what the server does; scored by `MCP::ServerDiscovery` |

Any other keyword is absorbed by `**_extra` and silently discarded, so a
misspelled key raises nothing.

**Raises:** `ArgumentError` if:
- The transport type is not one of the valid types
- A stdio transport is missing the `:command` key
- A network transport (ws, websocket, sse, streamable-http, http) is missing the `:url` key

## Constants

```ruby
RobotLab::MCP::Server::VALID_TRANSPORT_TYPES
# => ["stdio", "sse", "ws", "websocket", "streamable-http", "http"]

RobotLab::MCP::Server::DEFAULT_TIMEOUT
# => 15  (seconds)
```

## Attributes

### name

```ruby
server.name  # => String
```

The server identifier string.

### description

```ruby
server.description  # => String
```

Human-readable summary of the server's capabilities. Always a String — a `nil`
or omitted `description:` becomes `""`. Used by `MCP::ServerDiscovery`, which
scores `"#{name} #{description}"` against the user's message when a robot is
built with `mcp_discovery: true`. Discovery falls back to the full server list
when no server in the list has a non-empty description.

### transport

```ruby
server.transport  # => Hash
```

The normalized transport configuration hash (keys are symbols, type is downcased).

### timeout

```ruby
server.timeout  # => Numeric
```

Request timeout in seconds. Defaults to `DEFAULT_TIMEOUT` (15). Values >= 1000 passed to the constructor are auto-converted from milliseconds to seconds. The minimum is 1 second.

## Methods

### transport_type

```ruby
server.transport_type  # => String
```

Returns the transport type string (e.g., `"stdio"`, `"ws"`, `"sse"`).

### to_h

```ruby
server.to_h
# => { name: "y", description: "", transport: { type: "sse", url: "http://x" }, timeout: 30.0 }
```

Converts the server configuration to a hash representation. The hash is **not**
compacted — all four keys are always present, and `description` is `""` when it
was never set. Note that `timeout` is normalized to a Float unless it defaulted
(`DEFAULT_TIMEOUT` is the Integer `15`).

## Transport Configuration Options

### Stdio Transport

For local MCP servers running as subprocesses:

```ruby
Server.new(
  name: "filesystem",
  transport: {
    type: "stdio",
    command: "mcp-server-filesystem",  # Required
    args: ["--root", "/data"],          # Optional
    env: { "DEBUG" => "true" }          # Optional
  }
)
```

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `type` | `String` | Yes | Must be `"stdio"` |
| `command` | `String` | Yes | Executable command |
| `args` | `Array<String>` | No | Command arguments |
| `env` | `Hash` | No | Environment variables |

### WebSocket Transport

For bidirectional real-time communication:

```ruby
Server.new(
  name: "neon",
  transport: {
    type: "ws",
    url: "ws://localhost:8080"  # Required
  }
)
```

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `type` | `String` | Yes | `"ws"` or `"websocket"` |
| `url` | `String` | Yes | WebSocket endpoint URL |

### SSE Transport

For server-sent events streaming:

```ruby
Server.new(
  name: "streaming",
  transport: {
    type: "sse",
    url: "http://localhost:8080/sse"  # Required
  }
)
```

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `type` | `String` | Yes | Must be `"sse"` |
| `url` | `String` | Yes | SSE endpoint URL |

### Streamable HTTP Transport

For HTTP-based communication with session management:

```ruby
Server.new(
  name: "api",
  transport: {
    type: "streamable-http",
    url: "https://server.smithery.ai/neon/mcp",  # Required
    session_id: "abc123",                         # Optional
    auth_provider: -> { "Bearer #{token}" }       # Optional
  }
)
```

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `type` | `String` | Yes | `"streamable-http"` or `"http"` |
| `url` | `String` | Yes | HTTP endpoint URL |
| `session_id` | `String` | No | Session identifier |
| `auth_provider` | `Proc` | No | Authentication callback returning auth header value |

## Examples

### Multiple Server Configurations

```ruby
servers = [
  {
    name: "filesystem",
    transport: { type: "stdio", command: "mcp-server-filesystem", args: ["/data"] }
  },
  {
    name: "github",
    transport: { type: "stdio", command: "mcp-server-github" }
  },
  {
    name: "database",
    transport: { type: "ws", url: "ws://localhost:9090" }
  }
]

# Pass directly to a robot
robot = Robot.new(
  name: "dev_assistant",
  system_prompt: "You help with development tasks.",
  mcp: servers
)

# `run` defaults to `mcp: :none, tools: :none` — opt in per run
robot.run("What changed in the repo?", mcp: :inherit, tools: :inherit)
```

### Creating a Client from a Server

```ruby
server = RobotLab::MCP::Server.new(
  name: "tools",
  transport: { type: "ws", url: "ws://localhost:8080" }
)

client = RobotLab::MCP::Client.new(server)
client.connect
```

## See Also

- [MCP Overview](index.md)
- [MCP Client](client.md)
- [Transports](transports.md)
