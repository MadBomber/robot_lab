# MCP Server

Connecting a robot to a Model Context Protocol server for external tools.

## Overview

This example talks to the reference filesystem server
(`npx -y @modelcontextprotocol/server-filesystem <dir>`), which needs only Node
and is scoped to the directory you hand it. Part 1 uses the server on its own;
Part 2 gives it to a robot; Part 3 shows the same thing as a `RubyLLM::MCP`
subclass.

The runnable version is
[`examples/04_mcp.rb`](https://github.com/MadBomber/robot_lab/blob/main/examples/04_mcp.rb).

> [!WARNING]
> **Two things are required to actually use MCP tools in a run.** `Robot#run`
> defaults to `mcp: :none, tools: :none`, so build-time `mcp:` servers are never
> selected by a plain `robot.run("...")`. Pass both:
>
> ```ruby
> robot.run("...", mcp: :inherit, tools: :inherit)
> ```
>
> `mcp: :inherit` selects the robot's servers for this turn; `tools:` says which
> tools (local and MCP alike) reach the model.

## The server config

One config Hash is all a server needs. The same shape works in
`RobotLab.build(mcp: [...])`, template front matter, `Network#task(mcp:)`,
`RunConfig#mcp`, and `RobotLab::MCP.build`:

```ruby
require "robot_lab"

filesystem = {
  name:        "filesystem",
  description: "Read, write, and search files under the examples directory",
  transport: {
    type:    "stdio",
    command: "npx",
    args:    ["-y", "@modelcontextprotocol/server-filesystem", __dir__]
  },
  timeout: 60 # seconds; the first npx run downloads the server
}
```

## Part 1: A server on its own

`RobotLab::MCP.build` returns a `RubyLLM::MCP`. It connects lazily, on the
first request:

```ruby
server = RobotLab::MCP.build(filesystem)
tools  = server.tools                    # connects, lists tools

puts "Connected: #{server.name} (protocol #{server.version})"
puts "Instructions: #{server.instructions.lines.first.strip}" if server.instructions

tools.each { |tool| puts "#{tool.name}: #{tool.description.lines.first.strip}" }

# Call a tool directly
result = server.call(:list_directory, path: __dir__)
puts result.error? ? "error: #{result.text}" : result.text

# Resources and prompts are part of the same object. A server that does not
# implement them (the filesystem server implements neither) answers with a
# JSON-RPC "method not found" error, raised as RubyLLM::MCP::Error.
offered = lambda do |label|
  "#{server.public_send(label).size} #{label}"
rescue RubyLLM::MCP::Error => e
  "#{label} not offered (#{e.message})"
end
puts "Resources: #{offered.call(:resources)}"
puts "Prompts:   #{offered.call(:prompts)}"

server.close   # the next request would reconnect
```

Outside a robot run nothing is rescued for you: a missing `npx` raises
`Errno::ENOENT` from `server.tools`, and a protocol failure raises
`RubyLLM::MCP::Error`.

## Part 2: Robot + MCP

```ruby
robot = RobotLab.build(
  name:          "fs_assistant",
  model:         "claude-sonnet-4",
  system_prompt: "You answer questions about files using the tools you are given. Be brief.",
  mcp:           [filesystem],
  tool_approval: :approve
)
```

`mcp:` registers the server with the robot. `tool_approval: :approve` lets
tools a server marks as requiring approval run unattended; the default is
`:deny`, or pass `on_tool_approval:` to decide per call.

Connections are made on the first run that selects a server. `connect_mcp!`
connects now so status can be shown up front:

```ruby
robot.connect_mcp!

puts "MCP servers: #{robot.mcp.names.join(', ')}"            # => filesystem
puts "Failed:      #{robot.failed_mcp_server_names.inspect}"  # => []
puts "MCP tools:   #{robot.mcp_tools.size}"
robot.mcp[:filesystem].tools.size                             # the same RubyLLM::MCP object
```

A connection failure is not raised here: it is logged at `warn`, recorded in
`robot.mcp_failures`, and retried on the next run that selects the server.

Now run. `tools:` takes a name allowlist (or `:inherit` for every tool);
allowlisting keeps the tool schemas small for local models:

```ruby
question = "Which Ruby files in this directory have 'network' in their name? Just list them."

result = robot.run(question, mcp: :inherit, tools: %w[list_directory search_files])

result.output.each { |msg| puts msg.content if msg.respond_to?(:content) }
puts "Tool calls made: #{result.tool_calls.size}" if result.tool_calls.any?

# Closes every server (stopping the npx process); servers stay registered
# and would reconnect on the next run.
robot.disconnect
```

## Part 3: Servers as classes

Anything `RubyLLM::MCP`'s class DSL offers works on a robot too:

```ruby
class GitHub < RubyLLM::MCP
  command "github-mcp-server", "stdio"
  env GITHUB_PERSONAL_ACCESS_TOKEN: ENV["GITHUB_PERSONAL_ACCESS_TOKEN"]
  only "search_repositories", "get_file_contents", "create_issue"
  requires_approval "create_issue"     # paused until approved
end

robot = RobotLab.build(
  name: "dev",
  mcp:  [GitHub],
  on_tool_approval: ->(call) { call.name != "create_issue" || ask_the_user(call) }
)

robot.run("Open an issue about the flaky test", mcp: :inherit, tools: :inherit)
robot.run(robot.mcp[:git_hub].prompt("code_review", code: diff), mcp: :inherit)
```

`requires_approval if: :destructive?` gates every tool the server annotates as
destructive instead of naming them. The registry key for a class is its
ruby_llm default name, derived from the class name (`GitHub` becomes
`git_hub`).

## Multiple servers and name clashes

```ruby
robot = RobotLab.build(
  name: "developer",
  system_prompt: "You help with coding tasks using GitHub and the filesystem.",
  mcp: [filesystem, GitHub]
)

robot.run("Search for Ruby repos with CI configs and list their workflow files",
          mcp: :inherit, tools: :inherit)
robot.disconnect
```

Two servers (or a server and a local tool) offering the same tool name raise
`RobotLab::MCPError` from `run`. Give one a `prefix:` so its tools become
`prefix_name`:

```ruby
{ name: "fs2", prefix: "fs2", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/other"] }
```

## MCP in Networks

`mcp` and `tools` are the only two fields a network passes down to its member
robots. Declare them **per task** — the `task` DSL reaches the robot's `run`
call as its runtime values:

```ruby
data_analyst = RobotLab.build(name: "data_analyst", system_prompt: "You analyze data.")
file_manager = RobotLab.build(name: "file_manager", system_prompt: "You manage files.")

network = RobotLab.create_network(name: "support_with_mcp") do
  task :data_analyst, data_analyst,
       mcp: [GitHub],
       tools: :inherit,                                # send everything discovered
       depends_on: :none

  task :file_manager, file_manager,
       mcp: [filesystem],
       tools: %w[read_text_file list_directory],       # allowlist only these tool names
       depends_on: :optional
end

result = network.run(message: "Analyze the project structure")
```

> [!WARNING]
> Build-time `:inherit` cuts both ways. For a **standalone** robot it resolves
> against the global `:none` and yields nothing, so leave `tools:`/`mcp:` unset
> in the constructor and opt in on the run. Inside a **network** whose `config:`
> supplies `tools:`/`mcp:`, build-time `:inherit` is exactly how a robot opts
> into that list. A network-level `config:` propagates *only* `mcp` and `tools`;
> LLM fields and callbacks are never inherited from the network.

## Remote servers

Streamable HTTP is the other transport ruby_llm provides. `https` is required
except on loopback addresses:

```ruby
robot = RobotLab.build(
  name: "remote_assistant",
  system_prompt: "You have access to remote tools.",
  mcp: [
    {
      name:    "remote_api",
      timeout: 30,
      transport: { type: "streamable-http", url: "https://mcp.example.com/mcp" },
      bearer_token: ENV["MCP_TOKEN"]
    }
  ]
)

result = robot.run("Use the remote tools to check system status", mcp: :inherit, tools: :inherit)
robot.disconnect
```

`sse`, `ws` and `websocket` transports are not available; such a config raises
`RobotLab::MCPError` when the server is built.

## Runtime MCP Selection

`mcp:` and `tools:` on `robot.run` decide, per call, what the LLM sees:

```ruby
robot = RobotLab.build(name: "flexible_bot", system_prompt: "You use available tools.", mcp: [GitHub])

# Select the configured servers and send their tools
robot.run("Search for Ruby repos", mcp: :inherit, tools: :inherit)

# The default: no server contacted, no tools sent
robot.run("Just answer from your knowledge")

# Select the server but send only two named tools
robot.run("List the open issues", mcp: :inherit, tools: %w[list_issues get_issue])

# Detach MCP tools for this call; the server stays registered and connected
robot.run("Summarise what you found", mcp: :none, tools: :inherit)

robot.disconnect
```

> [!NOTE]
> `tools:` is a **name allowlist** across every available tool — local and MCP
> alike. `tools: :none` means "zero tools of any kind", not "MCP only"; there is
> no switch that selects local tools versus MCP tools.

## Running

```bash
# Node.js with npx on PATH (the filesystem server is fetched by npx)
# LM Studio running at localhost:1234 for Part 2 (Part 1 runs without it;
# the example stops with a message if the server is not reachable)

bundle exec ruby examples/04_mcp.rb

# Semantic MCP server selection (no LLM calls)
bundle exec ruby examples/28_mcp_discovery.rb
```

## Key Concepts

1. **One spec shape**: a config Hash, a `RubyLLM::MCP` instance, or a `RubyLLM::MCP` subclass, anywhere `mcp:` is accepted
2. **Nothing is sent by default**: `run` defaults to `mcp: :none, tools: :none`. Pass `mcp: :inherit, tools: :inherit` (or an allowlist)
3. **Lazy connection, reused**: a server connects on the first run that selects it and is reused across runs (one stdio process per server). `connect_mcp!` connects eagerly
4. **Failures are recorded, not raised**: `robot.mcp_failures` / `failed_mcp_server_names`, retried on the next run
5. **Approvals fail closed**: tools marked `requires_approval` are denied unless `tool_approval: :approve` or `on_tool_approval:` says otherwise
6. **Transports**: stdio and Streamable HTTP; `sse`/`ws` raise at build time
7. **Tool filtering**: `tools:` is an allowlist over local *and* MCP tools; MCP tool names carry the server's `prefix:` when one is set
8. **Resources and prompts**: `robot.mcp[:name].resources` / `.prompts`; pass `server.prompt(...)` straight to `robot.run`
9. **Cleanup**: call `robot.disconnect` when done so stdio child processes end

## See Also

- [MCP Integration Guide](../guides/mcp-integration.md)
- [MCP API Reference](../api/mcp/index.md)
- [Factory](../api/mcp/factory.md)
