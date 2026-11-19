# MCP (Model Context Protocol)

Integration with MCP servers for tools, resources and prompts.

## Overview

MCP allows robots to connect to external servers that provide tools, resources
and prompts. RobotLab uses ruby_llm's built-in client (`RubyLLM::MCP`, stdio and
Streamable HTTP) and adds a config-Hash factory, a per-robot registry, per-run
tool selection, and settlement of approvals, input requests and tasks.

```ruby
robot = RobotLab.build(
  name: "developer",
  system_prompt: "You help with coding tasks.",
  mcp: [
    {
      name: "filesystem",
      transport: {
        type: "stdio",
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-filesystem", "/data"]
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
| [Factory](factory.md) | `RobotLab::MCP.build` / `define` / `name_of` / `seconds`: config Hash to `RubyLLM::MCP` |
| [Server](server.md) | `RobotLab::MCP::Server < RubyLLM::MCP`: adds `description` and `connected?` |
| [Registry](registry.md) | `RobotLab::MCP::Registry`: a robot's servers by name, reused across runs |
| `MCP::ServerDiscovery` | Picks the relevant subset of configured servers for a message (see [Server Discovery](#server-discovery)) |
| [Robot MCP methods](../core/robot.md#mcp) | `mcp`, `with_mcp`, `connect_mcp!`, `mcp_tools`, `mcp_failures`, `failed_mcp_server_names`, `mcp_server_for`, `disconnect` |

## Quick Start

### Using MCP with a Robot

Pass server specs via `mcp:`. A spec is a config Hash, a `RubyLLM::MCP`
instance, or a `RubyLLM::MCP` subclass, mixed freely:

```ruby
class GitHub < RubyLLM::MCP
  command "github-mcp-server", "stdio"
  env GITHUB_PERSONAL_ACCESS_TOKEN: ENV["GITHUB_PERSONAL_ACCESS_TOKEN"]
  requires_approval if: :destructive?
end

robot = RobotLab.build(
  name: "assistant",
  template: :assistant,
  mcp: [GitHub, { name: "fs", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "."] }],
  tool_approval: :approve
)

result = robot.run("List my open pull requests", mcp: :inherit, tools: :inherit)
result.last_text_content
```

### Connecting at Run Time

`Robot#run` defaults to `mcp: :none, tools: :none`. Those defaults mean "send
zero tools for this turn", so a bare `robot.run("...")` reaches the LLM with
**no** tools attached and contacts **no** server, even when `mcp:` was supplied
at build time.

```ruby
robot.run("...")                                  # no MCP, no tools
robot.run("...", tools: :inherit)                 # attached local tools only
robot.run("...", mcp: :inherit, tools: :inherit)  # the robot's servers AND their tools
robot.run("...", mcp: :inherit, tools: %w[read_text_file])   # allowlist across local + MCP
```

Servers connect on the first run that selects them and stay connected; a later
`mcp: :none` run detaches their tools for that call without closing anything.

