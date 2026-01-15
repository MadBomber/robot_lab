# MCP Client

Connects to MCP servers and discovers tools.

## Class: `RobotLab::MCP::Client`

```ruby
client = RobotLab::MCP::Client.new(
  name: "filesystem",
  transport: { type: "stdio", command: "mcp-server-filesystem" }
)

client.connect
tools = client.list_tools
```

## Constructor

```ruby
Client.new(name:, transport:)
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `name` | `String` | Server identifier |
| `transport` | `Hash` | Transport configuration |

## Attributes

### name

```ruby
client.name  # => String
```

Server identifier.

### transport

```ruby
client.transport  # => Transport
```

The underlying transport connection.

### connected?

```ruby
client.connected?  # => Boolean
```

Whether the client is connected.

## Methods

### connect

```ruby
client.connect
```

Establish connection to the MCP server.

### disconnect

```ruby
client.disconnect
```

Close the connection.

### list_tools

```ruby
client.list_tools  # => Array<Tool>
```

Discover available tools from the server.

### call_tool

```ruby
result = client.call_tool(name, params)
```

Execute a tool on the server.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `name` | `String` | Tool name |
| `params` | `Hash` | Tool parameters |

### list_resources

```ruby
client.list_resources  # => Array<Resource>
```

List available resources (if supported).

### read_resource

```ruby
client.read_resource(uri)  # => Resource
```

Read a resource by URI.

## Transport Configuration

### Stdio

```ruby
client = Client.new(
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
client = Client.new(
  name: "remote",
  transport: {
    type: "websocket",
    url: "wss://mcp.example.com/ws"
  }
)
```

### SSE

```ruby
client = Client.new(
  name: "streaming",
  transport: {
    type: "sse",
    url: "https://mcp.example.com/sse"
  }
)
```

### HTTP

```ruby
client = Client.new(
  name: "http",
  transport: {
    type: "http",
    url: "https://mcp.example.com/mcp"
  }
)
```

## Examples

### Basic Usage

```ruby
client = Client.new(
  name: "github",
  transport: { type: "stdio", command: "mcp-server-github" }
)

client.connect

# List available tools
tools = client.list_tools
tools.each { |t| puts "#{t.name}: #{t.description}" }

# Call a tool
result = client.call_tool("search_repositories", { query: "ruby mcp" })
puts result

client.disconnect
```

### In Robot

```ruby
robot = RobotLab.build do
  name "assistant"

  mcp [
    { name: "fs", transport: { type: "stdio", command: "mcp-fs" } }
  ]
end

# MCP tools are automatically available
robot.tools.each { |t| puts t.name }
```

### Error Handling

```ruby
begin
  client.connect
  result = client.call_tool("unknown_tool", {})
rescue RobotLab::MCP::ConnectionError => e
  puts "Failed to connect: #{e.message}"
rescue RobotLab::MCP::ToolError => e
  puts "Tool error: #{e.message}"
ensure
  client.disconnect
end
```

## See Also

- [MCP Overview](index.md)
- [Transports](transports.md)
- [MCP Server](server.md)
