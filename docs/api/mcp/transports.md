# MCP Transports

Communication methods for MCP client-server connections.

## Overview

Transports handle the low-level communication between `MCP::Client` and external MCP servers. All transports implement the same interface defined by `Transports::Base`, using JSON-RPC 2.0 for message exchange and the MCP protocol version `2024-11-05` for initialization.

RobotLab provides four built-in transport types:

| Transport | Class | Use Case | Status |
|-----------|-------|----------|--------|
| Stdio | `Transports::Stdio` | Local subprocess servers | Fully working |
| WebSocket | `Transports::WebSocket` | Real-time bidirectional | **Broken** — see below |
| SSE | `Transports::SSE` | Server-sent events | Working, but `connect` reports success unconditionally |
| Streamable HTTP | `Transports::StreamableHTTP` | HTTP with session support | Working, but `connect` reports success unconditionally |

> **Read this before using a non-stdio transport.** Only `Stdio` performs its
> connection and MCP handshake synchronously. The other three wrap that work in
> an `Async do ... end` block whose result is never awaited, so any error raised
> inside — including a refused TCP connection — is discarded. `connect` returns
> `self` regardless. The specific consequences are documented per transport
> below.

## Base Interface

All transports inherit from `RobotLab::MCP::Transports::Base` and implement:

```ruby
class RobotLab::MCP::Transports::Base
  DEFAULT_TIMEOUT = 15  # seconds

  attr_reader :config   # => Hash (symbolized keys, :timeout removed)
  attr_reader :timeout  # => Numeric (seconds, extracted from config)

  def connect        # Establish connection, returns self
  def send_request(message)  # Send JSON-RPC message, returns Hash response
  def close          # Close connection, returns self
  def connected?     # Returns Boolean
end
```

The `timeout` is extracted from the config hash during initialization (and removed from `config`). If not provided, it defaults to `DEFAULT_TIMEOUT` (15 seconds). The timeout is propagated from `MCP::Server` through `MCP::Client` to the transport.

**Only `Stdio` enforces the timeout.** `SSE`, `WebSocket`, and `StreamableHTTP`
store `@timeout` and expose it through the `timeout` reader, but never reference
it — their requests are not time-bounded by this value. If you need a bound on a
non-stdio transport, wrap the call yourself, or route the client through an
`MCP::ConnectionPoller` (stdio only).

## Stdio Transport

**Class:** `RobotLab::MCP::Transports::Stdio`

Spawns a subprocess and communicates via stdin/stdout using JSON-RPC messages (one per line). Automatically sends MCP `initialize` and `notifications/initialized` on connect. All blocking I/O is wrapped with `Timeout.timeout` so a missing or hung server cannot block the caller forever.

### Configuration

```ruby
{
  type: "stdio",
  command: "mcp-server-filesystem",      # Required: executable command
  args: ["--root", "/data"],             # Optional: command arguments
  env: { "DEBUG" => "true" },            # Optional: environment variables
  timeout: 10                            # Optional: request timeout in seconds (default: 15)
}
```

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `command` | `String` | Yes | Executable command to spawn |
| `args` | `Array<String>` | No | Command arguments |
| `env` | `Hash` | No | Environment variables (merged with current env) |
| `timeout` | `Numeric` | No | Request timeout in seconds (default: 15) |

### Behavior

- Uses `Open3.popen3` to spawn the subprocess
- Verifies the process actually started (raises `MCPError` if it exits immediately)
- Writes JSON-RPC messages to stdin (one per line)
- Reads responses from stdout, skipping notifications (messages without `id`)
- All blocking reads are wrapped with `Timeout.timeout` — raises `MCPError` if the server does not respond within the timeout period
- `connected?` returns `true` when the subprocess is alive
- `close` calls `cleanup_process` to reliably close stdin, stdout, stderr and kill the subprocess
- Handles `Errno::ENOENT` (command not found), `Errno::EPIPE` / `IOError` (broken pipe / connection lost), and `Timeout::Error` (hung server) with clear error messages

### Example

```ruby
transport = RobotLab::MCP::Transports::Stdio.new(
  command: "mcp-server-filesystem",
  args: ["--root", "/data"],
  env: { "DEBUG" => "true" },
  timeout: 10
)

transport.connect
response = transport.send_request({ jsonrpc: "2.0", id: 1, method: "tools/list" })
transport.close
```

## WebSocket Transport

**Class:** `RobotLab::MCP::Transports::WebSocket`

Intended to use `async-websocket` for non-blocking bidirectional communication.

> **This transport does not currently work.** `connect` calls
> `Async::HTTP::Endpoint.parse`, but only requires `async` and
> `async/websocket/client` — the `Async::HTTP` namespace is never loaded, so the
> call raises `NameError`. That happens inside an un-awaited `Async` block, so
> the error is swallowed: `connect` returns `self`, no `MCPError` is raised, and
> `connected?` stays `false`. Every subsequent `send_request` then raises
> `MCPError, "Not connected"`.
>
> Verified: `WebSocket.new(url: "ws://127.0.0.1:9/ws").connect.connected?` is
> `false` with no exception surfacing.
>
> The rescue on `connect` only catches `LoadError`, which is raised if
> `async-websocket` is missing. Because of the `Async::HTTP::Endpoint` call, this
> transport also needs `async-http` even once `async-websocket` is installed —
> both are declared as runtime dependencies of the gem.

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

