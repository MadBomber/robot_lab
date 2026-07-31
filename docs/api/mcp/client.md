# MCP Client

Connects to MCP servers, discovers tools, and invokes them via the Model Context Protocol.

## Class: `RobotLab::MCP::Client`

```ruby
client = RobotLab::MCP::Client.new(
  {
    name: "filesystem",
    transport: { type: "stdio", command: "mcp-server-filesystem", args: ["--root", "/data"] }
  }
)

client.connect
tools = client.list_tools
result = client.call_tool("readFile", { path: "/data/readme.txt" })
client.disconnect
```

## Constructor

```ruby
Client.new(server_or_config, poller: nil)
```

`server_or_config` is **positional**. Passing the server keys directly —
`Client.new(name: "fs", transport: {...})` — raises
`ArgumentError: wrong number of arguments (given 0, expected 1)`. Wrap the
configuration in braces.

Accepts either a `Server` instance or a Hash configuration. When a Hash is provided, it is used to construct a `Server` internally.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `server_or_config` | `Server`, `Hash` | **required, positional** | Server instance or configuration hash |
| `poller` | `MCP::ConnectionPoller`, `nil` | `nil` | Shared `IO.select` poller for multiplexing stdio transports (see [ConnectionPoller](#connectionpoller)) |

**Hash Configuration Keys:**

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | `String` | Yes | Server identifier |
| `transport` | `Hash` | Yes | Transport configuration (must include `type`) |
| `timeout` | `Numeric` | No | Request timeout in seconds (default: 15). Propagated to the transport layer |
| `description` | `String` | No | Human-readable summary used by `MCP::ServerDiscovery` |

**Raises:** `ArgumentError` if the config is neither a `Server` nor a `Hash`.

## Attributes

### server

```ruby
client.server  # => RobotLab::MCP::Server
```

The MCP server configuration object.

### transport

```ruby
client.transport  # => RobotLab::MCP::Transports::Base subclass | nil
```

The transport instance created by `connect`. `nil` before the first successful
`connect` and again after `disconnect`.

### connected

```ruby
client.connected   # => Boolean
client.connected?  # => Boolean
```

Whether the client is currently connected to the server. `connected` is a plain
reader over the same ivar that `connected?` returns; both are public.

## Methods

### connect

```ruby
client.connect  # => self
```

Establish a connection to the MCP server. Creates the appropriate transport based on the server's transport type, then connects. If already connected, returns immediately. When a `poller:` was supplied, the client registers itself with the poller after the transport connects.

Connection failures are logged as warnings and the client remains in a disconnected state (does not raise). Always check `connected?` afterwards.

### disconnect

```ruby
client.disconnect  # => self
```

Close the connection to the MCP server. Unregisters from the poller (if any), closes the underlying transport, and resets `transport` to `nil`. If not connected, returns immediately.

### list_tools

```ruby
client.list_tools  # => Array<Hash>
```

Discover available tools from the server. Returns an array of tool definition hashes.

**Raises:** `MCPError` if not connected.

### call_tool

```ruby
result = client.call_tool(name, arguments = {})
```

Execute a tool on the server.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `name` | `String` | Tool name |
| `arguments` | `Hash` | Tool arguments (default: `{}`) |

**Returns:** Tool result content (from the `content` field of the response).

**Raises:** `MCPError` if not connected.

### list_resources

```ruby
client.list_resources  # => Array<Hash>
```

List available resources from the server.

**Raises:** `MCPError` if not connected.

### read_resource

```ruby
client.read_resource(uri)  # => Object
```

Read a resource by URI.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `uri` | `String` | Resource URI |

**Raises:** `MCPError` if not connected.

### list_prompts

```ruby
client.list_prompts  # => Array<Hash>
```

List available prompts from the server.

**Raises:** `MCPError` if not connected.

### get_prompt

```ruby
client.get_prompt(name, arguments = {})  # => Hash
```

Get a prompt by name with optional arguments.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `name` | `String` | Prompt name |
| `arguments` | `Hash` | Prompt arguments (default: `{}`) |

**Raises:** `MCPError` if not connected.

### to_h

```ruby
client.to_h  # => Hash
```

Converts the client to a hash representation containing server config and connection status:

```ruby
{ server: { name: "...", description: "...", transport: { ... }, timeout: 15 },
  connected: false }
```

## ConnectionPoller

**Class:** `RobotLab::MCP::ConnectionPoller`

By default each stdio client blocks on its own `@stdout.gets` inside a
`Timeout.timeout`. `ConnectionPoller` replaces that with a single background
thread running one `IO.select` across every registered stdio transport,
dispatching each JSON-RPC response to the client that is waiting for it. This is
useful when one robot talks to several local MCP servers.

It is **opt-in**: nothing in `Robot` or `Network` creates one. `Robot`'s internal
MCP setup calls `MCP::Client.new(server_config)` with no poller. You get a poller
only by wiring it yourself.

Async-based transports (SSE, WebSocket, StreamableHTTP) are unaffected — the
poller silently ignores any client whose transport is not a live `Stdio`.

```ruby
poller = RobotLab::MCP::ConnectionPoller.new.start

client = RobotLab::MCP::Client.new(
  { name: "fs", transport: { type: "stdio", command: "mcp-server-fs" } },
  poller: poller
)

client.connect          # registers the transport's stdout with the poller
client.call_tool("readFile", { path: "/data/readme.txt" })
client.disconnect       # unregisters

poller.stop
```

### Methods

| Method | Description |
|--------|-------------|
| `start` | Start the polling thread (named `RobotLab::MCP::ConnectionPoller`). Idempotent; returns `self` |
| `stop(timeout: 5)` | Stop the thread, cancelling every pending request with an `MCPError`. Waits up to `timeout` seconds for the thread to join. Returns `self` |
| `register(client)` | Register a client. Non-stdio (or not-yet-connected) clients are silently ignored |
| `unregister(client)` | Remove a client's IO from the select set |
| `send_request(client, message, timeout:)` | Write the JSON-RPC message to the client's stdin and block until the poll loop dispatches the response. Raises `MCPError` on timeout or a broken pipe |
| `running?` | Whether the polling thread is running |

`POLL_INTERVAL` is `0.1` seconds — the `IO.select` timeout, and the sleep used
when no clients are registered.

`Client#request` routes through `poller.send_request` only when a poller is
present **and** the transport is a `Transports::Stdio`; otherwise it calls
`transport.send_request` directly.

## Transport Configuration

The transport type is determined by the `type` key in the transport hash of the `Server` configuration.

### Stdio

```ruby
client = RobotLab::MCP::Client.new(
  {
    name: "local",
    transport: {
      type: "stdio",
      command: "npx",
      args: ["@modelcontextprotocol/server-filesystem", "/path"]
    }
  }
)
```

### WebSocket

```ruby
client = RobotLab::MCP::Client.new(
  {
    name: "remote",
    transport: {
      type: "ws",
      url: "wss://mcp.example.com/ws"
    }
  }
)
```

### SSE

```ruby
client = RobotLab::MCP::Client.new(
  {
    name: "streaming",
    transport: {
      type: "sse",
      url: "https://mcp.example.com/sse"
    }
  }
)
```

### Streamable HTTP

```ruby
client = RobotLab::MCP::Client.new(
  {
    name: "http",
    transport: {
      type: "streamable-http",
      url: "https://mcp.example.com/mcp",
      session_id: "optional-session-id"
    }
  }
)
```

## Examples

### Basic Usage

```ruby
client = RobotLab::MCP::Client.new(
  { name: "github", transport: { type: "stdio", command: "mcp-server-github" } }
)

client.connect
raise "could not connect" unless client.connected?

# List available tools
tools = client.list_tools
tools.each { |t| puts "#{t[:name]}: #{t[:description]}" }

# Call a tool
result = client.call_tool("search_repositories", { query: "ruby mcp" })
puts result

client.disconnect
```

### From a Server Object

```ruby
server = RobotLab::MCP::Server.new(
  name: "neon",
  transport: { type: "ws", url: "ws://localhost:8080" }
)

client = RobotLab::MCP::Client.new(server)
client.connect
```

### In a Robot

```ruby
robot = Robot.new(
  name: "assistant",
  system_prompt: "You help with file operations.",
  mcp: [
    { name: "fs", transport: { type: "stdio", command: "mcp-fs" } }
  ]
)

# `Robot#run` defaults to `mcp: :none, tools: :none`. Opt in on every run that
# should reach the MCP servers: `mcp: :inherit` connects them, `tools: :inherit`
# forwards the discovered tools to the model.
result = robot.run("Read the contents of /data/config.yml", mcp: :inherit, tools: :inherit)
puts result.last_text_content
```

MCP connection failures inside a robot are logged and recorded in
`robot.failed_mcp_server_names`; they never raise out of `run`.

### Error Handling

`connect` swallows its own failures, so test `connected?` rather than rescuing
around it:

```ruby
client.connect

begin
  raise RobotLab::MCPError, "not connected" unless client.connected?

  result = client.call_tool("unknown_tool", {})
rescue RobotLab::MCPError => e
  puts "MCP error: #{e.message}"
ensure
  client.disconnect
end
```

## See Also

- [MCP Overview](index.md)
- [Server Configuration](server.md)
- [Transports](transports.md)
