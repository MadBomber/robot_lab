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
    transport:
      type: stdio
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

> [!CAUTION]
> `transport:` must be a **nested mapping**, exactly as above. The flat form —
> `transport: stdio` with sibling `command:`/`args:` keys — does not raise:
> `Server` calls `transform_keys` on the transport value, a String raises
> `NoMethodError: undefined method 'transform_keys' for an instance of String`,
> and that exception is caught by MCP setup's rescue. The robot builds and runs
> with **zero tools** from that server. It is not silent, though: the failure is
> logged at `WARN` through `RobotLab.config.logger` (`$stdout` by default) and
> the server name is recorded in `robot.failed_mcp_server_names`.

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
  -> Network (network config:  / task config:)
    -> Robot (mcp: :inherit | :none | [...])
      -> Runtime (robot.run("msg", mcp: [...]), and task mcp: [...])
```

> [!NOTE]
> A task's `mcp:`/`tools:` are **not** a separate network tier — `Task` puts
> them into the run params, so they arrive as the **runtime** value for that
> robot's `run()`. Only a `config:` (on the network or on the task) acts as the
> parent level that `:inherit` resolves against.

## Timeout Configuration

Every server config accepts a `timeout:`. The default is 15 seconds
(`RobotLab::MCP::Server::DEFAULT_TIMEOUT`). Set it at the server level:

```ruby
robot = RobotLab.build(
  name: "patient_bot",
  system_prompt: "You help with slow operations.",
  mcp: [
    {
      name: "heavy_server",
      transport: { type: "stdio", command: "heavy-mcp-server" },
      timeout: 60  # seconds
    }
  ]
)
```

Values >= 1000 are auto-converted from milliseconds to seconds. The minimum timeout is 1 second:

| Given | Stored |
|-------|--------|
| `nil` | `15` (the default) |
| `30` | `30.0` |
| `5000` | `5.0` (read as milliseconds) |
| `0.5` | `1` (floored to the 1-second minimum) |

> [!WARNING]
> **Only the Stdio transport actually enforces the timeout.** SSE, WebSocket,
> and StreamableHTTP store the value and never reference it — a remote MCP
> server that stops responding will hang the call indefinitely regardless of
> what you set here. Apply your own timeout around remote-transport calls if
> you need one.

## Transport Types

Valid `type:` values are exactly: `stdio`, `sse`, `ws`, `websocket`,
`streamable-http`, `http` (`RobotLab::MCP::Server::VALID_TRANSPORT_TYPES`).

An invalid type raises `ArgumentError: Invalid transport type: <type>. Must be
one of: stdio, sse, ws, websocket, streamable-http, http` — but **only if you
construct the server or client yourself**. Through the robot (`mcp:` on
`RobotLab.build`) the error is caught by the same rescue that handles any other
connect failure: it is logged at `WARN` and the server name is recorded in
`robot.failed_mcp_server_names`, and the robot carries on with zero tools from
that server. See [Connection Errors](#connection-errors).

```ruby
bad = { name: "oops", transport: { type: "streamable_http", url: "https://x" } }

RobotLab::MCP::Server.new(**bad)   # => raises ArgumentError

robot = RobotLab.build(name: "r", system_prompt: "...", mcp: [bad])
robot.run("hi", mcp: :inherit, tools: :inherit)
# logs: WARN Robot 'r' error connecting to MCP server 'oops': Invalid transport type: ...
robot.failed_mcp_server_names   # => ["oops"]
```

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
    WebSocket transport requires the `async-websocket` gem. (It also reaches for
    `Async::HTTP::Endpoint` without requiring it, so `async-http` must be loaded
    as well.)

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

!!! note "Dependency Required"
    SSE transport requires the `async-http` gem.

### HTTP Transport

Streamable HTTP transport with session support:

```ruby
{
  name: "http_server",
  transport: {
    type: "streamable-http",   # or "http" — NOT "streamable_http"
    url: "https://api.example.com/mcp",
    session_id: "optional_session_id",
    auth_provider: -> { "Bearer #{fetch_token}" }
  }
}
```

!!! note "Dependency Required"
    Streamable HTTP transport requires the `async-http` gem.

> [!CAUTION]
> The type is spelled with a **hyphen**. `type: "streamable_http"` (underscore)
> raises `ArgumentError: Invalid transport type: streamable_http`.

> [!WARNING]
> The remote transports connect inside an un-awaited `Async` block and set
> their connected flag **before** the MCP initialize handshake. `client.connected?`
> therefore returns `true` even when the host is unreachable — do not treat it
> as proof the server answered. Stdio is the only transport that blocks on the
> handshake and reports a connect failure synchronously.

## Using MCP Tools

Once configured, MCP tools are discovered on connect and made available to the
robot. **Connecting is not automatic** — see the warning below:

```ruby
robot = RobotLab.build(
  name: "helper",
  system_prompt: <<~PROMPT,
    You can help users with GitHub tasks.
    Use available tools to search repositories, create issues, etc.
  PROMPT
  mcp: [
    { name: "github", transport: { type: "stdio", command: "mcp-server-github" } }
  ]
)