!!! warning "Build-time `:inherit` depends on whether there is a parent"
    The parent level is recomputed on **every run** as
    `network_config&.mcp || network_parent_config(network)&.mcp || RobotLab.config.mcp`,
    then the build-time value is resolved against it, then the runtime value
    against *that*.

    - For a **standalone** robot the parent is the global default `:none`, so a
      build-time `mcp: :inherit` / `tools: :inherit` collapses to nothing. Give
      the standalone robot an explicit array at build time and pass `:inherit`
      at run time.
    - **Inside a network** whose `config:` sets `mcp:`/`tools:`, build-time
      `:inherit` is exactly how a robot opts in to the network's list — see
      [MCP in Networks](#mcp-in-networks) below.

`robot.connect_mcp!` connects eagerly, but a later plain `run()` still sends no
tools. Connection failures are logged, recorded in `robot.mcp_failures` /
`robot.failed_mcp_server_names`, and retried on the next run that selects the
server — they are not raised.

### MCP in Networks

A robot can inherit its MCP server list from the network's `config:`. This is one
of only two fields (`mcp` and `tools`) that a network-level `RunConfig`
propagates to member robots, and only when the robot opts in with `:inherit`:

```ruby
network = RobotLab.create_network(
  name: "dev",
  config: RobotLab::RunConfig.new(mcp: [GitHub])
) do |n|
  n.task :assistant,
         RobotLab.build(name: "assistant", template: :assistant, mcp: :inherit),
         mcp: :inherit, tools: :inherit
end
```

`Network#task` has the same `mcp: :none, tools: :none` defaults as `Robot#run`,
so the task must opt in as well. A task's own `mcp:` Array reaches the robot as
its runtime value.

LLM fields (`model`, `temperature`, ...) and callbacks are **not** inherited from
a network config; each robot reads those from its own configuration.

### Direct Server Usage

A server works on its own, without a robot:

```ruby
server = RobotLab::MCP.build(
  name: "filesystem",
  transport: { type: "stdio", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/data"] }
)

server.tools.map(&:name)                              # connects on first use
server.call(:read_text_file, path: "/data/config.yml").text
server.resources
server.close
```

Through a robot, the same object is `robot.mcp[:filesystem]`.

### Server Discovery

When a robot is built with `mcp_discovery: true`, the servers a run selects are
narrowed before connecting: `MCP::ServerDiscovery` scores each server's
`name + description` against the message using term-frequency cosine
similarity and keeps the servers scoring at or above the threshold
(`DEFAULT_THRESHOLD` = 0.05). This happens on every run.

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

# Selects only the "brew" server for this message
robot.run("install imagemagick", mcp: :inherit, tools: :inherit)
```

Candidates may be Hashes, `RubyLLM::MCP` instances or classes (`description`
is read from each when it has one — `RobotLab::MCP::Server` does). Discovery
falls back to the **full** list when no server has a description, when the
query is blank, when no server clears the threshold, or when the optional
`classifier` gem is unavailable.

## Transport Types

| `type:` | Transport | Notes |
|---------|-----------|-------|
| `stdio` (or absent with `command`) | Local subprocess | `command`, `args`, `env`, `directory`/`cwd` |
| `streamable-http`, `streamable_http`, `http`, `https` (or absent with `url`) | Streamable HTTP | `url`, `headers`, `bearer_token`, `oauth`; `https` required except on loopback |
| `sse`, `ws`, `websocket` | **Unsupported** | Raise `RobotLab::MCPError` when the server is built |
| an object responding to `request` and `close` | Custom | Installed directly (tunnels, in-process test transports) |

## MCP Parameter Values

The `mcp:` parameter on a Robot, a task, or a `RunConfig` accepts:

| Value | Meaning |
|-------|---------|
| `:none` | No MCP servers (explicitly disabled) |
| `:inherit` | Resolve against the parent level (network config, then global config) |
| `Array` | Explicit list of specs: config Hashes, `RubyLLM::MCP` instances, `RubyLLM::MCP` subclasses |

The full config-Hash key table is on the [Factory](factory.md#config-hash-keys)
page. In short: `name` is required; `transport` may be nested or flat; stdio
takes `command`/`args`/`env`/`directory`; Streamable HTTP takes
`url`/`headers`/`bearer_token`/`oauth`; `timeout`, `prefix`, `only`, `except`,
`requires_approval`, `defer`, `log_level`, `input_requests`, `extensions` and
`description` are optional.

## Approvals, Input Requests, Tasks

ruby_llm pauses a run for tool calls that require approval, for a server's
input requests, and for long-running tasks. `Robot#run` settles them before it
returns:

| Setting | Default | Effect |
|---------|---------|--------|
| `tool_approval:` | `:deny` | `:approve` lets approval-gated tools run; `:deny` refuses them with a warning and an `{ error: }` result for the model |
| `on_tool_approval:` | `nil` | Proc receiving a `RubyLLM::ToolCall`; truthy approves. Takes precedence over `tool_approval` |
| `on_input_request:` | `nil` | Proc receiving a `RubyLLM::MCP::InputRequest`; return a Hash of field values to answer a form request, `true` to accept a URL request, anything else declines. Without it, requests are declined |
| tasks | | Polled at the task's interval; `RobotLab::MCPError` (`retryable: true`) after `Robot::ToolCallGating::MCP_TASK_TIMEOUT` (300 s) |

All three settings are `Robot.new` keywords and `RunConfig` fields.

## Error Handling

| Error | When |
|-------|------|
| `RobotLab::MCPError` | A spec cannot be built (no name, no `command`/`url`, unsupported or unknown transport, not a `RubyLLM::MCP` class); two tools share a name (suggests `prefix:`); a task outlives the timeout |
| Connection failures (`RobotLab::MCP::CONNECT_ERRORS`) | Rescued per server inside a robot: logged at `warn`, recorded in `mcp_failures`, retried next run. Raised to you from direct calls such as `server.tools` |
| `RubyLLM::MCP::Error` during a tool call | Turned into an `{ error: "<tool>: <message>" }` tool result; the run continues |

```ruby
robot = RobotLab.build(name: "t", system_prompt: "hi",
                       mcp: [{ name: "x", transport: { type: "sse", url: "https://x/sse" } }])
robot.connect_mcp!
# RobotLab::MCPError: MCP server 'x' uses transport 'sse', which ruby_llm 2.1 does not provide ...

robot = RobotLab.build(name: "t", system_prompt: "hi",
                       mcp: [{ name: "x", command: "no-such-server" }])
robot.connect_mcp!
# WARN -- : Robot 't' could not reach MCP server 'x': Errno::ENOENT: ...
robot.failed_mcp_server_names  # => ["x"]
```

`RobotLab::Errors.retryable?` treats a `RubyLLM::MCP::Error` without a JSON-RPC
`code` (transport failure) as retryable; one with a code (the server rejected
the request) is not.

## See Also

- [Factory](factory.md)
- [Server](server.md)
- [Registry](registry.md)
- [MCP Integration Guide](../../guides/mcp-integration.md)
