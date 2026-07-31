# MCP (Model Context Protocol)

Integration with MCP servers for extended tool capabilities.

## Overview

MCP allows robots to connect to external tool servers, extending their capabilities without modifying robot code. RobotLab provides an MCP client that communicates with MCP-compliant servers over multiple transport types.

```ruby
robot = Robot.new(
  name: "developer",
  system_prompt: "You help with coding tasks.",
  mcp: [
    {
      name: "filesystem",
      transport: {
        type: "stdio",
        command: "npx",
        args: ["@modelcontextprotocol/server-filesystem", "/data"]
      }
    }
  ]
)

# MCP is opt-in per run — see "Connecting at Run Time" below.
result = robot.run("What files are in /data?", mcp: :inherit, tools: :inherit)
```

## Components

| Component | Description |
|-----------|-------------|
| [Client](client.md) | Connects to MCP servers, lists tools, calls tools |
| [Server](server.md) | Server configuration data structure |
| [Transports](transports.md) | Communication methods (stdio, WebSocket, SSE, HTTP) |
| [ConnectionPoller](client.md#connectionpoller) | Optional shared `IO.select` loop multiplexing several stdio transports |
| `MCP::ServerDiscovery` | Picks the relevant subset of configured servers for a message (see [Server Discovery](#server-discovery)) |

## Quick Start

### Using MCP with a Robot

Pass MCP server configurations via the `mcp:` parameter when creating a robot:

```ruby
robot = Robot.new(
  name: "assistant",
  template: :assistant,
  mcp: [
    { name: "github", transport: { type: "stdio", command: "mcp-server-github" } }
  ]
)

result = robot.run("List my open pull requests", mcp: :inherit, tools: :inherit)
result.last_text_content
```

### Connecting at Run Time

`Robot#run` defaults to `mcp: :none, tools: :none`. Those defaults mean "connect
nothing and send zero tools for this turn", so a bare `robot.run("...")` reaches
the LLM with **no** MCP servers connected and **no** tools attached, even when
`mcp:` was supplied at build time.

```ruby
robot.run("...")                                  # no MCP, no tools
robot.run("...", tools: :inherit)                 # attached local tools only
robot.run("...", mcp: :inherit, tools: :inherit)  # connect MCP servers AND send their tools
```

`mcp: :inherit` triggers the connection attempt; `tools: :inherit` is what
actually forwards the discovered MCP tools to the model. Both are needed.

!!! warning "Build-time `:inherit` depends on whether there is a parent"
    `resolve_mcp_hierarchy` does not freeze the parent at construction — it
    recomputes it on **every run** as
    `network_config&.mcp || network_parent_config(network)&.mcp || RobotLab.config.mcp`,
    then resolves the build-time value against it, then the runtime value against
    *that*.

    - For a **standalone** robot the parent is the global default `:none`, so a
      build-time `mcp: :inherit` / `tools: :inherit` collapses to an allowlist
      that matches nothing. Give the standalone robot an explicit array at build
      time and pass `:inherit` at run time.
    - **Inside a network** whose `config:` sets `mcp:`/`tools:`, build-time
      `:inherit` is exactly how a robot opts in to the network's list — see
      [MCP in Networks](#mcp-in-networks) below.

`robot.connect_mcp!` connects eagerly, but a later plain `run()` still sends no
tools. Connection failures are logged and recorded in
`robot.failed_mcp_server_names` — they are not raised.

### MCP in Networks

A robot can inherit its MCP server list from the network's `config:`. This is one
of only two fields (`mcp` and `tools`) that a network-level `RunConfig`
propagates to member robots, and only when the robot opts in with `:inherit`:

```ruby
network = RobotLab.create_network(
  name: "dev",
  config: RobotLab::RunConfig.new(
    mcp: [{ name: "github", transport: { type: "stdio", command: "mcp-server-github" } }]
  )
) do |n|
  n.task :assistant,
         Robot.new(name: "assistant", template: :assistant, mcp: :inherit),
         mcp: :inherit, tools: :inherit
end
```

Here the build-time `mcp: :inherit` on the robot is correct and necessary: the
parent is resolved at run time from the network's `config:`, so `:inherit` picks
up the network's server list rather than the global `:none`.

`Network#task` has the same `mcp: :none, tools: :none` defaults as `Robot#run`,
so the task must opt in as well — otherwise the inherited list collapses to `[]`.

LLM fields (`model`, `temperature`, ...) and callbacks are **not** inherited from
a network config; each robot reads those from its own configuration.

### Direct Client Usage

`Client.new` takes the server (or config hash) as a **positional** argument:

```ruby
client = RobotLab::MCP::Client.new(
  name: "filesystem",
  transport: { type: "stdio", command: "mcp-server-filesystem", args: ["--root", "/data"] }
)
# ArgumentError: wrong number of arguments (given 0, expected 1)

client = RobotLab::MCP::Client.new(
  {
    name: "filesystem",
    transport: { type: "stdio", command: "mcp-server-filesystem", args: ["--root", "/data"] }
  }
)

client.connect
tools = client.list_tools
result = client.call_tool("readFile", { path: "/data/config.yml" })
client.disconnect
```

### Server Discovery

When a robot is built with `mcp_discovery: true`, the configured server list is
filtered before connecting: `MCP::ServerDiscovery` scores each server's
`name + description` against the user's message using term-frequency cosine
similarity and connects only the servers scoring at or above the threshold
(`DEFAULT_THRESHOLD` = 0.05).

```ruby
robot = RobotLab.build(
  name: "assistant",
  mcp_discovery: true,
  mcp: [
    { name: "filesystem", description: "Read, write, and search local files",
      transport: { type: "stdio", command: "mcp-server-fs" } },
    { name: "brew", description: "Install and manage macOS packages via Homebrew",
      transport: { type: "stdio", command: "mcp-server-brew" } }
  ]
)

# Connects only the "brew" server for this message
robot.run("install imagemagick", mcp: :inherit, tools: :inherit)
```

Discovery falls back to the **full** server list when no server has a
`description`, when the query is blank, when no server clears the threshold, or
when the optional `classifier` gem is unavailable.

## Transport Types

| Type | Config Key | Use Case |
|------|------------|----------|
| `stdio` | `"stdio"` | Local command/subprocess execution |
| `websocket` | `"ws"` or `"websocket"` | Real-time bidirectional communication |
| `sse` | `"sse"` | Server-sent events streaming |
| `streamable-http` | `"streamable-http"` or `"http"` | HTTP request/response with session support |

## MCP Parameter Values

The `mcp:` parameter on a Robot accepts three types of values:

| Value | Meaning |
|-------|---------|
| `:none` | No MCP servers (explicitly disabled) |
| `:inherit` | Resolve against the parent level (network config, then global config) |
| `Array<Hash>` | Explicit list of server configurations |

Each server configuration hash is passed straight to `MCP::Server.new`:

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | `String` | Yes | Unique server identifier |
| `transport` | `Hash` | Yes | Transport configuration (must include `type`) |
| `timeout` | `Numeric` | No | Request timeout in seconds (default: 15) |
| `description` | `String` | No | Human-readable summary; the text `ServerDiscovery` scores against |

`transport:` must be a **nested hash**. A flat `transport: "stdio"` with sibling
`command:`/`args:` keys raises internally (`NoMethodError: undefined method
'transform_keys' for an instance of String`). `init_mcp_client` rescues it rather
than re-raising, so the robot still builds — but with zero tools from that
server. It is not silent: the failure is logged at `warn` through
`RobotLab.config.logger` (`"Robot '<name>' error connecting to MCP server
'<server>': ..."`) and the server is recorded in
`robot.failed_mcp_server_names`. The same holds for an invalid transport type
reached through the robot path.

`MCP::Server#initialize` ends in `**_extra`, so any other key you add is
accepted and silently discarded — a typo in `timeout` or `description` will not
raise.

## Error Handling

`RobotLab::MCPError` is raised when a request is made without an active
connection, and by the transports for protocol/I-O failures.

**`Client#connect` does not raise.** It rescues every `StandardError` — including
a failed transport handshake and an unsupported transport type — logs a warning,
and leaves the client disconnected. Check `client.connected?` after connecting:

```ruby
client.connect

unless client.connected?
  warn "MCP server unavailable"
  return
end

begin
  client.call_tool("unknown_tool", {})
rescue RobotLab::MCPError => e
  puts "MCP error: #{e.message}"
end
```

An invalid transport type or a missing `command`/`url` raises `ArgumentError`
from `MCP::Server.new` — and because `MCP::Client.new` builds the server, from
`Client.new` too:

```ruby
RobotLab::MCP::Server.new(name: "x", transport: { type: "bogus", command: "z" })
# ArgumentError: Invalid transport type: bogus. Must be one of:
#   stdio, sse, ws, websocket, streamable-http, http
```

That `ArgumentError` only reaches you when you construct the server or client
**directly**. Through the robot path it is rescued like any other connect
failure — `init_mcp_client` logs it at `warn` and adds the server to
`failed_mcp_server_names`:

```ruby
robot = RobotLab.build(name: "t", system_prompt: "hi",
                       mcp: [{ name: "x", transport: { type: "bogus", command: "z" } }])
robot.connect_mcp!
# WARN -- : Robot 't' error connecting to MCP server 'x': Invalid transport type: bogus...
robot.failed_mcp_server_names  # => ["x"]
```

## See Also

- [MCP Client](client.md)
- [MCP Server](server.md)
- [Transports](transports.md)