# mcp: :inherit connects the servers; tools: :inherit sends their tools to the LLM.
result = robot.run("Find repositories about machine learning", mcp: :inherit, tools: :inherit)
puts result.last_text_content
```

> [!CAUTION]
> **A plain `robot.run(message)` neither connects MCP servers nor sends any
> tools.** Both the `mcp:` and `tools:` parameters of `run` default to `:none`,
> which means "zero this turn" — the build-time `mcp:` list is simply not
> consulted. You need **both** flags:
>
> ```ruby
> robot.run("...")                                   # no MCP connection, no tools
> robot.run("...", mcp: :inherit)                    # connects, but sends zero tools
> robot.run("...", mcp: :inherit, tools: :inherit)   # connects AND sends its tools
> ```

## Filtering MCP Tools

Use the `tools:` parameter to restrict which tools (including MCP-discovered
tools) reach the LLM. It is a **name allowlist**, and it must be supplied at the
level that actually runs — the `run()` call (or the network `task`, which
forwards to `run()`):

```ruby
robot = RobotLab.build(
  name: "reader",
  system_prompt: "You help read and search files.",
  mcp: [
    { name: "filesystem", transport: { type: "stdio", command: "mcp-server-fs" } }
  ]
)

robot.run("Summarise the README",
          mcp:   :inherit,
          tools: %w[read_file search_files list_directory])  # only these
```

> [!WARNING]
> A build-time `tools: %w[...]` allowlist has no effect on its own, because the
> runtime default of `:none` sends zero tools regardless. And for a
> **standalone** robot, do not write `tools: :inherit` at build time as a
> workaround: there the parent level is the global `:none`, so it produces an
> allowlist of `["none"]` that matches nothing. Leave build-time `tools:` unset
> and pass the filter at run time.
>
> Inside a **network** whose `config:` supplies `tools:`/`mcp:`, this reverses:
> the parent level is the network's list, and build-time `:inherit` is what
> makes the robot pick it up. See
> [Network-Wide Tool and MCP Defaults](creating-networks.md#network-wide-tool-and-mcp-defaults).

## MCP in Networks

When running robots in a network, use per-task MCP configuration. Remember that
a task's `mcp:`/`tools:` become that robot's **runtime** values, so `tools:`
must be set too or the MCP tools will not be sent:

```ruby
network = RobotLab.create_network(name: "dev_pipeline") do
  task :planner, planner_robot, depends_on: :none
  task :coder, coder_robot,
       mcp: [
         { name: "filesystem", transport: { type: "stdio", command: "mcp-server-fs" } }
       ],
       tools: :inherit,
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

> [!NOTE]
> `MCP::Client#initialize(server_or_config, poller: nil)` takes its server as a
> **positional** argument — either a `Server` instance or a config Hash.
> `Client.new(name: "x", transport: {...})` raises `ArgumentError: wrong number
> of arguments (given 0, expected 1)`; wrap the hash in braces:
> `Client.new({ name: "x", transport: {...} })`.

## Connection Multiplexing

When a robot connects to several local (stdio) MCP servers, each client normally blocks independently while waiting for a response. `MCP::ConnectionPoller` replaces this with a single `IO.select` call across all registered stdout file descriptors, dispatching each response to the pending request for that client.