- Intends to use `Async::WebSocket::Client.connect` within an `Async` block, then
  send the MCP `initialize` handshake
- In practice the block raises `NameError` on `Async::HTTP::Endpoint` before the
  connection is created, and the un-awaited block discards it
- `send_request` sends JSON-RPC messages as JSON strings and reads the response
  inside an awaited `Async` block — but it raises `MCPError, "Not connected"`
  because `@connected` was never set
- `connect` raises `MCPError` only for `LoadError` (missing `async-websocket`);
  it does not raise for a connection failure
- `close` is a no-op while `@connected` is `false`

### Example

```ruby
transport = RobotLab::MCP::Transports::WebSocket.new(
  url: "ws://localhost:8080"
)

transport.connect
transport.connected?  # => false, even against a live server

# Raises MCPError: "Not connected"
transport.send_request({ jsonrpc: "2.0", id: 1, method: "tools/list" })
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

- Creates an `Async::HTTP::Client` on connect, then sends the MCP `initialize`
  handshake
- Sends JSON-RPC messages via HTTP POST with `Content-Type: application/json`
- Reads and parses JSON response body
- Raises `MCPError` if the `async-http` gem is not installed (`LoadError` only)
- The `timeout` from the server config is stored but never applied

> **`connect` always reports success.** `@connected = true` is assigned *before*
> `send_initialize` runs, and the whole sequence is inside an un-awaited `Async`
> block. Against an unreachable host, `connect` returns `self`, `connected?`
> returns `true`, and the handshake failure is never surfaced. The first real
> `send_request` is where the failure appears.
>
> Verified: `SSE.new(url: "http://127.0.0.1:9/sse").connect.connected?` is `true`.

### Example

```ruby
transport = RobotLab::MCP::Transports::SSE.new(
  url: "http://localhost:8080/sse"
)

transport.connect
# connected? is true here whether or not the server exists

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
- Raises `MCPError` if the `async-http` gem is not installed (`LoadError` only)
- The `timeout` from the server config is stored but never applied

> **`connect` always reports success**, for the same reason as SSE:
> `@connected = true` precedes `send_initialize`, and the enclosing `Async` block
> is never awaited. `connected?` returns `true` against an unreachable host, and
> `session_id` stays at whatever you configured (`nil` if you configured nothing)
> because the handshake result was discarded.
>
> Verified: `StreamableHTTP.new(url: "http://127.0.0.1:9/mcp").connect` yields
> `connected? == true`, `session_id == nil`.

### Example

```ruby
transport = RobotLab::MCP::Transports::StreamableHTTP.new(
  url: "https://server.smithery.ai/neon/mcp",
  auth_provider: -> { "Bearer #{ENV['MCP_TOKEN']}" }
)

transport.connect
puts transport.session_id  # => pre-configured value, or nil until a request lands

response = transport.send_request({ jsonrpc: "2.0", id: 1, method: "tools/list" })
transport.close
```

## Connection Lifecycle

All transports expose the same four-step lifecycle:

1. **Create** -- instantiate with configuration hash
2. **Connect** -- establish connection and perform MCP protocol initialization
3. **Request/Response** -- send JSON-RPC requests, receive responses
4. **Close** -- tear down connection and release resources

Step 2 behaves differently per transport:

| Transport | `connect` is synchronous | Errors surface from `connect` | `connected?` reflects reality |
|-----------|--------------------------|-------------------------------|-------------------------------|
| `Stdio` | Yes | Yes (`MCPError`) | Yes — also checks the process is alive |
| `SSE` | No (un-awaited `Async`) | No | No — always `true` after `connect` |
| `StreamableHTTP` | No (un-awaited `Async`) | No | No — always `true` after `connect` |
| `WebSocket` | No (un-awaited `Async`) | No | No — always `false` after `connect` |

Only `Stdio` gives you a trustworthy answer at connect time. For the other three,
treat the first `send_request` as the real connection test.

Each transport builds the same MCP `initialize` message during connect:

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
- **Not connected** -- calling `send_request` before `connect` raises `MCPError` (all transports)
- **Missing gem** -- WebSocket, SSE, and HTTP transports raise `MCPError` with a `LoadError` message if the required gem (`async-websocket` / `async-http`) is not installed. This is the *only* error `connect` re-raises on those three
- **Connection refused / unreachable host** -- **not** reported by SSE, WebSocket, or StreamableHTTP `connect`; the error is discarded with the un-awaited `Async` block
- **No response** -- Stdio transport raises `MCPError` if the subprocess produces no output (EOF on stdout)
- **Command not found** -- Stdio transport raises `MCPError` with the original `Errno::ENOENT` message
- **Timeout** -- Stdio transport raises `MCPError` if the server does not respond within the configured timeout. No other transport enforces a timeout
- **Broken pipe** -- Stdio transport raises `MCPError` and marks itself disconnected on `Errno::EPIPE` or `IOError`
- **Immediate exit** -- Stdio transport raises `MCPError` if the server process exits immediately after spawn

## See Also

- [MCP Overview](index.md)
- [MCP Client](client.md)
- [Server Configuration](server.md)
