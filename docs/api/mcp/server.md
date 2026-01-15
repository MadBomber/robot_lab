# MCP Server

Expose tools via Model Context Protocol.

## Class: `RobotLab::MCP::Server`

```ruby
server = RobotLab::MCP::Server.new(name: "my_tools")

server.add_tool(
  name: "get_time",
  description: "Get current time",
  handler: ->(**_) { Time.now.iso8601 }
)

server.start(transport: :stdio)
```

## Constructor

```ruby
Server.new(name:, version: "1.0.0")
```

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `name` | `String` | Server name |
| `version` | `String` | Server version |

## Attributes

### name

```ruby
server.name  # => String
```

Server identifier.

### version

```ruby
server.version  # => String
```

Server version.

### tools

```ruby
server.tools  # => Array<Tool>
```

Registered tools.

## Methods

### add_tool

```ruby
server.add_tool(
  name:,
  description:,
  parameters: {},
  handler:
)
```

Register a tool with the server.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `name` | `String` | Tool name |
| `description` | `String` | Tool description |
| `parameters` | `Hash` | Parameter schema |
| `handler` | `Proc` | Execution function |

### remove_tool

```ruby
server.remove_tool(name)
```

Unregister a tool.

### start

```ruby
server.start(transport: :stdio, **options)
```

Start the server.

**Transport Options:**

| Transport | Options |
|-----------|---------|
| `:stdio` | None |
| `:websocket` | `port:`, `host:` |
| `:sse` | `port:`, `host:`, `path:` |
| `:http` | `port:`, `host:`, `path:` |

### stop

```ruby
server.stop
```

Stop the server.

## Examples

### Basic Server

```ruby
server = RobotLab::MCP::Server.new(name: "utilities")

server.add_tool(
  name: "echo",
  description: "Echo back the input",
  parameters: {
    message: { type: "string", required: true }
  },
  handler: ->(message:) { message }
)

server.start(transport: :stdio)
```

### Database Tools Server

```ruby
server = RobotLab::MCP::Server.new(name: "database")

server.add_tool(
  name: "query_users",
  description: "Query users by criteria",
  parameters: {
    status: { type: "string", enum: ["active", "inactive"] },
    limit: { type: "integer", default: 10 }
  },
  handler: ->(status: nil, limit: 10) {
    scope = User.all
    scope = scope.where(status: status) if status
    scope.limit(limit).map(&:to_h)
  }
)

server.add_tool(
  name: "get_user",
  description: "Get user by ID",
  parameters: {
    id: { type: "string", required: true }
  },
  handler: ->(id:) {
    user = User.find_by(id: id)
    user ? user.to_h : { error: "Not found" }
  }
)

server.start(transport: :websocket, port: 8080)
```

### From Robot Tools

```ruby
# Convert existing robot tools to MCP server
robot = RobotLab.build do
  name "assistant"

  tool :calculate do
    description "Perform calculation"
    parameter :expression, type: :string, required: true
    handler { |expression:, **_| eval(expression) }
  end
end

server = RobotLab::MCP::Server.from_robot(robot)
server.start(transport: :stdio)
```

### HTTP Server

```ruby
server = RobotLab::MCP::Server.new(name: "api_tools")

server.add_tool(
  name: "fetch_data",
  description: "Fetch data from API",
  parameters: {
    endpoint: { type: "string", required: true }
  },
  handler: ->(endpoint:) {
    response = HTTP.get("https://api.example.com/#{endpoint}")
    JSON.parse(response.body)
  }
)

server.start(transport: :http, port: 3001, path: "/mcp")
```

### With Resources

```ruby
server = RobotLab::MCP::Server.new(name: "files")

server.add_resource(
  uri: "file://config",
  name: "Configuration",
  description: "Application configuration",
  handler: -> { File.read("config.yml") }
)

server.start(transport: :stdio)
```

## See Also

- [MCP Overview](index.md)
- [MCP Client](client.md)
- [Transports](transports.md)