This is primarily useful in networks where many robots each have multiple stdio MCP servers. Async-based transports (SSE, WebSocket, StreamableHTTP) are unaffected — they already use the Async fiber scheduler.

```ruby
# Create a shared poller
poller = RobotLab::MCP::ConnectionPoller.new.start

# Pass the poller when building clients
client1 = RobotLab::MCP::Client.new(
  { name: "filesystem", transport: { type: "stdio", command: "mcp-server-fs" } },
  poller: poller
)
client2 = RobotLab::MCP::Client.new(
  { name: "github", transport: { type: "stdio", command: "mcp-server-github" } },
  poller: poller
)

client1.connect   # registers with poller
client2.connect   # registers with poller

# Both clients share the IO.select loop
client1.list_tools
client2.list_tools

poller.stop
```

Without a shared poller each client uses its own blocking `Timeout.timeout` call. With a poller, responses from any registered server wake the poller's select loop, which dispatches to the right waiting thread via a `Thread::Queue`.

!!! note
    Only stdio clients are registered with the poller. SSE, WebSocket, and StreamableHTTP clients passed a `poller:` argument ignore it silently.

## Server Discovery

When a robot has many MCP servers configured, connecting to all of them upfront is wasteful — most servers will be irrelevant for any given user message. **Server Discovery** uses TF cosine similarity to select only the semantically relevant servers before the first `ensure_mcp_clients` call.

### Enabling Discovery

Add `description:` to each server config and set `mcp_discovery: true` on the robot:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful assistant.",
  mcp_discovery: true,
  mcp: [
    {
      name: "filesystem",
      description: "Read, write, and search local files and directories",
      transport: { type: "stdio", command: "mcp-server-filesystem" }
    },
    {
      name: "github",
      description: "GitHub repos, issues, pull requests, code search",
      transport: { type: "stdio", command: "mcp-server-github" }
    },
    {
      name: "brew",
      description: "Install, update, and manage macOS packages via Homebrew",
      transport: { type: "stdio", command: "mcp-server-brew" }
    }
  ]
)

# Discovery connects only :brew for this message — filesystem and github are skipped.
# mcp: :inherit is required; a plain run() resolves the MCP list to empty and
# discovery never runs.
robot.run("install imagemagick", mcp: :inherit, tools: :inherit)
```

### How It Works

`MCP::ServerDiscovery.select(query, from:, threshold:)` computes TF cosine similarity between the user's query and each server's topic text (`name + description`). Servers scoring at or above `DEFAULT_THRESHOLD` (0.05) are returned; the rest are excluded.

The threshold is intentionally low — server descriptions are short, so raw cosine scores are naturally small even for on-topic queries.

Discovery only applies on the **first** MCP-resolving `run()` call (before the robot is marked MCP-initialized). Once a set of servers is connected they remain connected for the robot's lifetime, preserving tool continuity across a conversation.

### Fallback Behaviour

All servers are returned unchanged when any of the following apply:

| Condition | Reason |
|-----------|--------|
| No server has a `description` field | Nothing to score against |
| `classifier` gem unavailable | Raises `DependencyError`, caught internally |
| Query is blank or nil | Nothing to compare |
| No server scores ≥ threshold | Rather fall back than leave the robot with no tools |

### Using the API Directly

```ruby
servers = [
  { name: "filesystem", description: "Read and write files",
    transport: { type: "stdio", command: "mcp-server-fs" } },
  { name: "github",     description: "GitHub repos and PRs",
    transport: { type: "stdio", command: "mcp-server-github" } }
]

relevant = RobotLab::MCP::ServerDiscovery.select(
  "search github repos",
  from: servers,
  threshold: 0.05   # optional, default
)
# => [{ name: "github", ... }]
```

> [!IMPORTANT]
> Scoring is lexical, not semantic — it compares word stems against each
> server's `description`. A query that happens to share no stems with **any**
> description scores 0.0 everywhere, trips the "nothing above threshold"
> fallback in the table above, and gets **all** servers back rather than none.
> With the two servers above:
>
> ```ruby
> select("search github repos",     from: servers)  # => ["github"]
> select("read and write files",    from: servers)  # => ["filesystem"]
> select("list open pull requests", from: servers)  # => ["filesystem", "github"]  <- fallback
> ```
>
> The last one selects everything because the description says "PRs", not "pull
> requests". Write descriptions using the words your prompts will actually use.

## Connection Resilience

### Eager Connection

`connect_mcp!` connects the robot's configured servers immediately, without
waiting for a `run()` that passes `mcp: :inherit`:

```ruby
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You help with tasks.",
  mcp: [
    { name: "github", transport: { type: "stdio", command: "mcp-server-github" } },
    { name: "filesystem", transport: { type: "stdio", command: "mcp-server-fs" } }
  ]
)

