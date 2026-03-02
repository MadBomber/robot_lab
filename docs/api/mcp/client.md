# MCP Client

Connects to MCP servers, discovers tools, and invokes them via the Model Context Protocol.

## Class: `RobotLab::MCP::Client`

```ruby
client = RobotLab::MCP::Client.new(
  name: "filesystem",
  transport: { type: "stdio", command: "mcp-server-filesystem", args: ["--root", "/data"] }
)

client.connect
tools = client.list_tools
result = client.call_tool("readFile", { path: "/data/readme.txt" })
client.disconnect
```

## Constructor

```ruby
Client.new(server_or_config)
```

Accepts either a `Server` instance or a Hash configuration. When a Hash is provided, it is used to construct a `Server` internally.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `server_or_config` | `Server`, `Hash` | Server instance or configuration hash |

**Hash Configuration Keys:**

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | `String` | Yes | Server identifier |
| `transport` | `Hash` | Yes | Transport configuration (must include `type`) |
| `timeout` | `Numeric` | No | Request timeout in seconds (default: 15). Propagated to the transport layer |

**Raises:** `ArgumentError` if the config is neither a `Server` nor a `Hash`.

## Attributes

### server

```ruby
client.server  # => RobotLab::MCP::Server
```

The MCP server configuration object.

### connected?

```ruby
client.connected?  # => Boolean
```

Whether the client is currently connected to the server.

## Methods

### connect

```ruby
client.connect  # => self
```

Establish a connection to the MCP server. Creates the appropriate transport based on the server's transport type, then connects. If already connected, returns immediately.

Connection failures are logged as warnings and the client remains in a disconnected state (does not raise).

### disconnect

```ruby
client.disconnect  # => self
```

Close the connection to the MCP server. Closes the underlying transport and resets connection state. If not connected, returns immediately.

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

Converts the client to a hash representation containing server config and connection status.

## Transport Configuration

The transport type is determined by the `type` key in the transport hash of the `Server` configuration.

### Stdio

```ruby
client = RobotLab::MCP::Client.new(
  name: "local",
  transport: {
    type: "stdio",
    command: "npx",
    args: ["@modelcontextprotocol/server-filesystem", "/path"]
  }
)
```

### WebSocket

```ruby
client = RobotLab::MCP::Client.new(
  name: "remote",
  transport: {
    type: "ws",
    url: "wss://mcp.example.com/ws"
  }
)
```

### SSE

```ruby
client = RobotLab::MCP::Client.new(
  name: "streaming",
  transport: {
    type: "sse",
    url: "https://mcp.example.com/sse"
  }
)
```

### Streamable HTTP

```ruby
client = RobotLab::MCP::Client.new(
  name: "http",
  transport: {
    type: "streamable-http",
    url: "https://mcp.example.com/mcp",
    session_id: "optional-session-id"
  }
)
```

## Examples

### Basic Usage

```ruby
client = RobotLab::MCP::Client.new(
  name: "github",
  transport: { type: "stdio", command: "mcp-server-github" }
)

client.connect

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

# MCP tools are automatically discovered and available to the LLM
result = robot.run("Read the contents of /data/config.yml")
puts result.last_text_content
```

### Error Handling

```ruby
begin
  client.connect
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
