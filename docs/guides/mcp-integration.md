# MCP Integration

RobotLab connects robots to Model Context Protocol (MCP) servers through
ruby_llm's built-in client, `RubyLLM::MCP`. A server is described once, as a
config Hash or a `RubyLLM::MCP` subclass, and gives a robot the server's tools,
resources and prompts.

## What RobotLab adds

ruby_llm 2.1 ships the whole MCP client: stdio and Streamable HTTP transports,
tools, resources, prompts, OAuth, input requests (elicitation), long-running
tasks and approval gating. RobotLab adds only what a robot needs on top:

| Piece | Purpose |
|-------|---------|
| `RobotLab::MCP.build(spec)` | Turns a config Hash (the shape used in templates, `RunConfig#mcp` and `RobotLab.build(mcp: [...])`) into a `RubyLLM::MCP` instance; passes instances and subclasses through |
| `RobotLab::MCP::Server` | The `RubyLLM::MCP` subclass those hashes become; adds a `description` (for discovery) and `connected?` |
| `RobotLab::MCP::Registry` | Holds a robot's servers by name so repeated runs reuse one connection (and one stdio process) per server |
| `Robot#mcp`, `#with_mcp`, `#connect_mcp!`, `#mcp_tools`, `#mcp_failures`, `#disconnect` | The robot-side API |
| Per-run `mcp:` / `tools:` | Selects which servers and tools a given run sends to the model |
| `tool_approval:`, `on_tool_approval:`, `on_input_request:` | Settle what ruby_llm pauses a run for |

Everything else (`server.tools`, `server.call`, `server.resources`,
`server.prompt`, OAuth) is ruby_llm's API, reached through `robot.mcp[:name]`.

## Configuring Servers

### As a config Hash

```ruby
filesystem = {
  name:        "filesystem",
  description: "Read, write, and search files under the project directory",
  transport: {
    type:    "stdio",
    command: "npx",
    args:    ["-y", "@modelcontextprotocol/server-filesystem", "."]
  },
  timeout: 60,
  only:    %w[read_text_file list_directory search_files]
}

robot = RobotLab.build(
  name:          "coder",
  system_prompt: "You answer questions about the project files.",
  mcp:           [filesystem]
)
```

The keys the factory understands:

| Key | Maps to | Notes |
|-----|---------|-------|
| `name` | server name | **Required.** Raises `MCPError` when missing or blank |
| `description` | `Server.description` | Scored by [server discovery](#server-discovery) |
| `transport` | see below | A nested Hash, a type String (`"stdio"`), or a transport object |
| `command`, `args`, `env`, `directory` / `cwd` | stdio | `command` may be a String or an Array; `args` are appended |
| `url`, `headers`, `bearer_token`, `oauth` | Streamable HTTP | `oauth: true` enables ruby_llm's defaults; a Hash passes settings |
| `timeout` | `timeout` | Seconds; values of 1000 or more are read as milliseconds; minimum 1. Absent means ruby_llm's `request_timeout` |
| `prefix` | `prefix` | Renames tools `prefix_name`; resolves name clashes between servers |
| `only`, `except` | `only`, `except` | Tool name allowlist / denylist, applied by the server object |
| `requires_approval` | `requires_approval` | `true` (every tool), an Array of names, or `{ if: :destructive? }` |
| `defer` | `defer` | `true` or an Array of names: keep those tools out of the model's context until the provider's tool search loads them |
| `log_level`, `input_requests`, `extensions` | same-named DSL | `extensions` takes a list (`["tasks"]`) or a Hash of settings |

`topics`, `independent`, `group`, `session_id` and `auth_provider` are ignored
without comment (hosts use them for their own grouping). Any other unknown key
is ignored and logged once at `debug`.

Transport keys may sit inside `transport:` or flat at the top level, and the
type is inferred from `command` (stdio) or `url` (Streamable HTTP) when
`transport.type` is absent. These three are equivalent:

```ruby
{ name: "fs", transport: { type: "stdio", command: "npx", args: ["-y", "server-fs", "."] } }
{ name: "fs", transport: "stdio", command: "npx", args: ["-y", "server-fs", "."] }
{ name: "fs", command: "npx", args: ["-y", "server-fs", "."] }
```

A remote server:

```ruby
{
  name: "linear",
  transport: { type: "streamable-http", url: "https://mcp.linear.app/mcp" },
  headers: { "X-Team" => "core" },
  bearer_token: ENV["LINEAR_TOKEN"]
}
```

`streamable-http`, `streamable_http`, `http` and `https` all mean Streamable
HTTP. ruby_llm requires `https` for anything other than a loopback address.

> [!WARNING]
> ruby_llm provides **stdio and Streamable HTTP only**. A config with
> `type: "sse"`, `"ws"` or `"websocket"` raises `RobotLab::MCPError` when the
> server is built (at `connect_mcp!`, `with_mcp`, or the first run that selects
> it), with a message pointing at the server's Streamable HTTP endpoint. Hash
> specs are not validated by `RobotLab.build` itself.

### As a `RubyLLM::MCP` subclass

Anything ruby_llm's class DSL offers works on a robot. Pass the class (one
instance per robot) or an instance (shared):