robot.connect_mcp!

# Check which servers failed
if robot.failed_mcp_server_names.any?
  puts "Failed to connect: #{robot.failed_mcp_server_names.join(', ')}"
end
```

> [!NOTE]
> `connect_mcp!` only opens the connections. A later plain `robot.run(message)`
> still sends the LLM **zero** tools, because `run`'s `tools:` defaults to
> `:none`. Eager connection and tool visibility are separate switches.

### Automatic Retry

Failed MCP servers are retried on subsequent `run()` calls **that resolve to a
non-empty MCP list** — i.e. runs that pass `mcp: :inherit` (or an explicit
array). If a server was down when the robot first connected, it is retried
transparently:

```ruby
robot.run("First message",  mcp: :inherit, tools: :inherit)  # github connects, filesystem fails
# ... filesystem comes back up ...
robot.run("Second message", mcp: :inherit, tools: :inherit)  # filesystem retried and connects
```

### Injecting External MCP Clients

Host applications that manage MCP connections externally can inject pre-connected clients into a robot:

```ruby
robot.inject_mcp!(clients: my_clients, tools: my_tools)
```

This skips the normal connection process and marks the robot as MCP-initialized.

## Error Handling

### Connection Errors

MCP connection failures are **not raised**. They are logged as warnings and
recorded on the robot; the run continues without that server's tools, and one
failing server does not prevent the others from connecting. Inspect the result
rather than rescuing:

```ruby
result = robot.run("Search for repos", mcp: :inherit, tools: :inherit)

if robot.failed_mcp_server_names.any?
  warn "MCP servers unavailable: #{robot.failed_mcp_server_names.join(', ')}"
end
```

### Timeout Errors

Stdio transports wrap all blocking I/O with a configurable timeout. On expiry
the transport raises `MCPError`. Note that the two messages differ, and neither
uses the server *name* you configured — the handshake message names the
**command**, and the per-request message names nothing at all:

```ruby
# Handshake timed out during connect:
# RobotLab::MCPError: MCP server 'heavy-mcp-server' did not respond within 15s

# A later request timed out:
# RobotLab::MCPError: MCP server did not respond within 15s
```

> [!IMPORTANT]
> `MCP::Client#connect` rescues **every** `StandardError`, logs
> `"MCP connection failed for <name>: ..."` at `:warn`, and returns `self` with
> `connected?` false. So a connect-time timeout never reaches your `begin/rescue`
> — check `client.connected?` (or `robot.failed_mcp_server_names`) instead.
> Per-request calls such as `list_tools` and `call_tool` **do** propagate
> `MCPError`.

SSE, WebSocket, and StreamableHTTP raise no timeout error at all — see the
warning under [Timeout Configuration](#timeout-configuration).

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

Restrict which MCP tools reach the LLM with a `tools:` allowlist on the run:

```ruby
robot = RobotLab.build(
  name: "reader",
  system_prompt: "You read and search files.",
  mcp: [{ name: "fs", transport: { type: "stdio", command: "mcp-fs" } }]
)

robot.run("Find the config file",
          mcp:   :inherit,
          tools: %w[read_file search_files])  # No write access
```

### 3. Use Appropriate Transports

| Transport | Best For |
|-----------|----------|
| `stdio` | Local servers, CLI tools. The only transport that enforces `timeout:` and reports connect failures synchronously. |
| `websocket` (or `ws`) | Persistent connections, bidirectional |
| `sse` | Server push, event streams |
| `streamable-http` (or `http`) | Remote APIs, session-based |

## Next Steps

- [Using Tools](using-tools.md) - Local tool patterns
- [Creating Networks](creating-networks.md) - Network configuration
- [API Reference: MCP](../api/mcp/index.md) - Complete MCP API
