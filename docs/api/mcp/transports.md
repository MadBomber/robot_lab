# MCP Transports

Communication methods for MCP client-server connections.

## Overview

Transports handle the low-level communication between `MCP::Client` and external MCP servers. All transports implement the same interface defined by `Transports::Base`, using JSON-RPC 2.0 for message exchange and the MCP protocol version `2024-11-05` for initialization.

RobotLab provides four built-in transport types:

| Transport | Class | Use Case |
|-----------|-------|----------|
| Stdio | `Transports::Stdio` | Local subprocess servers |
| WebSocket | `Transports::WebSocket` | Real-time bidirectional |
| SSE | `Transports::SSE` | Server-sent events |
| Streamable HTTP | `Transports::StreamableHTTP` | HTTP with session support |

## Base Interface

All transports inherit from `RobotLab::MCP::Transports::Base` and implement:

```ruby
class RobotLab::MCP::Transports::Base
  attr_reader :config  # => Hash (symbolized keys)

  def connect        # Establish connection, returns self
  def send_request(message)  # Send JSON-RPC message, returns Hash response
  def close          # Close connection, returns self
  def connected?     # Returns Boolean
end
```

## Stdio Transport

**Class:** `RobotLab::MCP::Transports::Stdio`

Spawns a subprocess and communicates via stdin/stdout using JSON-RPC messages (one per line). Automatically sends MCP `initialize` and `notifications/initialized` on connect.

### Configuration

```ruby
{
  type: "stdio",
  command: "mcp-server-filesystem",      # Required: executable command
  args: ["--root", "/data"],             # Optional: command arguments
  env: { "DEBUG" => "true" }             # Optional: environment variables
}
```

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `command` | `String` | Yes | Executable command to spawn |
| `args` | `Array<String>` | No | Command arguments |
| `env` | `Hash` | No | Environment variables (merged with current env) |

### Behavior

- Uses `Open3.popen3` to spawn the subprocess
- Writes JSON-RPC messages to stdin (one per line)
- Reads responses from stdout, skipping notifications (messages without `id`)
- `connected?` returns `true` when the subprocess is alive
- `close` terminates stdin, stdout, stderr, and kills the subprocess

### Example

```ruby
transport = RobotLab::MCP::Transports::Stdio.new(
  command: "mcp-server-filesystem",
  args: ["--root", "/data"],
  env: { "DEBUG" => "true" }
)

transport.connect
response = transport.send_request({ jsonrpc: "2.0", id: 1, method: "tools/list" })
transport.close
```

## WebSocket Transport

**Class:** `RobotLab::MCP::Transports::WebSocket`

Uses `async-websocket` for non-blocking bidirectional communication. Requires the `async-websocket` gem.

### Configuration

```ruby
{
  type: "ws",                              # or "websocket"
  url: "wss://mcp.example.com/ws"          # Required: WebSocket endpoint
}
```

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `url` | `String` | Yes | WebSocket endpoint URL |

### Behavior

- Uses `Async::WebSocket::Client.connect` within an `Async` block
- Sends JSON-RPC messages as JSON strings
- Reads responses synchronously within the async context
- Raises `MCPError` if the `async-websocket` gem is not installed

### Example

```ruby
transport = RobotLab::MCP::Transports::WebSocket.new(
  url: "ws://localhost:8080"
)

transport.connect
response = transport.send_request({ jsonrpc: "2.0", id: 1, method: "tools/list" })
transport.close
```

## SSE Transport

**Class:** `RobotLab::MCP::Transports::SSE`

Uses `async-http` for HTTP-based communication. Sends requests via HTTP POST and reads responses. Requires the `async-http` gem.

### Configuration

```ruby
{
  type: "sse",
  url: "http://localhost:8080/sse"         # Required: SSE endpoint
}
```

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `url` | `String` | Yes | SSE/HTTP endpoint URL |

### Behavior

- Creates an `Async::HTTP::Client` on connect
- Sends JSON-RPC messages via HTTP POST with `Content-Type: application/json`
- Reads and parses JSON response body
- Raises `MCPError` if the `async-http` gem is not installed

### Example

```ruby
transport = RobotLab::MCP::Transports::SSE.new(
  url: "http://localhost:8080/sse"
)

transport.connect
response = transport.send_request({ jsonrpc: "2.0", id: 1, method: "tools/list" })
transport.close
```

## Streamable HTTP Transport

**Class:** `RobotLab::MCP::Transports::StreamableHTTP`

HTTP-based transport with session management and optional authentication. Supports session IDs for maintaining server-side state across requests. Requires the `async-http` gem.

### Configuration

```ruby
{
  type: "streamable-http",                 # or "http"
  url: "https://server.smithery.ai/neon/mcp",  # Required: HTTP endpoint
  session_id: "abc123",                    # Optional: session identifier
  auth_provider: -> { "Bearer #{token}" }  # Optional: auth callback
}
```

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `url` | `String` | Yes | HTTP endpoint URL |
| `session_id` | `String` | No | Pre-existing session identifier |
| `auth_provider` | `Proc` | No | Callback returning Authorization header value |

### Behavior

- Creates an `Async::HTTP::Client` on connect
- Sends MCP `initialize` on connect; if no session ID was provided, extracts it from the server response (`serverInfo.sessionId`)
- Sends `X-Session-ID` header with each request when a session ID is available
- Calls `auth_provider` for each request to populate the `Authorization` header
- Exposes `session_id` reader for accessing the current session ID
- Raises `MCPError` if the `async-http` gem is not installed

### Example

```ruby
transport = RobotLab::MCP::Transports::StreamableHTTP.new(
  url: "https://server.smithery.ai/neon/mcp",
  auth_provider: -> { "Bearer #{ENV['MCP_TOKEN']}" }
)

transport.connect
puts transport.session_id  # => assigned by server or pre-configured

response = transport.send_request({ jsonrpc: "2.0", id: 1, method: "tools/list" })
transport.close
```

## Connection Lifecycle

All transports follow the same lifecycle:

1. **Create** -- instantiate with configuration hash
2. **Connect** -- establish connection and perform MCP protocol initialization
3. **Request/Response** -- send JSON-RPC requests, receive responses
4. **Close** -- tear down connection and release resources

Each transport sends the MCP `initialize` message during connect:

```json
{
  "jsonrpc": "2.0",
  "id": 0,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {
      "name": "RobotLab",
      "version": "<current version>"
    }
  }
}
```

## Error Handling

All transports raise `RobotLab::MCPError` for connection and communication failures:

```ruby
begin
  transport.connect
  transport.send_request(message)
rescue RobotLab::MCPError => e
  puts "Transport error: #{e.message}"
ensure
  transport.close
end
```

Specific error cases:
- **Not connected** -- calling `send_request` before `connect` raises `MCPError`
- **Missing gem** -- WebSocket, SSE, and HTTP transports raise `MCPError` with a `LoadError` message if required gems are not installed
- **No response** -- Stdio transport raises `MCPError` if the subprocess produces no output

## See Also

- [MCP Overview](index.md)
- [MCP Client](client.md)
- [Server Configuration](server.md)