```ruby
class GitHub < RubyLLM::MCP
  command "github-mcp-server", "stdio"
  env GITHUB_PERSONAL_ACCESS_TOKEN: ENV["GITHUB_PERSONAL_ACCESS_TOKEN"]
  only "search_repositories", "get_file_contents", "create_issue"
  requires_approval if: :destructive?
end

robot = RobotLab.build(name: "dev", mcp: [GitHub])
robot.mcp[:git_hub]   # the GitHub instance; the name is derived from the class name
```

Subclass `RobotLab::MCP::Server` instead when you want the `description`
macro that discovery reads:

```ruby
class Brew < RobotLab::MCP::Server
  description "Install, update, and manage macOS packages via Homebrew"
  command "mcp-server-brew"
end
```

A Hash, an instance and a class can be mixed in one `mcp:` Array.

### In template front matter

```markdown title="prompts/github_assistant.md"
---
description: GitHub assistant with MCP tool access
mcp:
  - name: github
    transport: stdio
    command: npx
    args: ["-y", "@modelcontextprotocol/server-github"]
---
You are a helpful GitHub assistant with access to GitHub tools via MCP.
```

```ruby
robot = RobotLab.build(template: :github_assistant)
robot.run("What are the open issues?", mcp: :inherit, tools: :inherit)
```

Both the flat form above and a nested `transport:` mapping are accepted. A
constructor `mcp:` other than `:none` overrides the front matter list.

### In networks

A task's `mcp:` reaches the robot as its **runtime** value for that run, so
`tools:` must be set too or the MCP tools are not sent:

```ruby
network = RobotLab.create_network(name: "dev_pipeline") do
  task :planner, planner_robot, depends_on: :none
  task :coder,   coder_robot,   depends_on: [:planner],
       mcp:   [filesystem],
       tools: :inherit
end
```

A network-level `config:` with `mcp:` acts as the parent that a robot's
build-time `mcp: :inherit` resolves against. See
[Network-Wide Tool and MCP Defaults](creating-networks.md#network-wide-tool-and-mcp-defaults).

### Hierarchical resolution

`mcp:` resolves through **runtime > robot build > network > global config**;
each level is `:none`, `:inherit`, or an Array of specs:

```
Global (RobotLab.config.mcp)
  -> Network (network config: / task config:)
    -> Robot (mcp: :inherit | :none | [...])
      -> Runtime (robot.run("msg", mcp: [...]), and task mcp: [...])
```

## Per-Run Selection

`run` defaults to `mcp: :none, tools: :none`, which sends the model **no
tools at all**. Each run attaches exactly the selected servers' tools to the
chat (through `with_tools`), so the per-run `tools:` allowlist, the `max_tools`
cap and `:none` apply to MCP tools exactly as to local ones.

```ruby
robot = RobotLab.build(name: "bot", mcp: [filesystem], local_tools: [calculator])

robot.run("hi")                                   # zero tools; no server contacted
robot.run("hi", mcp: :inherit, tools: :inherit)   # calculator + every filesystem tool
robot.run("hi", mcp: :none,    tools: :inherit)   # calculator only; server stays registered and connected
robot.run("hi", mcp: :inherit, tools: %w[list_directory calculator])  # allowlist across both
robot.run("hi", mcp: [github], tools: :inherit)   # a server first seen at run time is registered and connected now
```

Points worth knowing:

- Servers connect lazily, on the first run that selects them (or on
  `connect_mcp!`). A Hash spec builds one server object on first use and reuses
  it on every later run: one stdio process per server, not one per run.
- `:none` on a later run detaches the MCP tools for that call only. The server
  stays in `robot.mcp` and stays connected.
- Two tools with the same name (a local tool and an MCP tool, or two servers)
  raise `RobotLab::MCPError` naming the duplicate; give one server a `prefix:`.
- Tools a server declares with `defer:` are attached deferred
  (`robot.chat.deferred_tools`), the rest normally.
- `tools:` entries match `tool.name`, which for an MCP tool is
  `"#{prefix}_#{server_tool_name}"` when a prefix is set.

> [!IMPORTANT]
> For a **standalone** robot leave build-time `tools:` unset and pass
> `:inherit` (or an allowlist) on the run. Build-time `:inherit` resolves
> against the parent level, which standalone is the global `:none`. Inside a
> network whose `config:` sets `tools:`/`mcp:`, build-time `:inherit` is how a
> robot opts in.

## The Registry: `robot.mcp`

`robot.mcp` is a `RobotLab::MCP::Registry`, an `Enumerable` of `RubyLLM::MCP`
instances keyed by name:

```ruby
robot.mcp.names            # => ["filesystem", "git_hub"]
robot.mcp[:filesystem]     # => the RubyLLM::MCP instance
robot.mcp.key?("github")   # => false
robot.mcp.each { |server| puts server.name }
robot.mcp.delete(:filesystem)   # closes and forgets one server
```

`with_mcp(*servers)` registers more servers (Hashes, instances or classes in
any mix) and returns the robot; registering a spec already known returns the
same server, so hosts may call it on every request. `with_mcp(nil)` closes and
forgets every server.

```ruby
recruit.with_mcp(*chief.mcp)   # share the chief's server instances
```

Registered servers are available to runs that select them through the `mcp:`
cascade; registration alone does not put tools in front of the model.

## Eager Connection and Failures

### `connect_mcp!`

Registers the build-time servers and lists each one's tools now, so status
can be shown before the first run:

```ruby
robot = RobotLab.build(name: "assistant", mcp: [github, filesystem])
robot.connect_mcp!

robot.mcp.names                 # => ["github", "filesystem"]
robot.failed_mcp_server_names   # => ["filesystem"]   (if it could not be reached)
robot.mcp_failures              # => { "filesystem" => #<Errno::ENOENT ...> }
robot.mcp_tools.size            # tools of every registered server (connects as needed)
```

`connect_mcp!` only opens connections. A later plain `run()` still sends zero
tools; `mcp: :inherit, tools: :inherit` on the run is what sends them.

### Connection failures are not raised

A server that cannot be reached while listing tools (any of
`RobotLab::MCP::CONNECT_ERRORS`: `RubyLLM::Error`, `RubyLLM::ConfigurationError`,
`SystemCallError`, `IOError`, `ArgumentError`) is:

- logged at `warn` through `RobotLab.config.logger`
  (`Robot 'bot' could not reach MCP server 'filesystem': Errno::ENOENT: ...`),
- recorded in `robot.mcp_failures` (name => exception) and
  `robot.failed_mcp_server_names`,
- skipped for this run; the other servers' tools are still sent.

It is retried on the next run that selects it and leaves the failure list once
it answers:

```ruby
robot.run("first",  mcp: :inherit, tools: :inherit)  # github connects, filesystem fails
# ... filesystem comes back ...
robot.run("second", mcp: :inherit, tools: :inherit)  # filesystem retried and connects
```

`robot.to_h` reports `mcp_servers:` (registered names) and, when any server
failed, `mcp_failed:`.

### `disconnect`

```ruby
robot.disconnect   # closes every server (stopping stdio processes) and the bus channel
```

Servers stay registered and reconnect on their next use. Call `disconnect`
when a robot is done so stdio child processes do not outlive it.

## Approvals, Input Requests and Tasks

ruby_llm pauses a run when a tool call requires approval, when a server asks
the user for input, or when a server runs a call as a long-running task.
RobotLab settles all three inside `run`, so a run never returns half-finished.

### Approvals

Tools a server marks with `requires_approval` (in a Hash config or the class
DSL) are **denied by default**, with a warning naming the two settings that
allow them. The model sees `{ error: "The user denied the <tool> tool call." }`
and carries on.

```ruby
# Allow every approval-gated tool to run unattended
robot = RobotLab.build(name: "bot", mcp: [GitHub], tool_approval: :approve)

# Or decide per call; the Proc receives a RubyLLM::ToolCall, truthy approves
robot = RobotLab.build(
  name: "bot",
  mcp:  [GitHub],
  on_tool_approval: ->(call) { call.name != "create_issue" || ask_the_user(call) }
)
```

`tool_approval` (`:deny` default, `:approve`) and `on_tool_approval` are also
`RunConfig` fields, so they can come from `config:`. When both are given the
Proc decides.

### Input requests (elicitation)

A server may ask for input mid-call: a **form** request lists `fields`, a
**URL** request asks the user to visit `url`. `on_input_request:` receives the
`RubyLLM::MCP::InputRequest`:

```ruby
robot = RobotLab.build(
  name: "deployer",
  mcp:  [deploy_server],
  on_input_request: lambda { |request|
    request.message            # => "Which environment?"
    request.fields.map(&:name) # => ["environment"]
    { environment: "staging" } # a Hash of field values answers a form request
  }
)
```

Return a Hash to answer a form request, `true` to accept a URL request
(after sending the user to `request.url`), and anything else to decline.
Without a handler every request is declined, with a warning.

### Long-running tasks

When a server runs a tool call as a task, `run` polls at the task's
`poll_interval` until it finishes. A run waits at most
`Robot::ToolCallGating::MCP_TASK_TIMEOUT` (300 s) for its tasks, then raises
`RobotLab::MCPError` with `retryable: true`.

## Server Discovery

When a robot has many servers configured, `mcp_discovery: true` narrows the
selected servers to those relevant to each message before connecting:

```ruby
robot = RobotLab.build(
  name: "assistant",
  mcp_discovery: true,
  mcp: [
    { name: "filesystem", description: "Read, write, and search local files and directories",
      transport: { type: "stdio", command: "mcp-server-filesystem" } },
    { name: "github",     description: "GitHub repos, issues, pull requests, code search",
      transport: { type: "stdio", command: "mcp-server-github" } },
    { name: "brew",       description: "Install, update, and manage macOS packages via Homebrew",
      transport: { type: "stdio", command: "mcp-server-brew" } }
  ]
)

robot.run("install imagemagick via homebrew", mcp: :inherit, tools: :inherit)  # brew only
robot.run("read my config file",              mcp: :inherit, tools: :inherit)  # filesystem only
```

Discovery runs on **every** run that selects servers (not just the first).
Servers skipped for one message stay registered and connected for the next.
`MCP::ServerDiscovery.select(query, from:, threshold:)` scores the message
against each server's `name + description` with TF cosine similarity and keeps
those at or above `DEFAULT_THRESHOLD` (0.05). Candidates may be Hashes,
`RubyLLM::MCP` instances or classes; a class or instance contributes its
`description` when it responds to one (`RobotLab::MCP::Server` does).

All servers are returned unchanged when no server has a description, the
query is blank, nothing clears the threshold, or the optional `classifier` gem
is not installed. Scoring is lexical: write descriptions with the words your
prompts will actually use. When the run's message is an MCP prompt, the
prompt's message contents are what discovery scores.

## Resources and Prompts

There are no wrappers. `robot.mcp[:name]` is the `RubyLLM::MCP` instance with
the full protocol surface:

```ruby
server = robot.mcp[:github]

server.tools                      # => [RubyLLM::MCP::Tool, ...]
server.instructions               # the server's usage notes, or nil
server.version                    # the version the server reports
server.call(:search_issues, query: "flaky")   # => RubyLLM::MCP::Result (text, structured, error?)

server.resources                  # => [RubyLLM::MCP::Resource, ...]
server.resource("file:///project/README.md")
server.resource_templates
server.prompts                    # => [RubyLLM::MCP::Prompt, ...]
```

A server prompt can be run directly; `Robot#run` accepts a
`RubyLLM::MCP::Prompt` in place of a String:

```ruby
robot.run(server.prompt("code_review", code: diff), mcp: :inherit, tools: :inherit)
```

`RunHookContext#request` is then the Prompt rather than a String. Learnings
(`robot.learn`) are not injected into a Prompt request.

OAuth servers (`oauth:` in a Hash, `oauth` in the DSL) expose ruby_llm's flow
on the same object: `authorized?`, `authorization_url(redirect_uri:)`,
`authorize(params)`, `deauthorize`. Credentials persist through
`RubyLLM.config.mcp_credential_store`.

## Hooks and MCP Tools

MCP tools are `RubyLLM::MCP::Tool` instances, not `RobotLab::Tool`s, so the
robot runs the `:tool_call` hook family around the chat's execution of them.
`ToolCallHookContext` carries the owning server:

```ruby
class ToolAudit < RobotLab::Hook
  self.namespace = :global

  def self.around_tool_call(ctx)
    if ctx.mcp?
      RobotLab.config.logger.info "#{ctx.mcp_server.name}: #{ctx.tool_name} #{ctx.tool_args}"
    end
    yield
  end
end

RobotLab.on(ToolAudit)
```

`ctx.mcp_server` is `nil` (and `ctx.mcp?` false) for local tools.
`robot.mcp_server_for(tool)` answers the same question outside a hook. The
`on_tool_call:` / `on_tool_result:` callbacks fire for MCP tools as for any
other.

A `RubyLLM::MCP::Error` raised mid-call (the server went away, a transport
timeout) does not abort the run: the hook context's `tool_error` is set and the
model receives `{ error: "<tool name>: <message>" }` as the tool result.

## Error Handling

| Situation | What happens |
|-----------|--------------|
| Spec with no `name`, no `command`/`url`, an unknown or unsupported (`sse`/`ws`) transport, or a non-`RubyLLM::MCP` class | `RobotLab::MCPError` raised when the server is built: at `connect_mcp!`, `with_mcp`, or the first run that selects it |
| Server unreachable while listing tools | Rescued per server, logged at `warn`, recorded in `mcp_failures`; the run continues without it and retries next time |
| Two tools share a name | `RobotLab::MCPError` from `run`, suggesting `prefix:` |
| `RubyLLM::MCP::Error` during a tool call | Becomes an `{ error: }` tool result; the run continues |
| Long-running task past 300 s | `RobotLab::MCPError` with `retryable: true` |
| Direct calls such as `server.tools` or `server.call` | Raise ruby_llm's errors to you (`RubyLLM::MCP::Error`, `Errno::*`, ...); nothing is swallowed outside a robot run |

`RobotLab::Errors.retryable?` treats a `RubyLLM::MCP::Error` with no JSON-RPC
`code` (the transport failed) as retryable and one with a code (the server
answered and rejected the request) as not.

## Migrating from 0.3

0.4 replaces robot_lab's own MCP client with ruby_llm's. There is no
compatibility layer.

| 0.3 | 0.4 |
|-----|-----|
| `RobotLab.build(mcp_servers: [...])` | `RobotLab.build(mcp: [...])` |
| `RobotLab::MCP::Client.new(config)`, `client.connect`, `list_tools`, `call_tool` | `server = RobotLab::MCP.build(config)`; `server.tools`, `server.call(name, **args)` (connects on first use) |
| `RobotLab::MCP::Server.new(name:, transport:, timeout:)` config object | `RobotLab::MCP::Server` is now a `RubyLLM::MCP` subclass; build servers with `RobotLab::MCP.build` |
| `RobotLab::MCP::Transports::*`, `MCP::ConnectionPoller` | Gone. ruby_llm handles stdio and Streamable HTTP; `transport:` may be an object responding to `request`/`notify`/`cancel`/`close` |
| `type: "sse"`, `"ws"`, `"websocket"` | Raise `MCPError`. Use the server's Streamable HTTP endpoint (`https` except loopback) |
| `robot.inject_mcp!(clients:, tools:)` | `robot.with_mcp(*servers)` |
| `robot.mcp_clients`, `robot.mcp_client(name)` | `robot.mcp` (Registry: `names`, `[]`, `each`), `robot.mcp[:name]` |
| `robot.mcp_tools` (cached Array of `RobotLab::Tool`) | `robot.mcp_tools` returns `RubyLLM::MCP::Tool`s and connects as needed |
| `Tool.create(mcp: "name")`, `tool.mcp`, `tool.mcp?` | Gone. Ask `robot.mcp_server_for(tool)` or `ToolCallHookContext#mcp_server` / `#mcp?` |
| `robot.to_h[:mcp_tools]` | Gone; `to_h` has `mcp_servers:` (names) and `mcp_failed:` |
| `VALID_TRANSPORT_TYPES`, `DEFAULT_TIMEOUT` (15 s) | Gone. Timeout defaults to ruby_llm's `request_timeout` |
| Nested `transport:` mapping required in front matter | Flat form (`transport: stdio` plus `command:`/`args:`) now works |
| Approval-gated tools ran | Denied unless `tool_approval: :approve` or `on_tool_approval:` is set |
| `async-http`, `async-websocket` dependencies | Removed. `ruby_llm >= 2.1.1, < 3` is required |

Unchanged: `Robot#run(mcp:, tools:)` semantics, the `:none`/`:inherit`/Array
cascade, `connect_mcp!`, `failed_mcp_server_names`, `disconnect`,
`mcp_discovery`, and the config Hash shape (which now also accepts `prefix`,
`only`, `except`, `requires_approval`, `defer`, `headers`, `bearer_token`,
`oauth`, `directory`, `log_level`, `input_requests`, `extensions`).

Migration sketch for a host that managed connections itself:

```ruby
servers = configs.map { |config| RobotLab::MCP.build(config) }
servers.each do |server|
  server.tools   # eager connect; show a spinner here
rescue *RobotLab::MCP::CONNECT_ERRORS => e
  warn "#{server.name}: #{e.message}"
end

robot.with_mcp(*servers)
robot.run(prompt, mcp: :inherit, tools: :inherit)
```

Logging: robot_lab's warnings go to `RobotLab.config.logger`; ruby_llm's MCP
logs go to `RubyLLM.logger`.

## Next Steps

- [Using Tools](using-tools.md) - Local tool patterns and the `tools:` allowlist
- [Creating Networks](creating-networks.md) - Network and task configuration
- [Hooks](hooks.md) - Observing tool calls
- [API Reference: MCP](../api/mcp/index.md) - Factory, Server and Registry
