# MCP Server

Connecting robots to Model Context Protocol servers for external tool access.

## Overview

This example demonstrates how to connect robots to external MCP servers. MCP servers expose tools that robots can discover and invoke automatically. RobotLab supports stdio, HTTP, WebSocket, and SSE transports.

The runnable version of everything below is
[`examples/04_mcp.rb`](https://github.com/MadBomber/robot_lab/blob/main/examples/04_mcp.rb)
(direct `MCP::Client` usage in Part 1, robot integration in Part 2).

> [!WARNING]
> **Two things are required to actually use MCP tools in a run.** `Robot#run`
> defaults to `mcp: :none, tools: :none`, so build-time `mcp:` servers are never
> connected by a plain `robot.run("...")`. Pass both:
>
> ```ruby
> robot.run("...", mcp: :inherit, tools: :inherit)
> ```
>
> `mcp: :inherit` triggers the connection attempt; `tools: :inherit` is what sends
> the discovered tools to the LLM.

> [!WARNING]
> `transport:` must be a **nested hash**. A flat `transport: stdio` with sibling
> `command:` / `args:` keys raises
> `NoMethodError: undefined method 'transform_keys' for an instance of String`
> internally — and that error is swallowed, so the robot silently builds with zero
> MCP tools. Connection failures are logged and recorded in
> `robot.failed_mcp_server_names`; they are never raised.

## Using MCP with a Robot

The primary pattern is to pass MCP server configurations via `mcp:` or `mcp_servers:` when building a robot:

```ruby
#!/usr/bin/env ruby

require "bundler/setup"
require "robot_lab"

# MCP server configuration (stdio transport)
github_server = {
  name: "github",
  transport: {
    type: "stdio",
    command: "github-mcp-server",
    args: ["stdio"],
    env: {
      "GITHUB_PERSONAL_ACCESS_TOKEN" => ENV.fetch("GITHUB_PERSONAL_ACCESS_TOKEN", "")
    }
  }
}

# Create a robot with MCP server integration
# Tools are automatically discovered when the robot connects
robot = RobotLab.build(
  name: "github_assistant",
  system_prompt: <<~PROMPT,
    You are a GitHub assistant with access to repository tools.
    Help users search repos, manage issues, and explore code.
  PROMPT
  mcp: [github_server],
  model: "claude-sonnet-4"
)

# MCP clients are created lazily. connect_mcp! forces the connection now so the
# counts below are meaningful -- without it both lines print empty results.
robot.connect_mcp!

puts "MCP Servers: #{robot.mcp_clients.keys.join(", ")}"
puts "MCP Tools: #{robot.mcp_tools.size} discovered"
puts "Failed servers: #{robot.failed_mcp_server_names.join(", ")}" if robot.failed_mcp_server_names.any?

# Run the robot -- both kwargs are required for it to reach the MCP tools
result = robot.run(
  "What are the top 3 most starred Ruby web frameworks on GitHub?",
  mcp: :inherit,
  tools: :inherit
)
puts result.last_text_content

# Confirm which tools were sent this turn
puts "Tools sent: #{robot.chat.tools.size}"

# Always disconnect MCP clients when done
robot.disconnect
```

> [!NOTE]
> `result.tool_calls` is effectively always empty — it reads the final assistant
> message, which contains only text once ruby_llm's tool loop has finished. Use the
> `on_tool_call:` callback or the Hook system to observe MCP tool invocations.

## Direct MCP Client Usage

You can also use the MCP client directly without a robot:

```ruby
require "robot_lab"

# Create and connect MCP client
github_server = {
  name: "github",
  transport: {
    type: "stdio",
    command: "github-mcp-server",
    args: ["stdio"],
    env: { "GITHUB_PERSONAL_ACCESS_TOKEN" => ENV["GITHUB_PERSONAL_ACCESS_TOKEN"] }
  }
}

# NOTE: the config is a single POSITIONAL argument.
# MCP::Client.new(name: ..., transport: ...) raises ArgumentError.
client = RobotLab::MCP::Client.new(github_server)
client.connect

if client.connected?
  # List available tools
  tools = client.list_tools
  tools.each do |tool|
    puts "#{tool[:name]}: #{tool[:description]}"
  end

  # Call a tool directly
  result = client.call_tool("search_repositories", {
    query: "language:ruby stars:>1000",
    per_page: 5
  })

  puts JSON.pretty_generate(result)

  client.disconnect
end
```

## Multiple MCP Servers

A robot can connect to multiple MCP servers simultaneously:

```ruby
filesystem_server = {
  name: "filesystem",
  transport: {
    type: "stdio",
    command: "npx",
    args: ["@modelcontextprotocol/server-filesystem", "/data"]
  }
}

github_server = {
  name: "github",
  transport: {
    type: "stdio",
    command: "github-mcp-server",
    args: ["stdio"],
    env: { "GITHUB_PERSONAL_ACCESS_TOKEN" => ENV["GITHUB_PERSONAL_ACCESS_TOKEN"] }
  }
}

robot = RobotLab.build(
  name: "developer",
  system_prompt: "You help with coding tasks using GitHub and the filesystem.",
  mcp: [filesystem_server, github_server],
  model: "claude-sonnet-4"
)

result = robot.run(
  "Search for Ruby repos with CI configs and list their workflow files",
  mcp: :inherit,
  tools: :inherit
)
puts result.last_text_content

robot.disconnect
```

## MCP in Networks

`mcp` and `tools` are the only two fields a network passes down to its member
robots. Declare them **per task** — the `task` DSL is what reliably reaches the
robot's `run` call.

```ruby
# Create robots -- leave mcp:/tools: unset in the constructor
data_analyst = RobotLab.build(
  name: "data_analyst",
  system_prompt: "You analyze data."
)

file_manager = RobotLab.build(
  name: "file_manager",
  system_prompt: "You manage files."
)

# Per-task MCP + tools configuration
network = RobotLab.create_network(name: "support_with_mcp") do
  task :data_analyst, data_analyst,
       mcp: [github_server],
       tools: :inherit,                       # send everything discovered
       depends_on: :none

  task :file_manager, file_manager,
       mcp: [filesystem_server],
       tools: %w[read_file list_directory],   # allowlist only these tool names
       depends_on: :optional
end

result = network.run(message: "Analyze the project structure")
```

> [!WARNING]
> Build-time `:inherit` cuts both ways, so scope it deliberately.
>
> For a **standalone** robot it is a trap: `:inherit` resolves against the global
> level (`:none`), yielding an allowlist of `["none"]` that matches nothing, so the
> robot sends no tools no matter what you pass at run time.
>
> Inside a **network**, build-time `:inherit` is exactly how a robot opts into the
> network's `config:` list — the parent is resolved at run time from
> `network_config`. Verified with a network `config:` of `tools: %w[ReadFile]` on a
> robot holding `ReadFile` and `ListDir`:
>
> | Robot constructor | Task line | Tools sent |
> |---|---|---|
> | `tools: :inherit` | `tools: :inherit` | `[:read_file]` — network allowlist applied |
> | (unset) | `tools: :inherit` | `[:read_file, :list_dir]` — allowlist ignored |
>
> A network-level `config:` also propagates *only* `mcp` and `tools`. LLM fields
> (`model`, `temperature`, `max_tokens`, ...) and callbacks (`on_content`) are read
> from each robot's own config at construction time and are never inherited from
> the network.

## Transport Types

The `type:` field must be one of `stdio`, `sse`, `ws`, `websocket`,
`streamable-http`, or `http`. Anything else raises `ArgumentError` — note that
`streamable_http` with an underscore is **not** valid.

`timeout:` sits alongside `transport:` on the server config and defaults to 15
seconds. It is normalized: `nil` becomes 15, any value of 1000 or more is treated
as milliseconds (5000 → 5.0s), and anything under 1 second is floored to 1.

> [!NOTE]
> Only the stdio transport actually enforces `timeout`. The SSE, WebSocket, and
> StreamableHTTP transports store the value and never reference it.

## HTTP Transport

Connect to remote MCP servers over HTTP. Requires the `async-http` gem.

```ruby
robot = RobotLab.build(
  name: "remote_assistant",
  system_prompt: "You have access to remote tools.",
  mcp: [
    {
      name: "remote_api",
      timeout: 30,
      transport: {
        type: "http",
        url: "https://mcp.example.com/mcp",
        # Auth is supplied by a callable, not a headers hash
        auth_provider: -> { "Bearer #{ENV['MCP_TOKEN']}" }
      }
    }
  ]
)

result = robot.run("Use the remote tools to check system status", mcp: :inherit, tools: :inherit)
robot.disconnect
```

> [!WARNING]
> A `headers:` key in a streamable-http transport config is **silently discarded**.
> The transport builds its own header hash on every request and only merges in
> `Authorization` when `auth_provider` is set. Use `auth_provider:` (a proc
> returning the full header value) for authentication.

> [!WARNING]
> The HTTP and SSE transports set `@connected = true` *before* the MCP
> initialization handshake completes, so `connected?` returns `true` even against
> an unreachable host. Treat it as "a connect was attempted", not "the server
> answered", and check `robot.failed_mcp_server_names` as well.

## WebSocket Transport

For real-time bidirectional communication. Requires the `async-websocket` gem.

```ruby
robot = RobotLab.build(
  name: "realtime_assistant",
  system_prompt: "You monitor real-time events.",
  mcp: [
    {
      name: "realtime",
      transport: {
        type: "websocket",
        url: "ws://localhost:8765"
      }
    }
  ]
)

result = robot.run("Subscribe to the events channel", mcp: :inherit, tools: :inherit)
robot.disconnect
```

> [!CAUTION]
> The WebSocket transport currently raises `NameError` on
> `Async::HTTP::Endpoint` inside an un-awaited `Async` block. It is not usable as
> shipped — prefer stdio or HTTP.

## SSE Transport

Server-Sent Events transport. Requires the `async-http` gem.

```ruby
robot = RobotLab.build(
  name: "sse_assistant",
  system_prompt: "You have access to streaming tools.",
  mcp: [
    {
      name: "streaming_api",
      transport: {
        type: "sse",
        url: "https://api.example.com/sse"
      }
    }
  ]
)

result = robot.run("Stream the latest metrics", mcp: :inherit, tools: :inherit)
robot.disconnect
```

## Runtime MCP Selection

`mcp:` and `tools:` on `robot.run` decide, per call, what the LLM sees:

```ruby
robot = RobotLab.build(
  name: "flexible_bot",
  system_prompt: "You use available tools.",
  mcp: [github_server]
)

# Connect the configured MCP servers and send their tools
result = robot.run("Search for Ruby repos", mcp: :inherit, tools: :inherit)

# The DEFAULT: no MCP connection, no tools sent. Writing these out is
# redundant -- omitting both kwargs does exactly the same thing.
result = robot.run("Just answer from your knowledge")

# Connect MCP but send only two named tools
result = robot.run(
  "List the open issues",
  mcp: :inherit,
  tools: %w[list_issues get_issue]
)

robot.disconnect
```

> [!NOTE]
> `tools:` is a **name allowlist** across every available tool — local and MCP
> alike. `tools: :none` means "zero tools of any kind", not "MCP only"; there is no
> switch that selects local tools versus MCP tools.

## Running

```bash
# Set API keys
export ANTHROPIC_API_KEY="your-key"
export GITHUB_PERSONAL_ACCESS_TOKEN="your-token"

# Install MCP server (example: GitHub)
brew install github-mcp-server

# Direct MCP::Client usage + robot integration
ruby examples/04_mcp.rb

# Semantic MCP server selection (no LLM calls)
ruby examples/28_mcp_discovery.rb
```

## Key Concepts

1. **MCP Configuration**: Pass server configs via `mcp:` / `mcp_servers:` on `RobotLab.build` or `Robot.new`. `transport:` must be a nested hash
2. **Nothing is sent by default**: `run` defaults to `mcp: :none, tools: :none`. Pass `mcp: :inherit, tools: :inherit` to connect and send
3. **Lazy connection**: MCP clients are created on the first qualifying `run`. Call `robot.connect_mcp!` to connect eagerly — before that, `mcp_clients` and `mcp_tools` are empty
4. **Failures are silent**: connection errors are logged and recorded in `robot.failed_mcp_server_names`, never raised
5. **Transport Types**: `stdio`, `sse`, `ws`, `websocket`, `streamable-http`, `http` (`streamable_http` is invalid)
6. **Tool Filtering**: `tools:` is an allowlist over local *and* MCP tools combined; entries must match how each tool was attached (class-attached → `"ReadFile"`, instance-attached → `"read_file"`)
7. **Networks**: an explicit list on the `task` line applies directly; to inherit the network's `config:` list instead, build the robot with `tools: :inherit` *and* pass `tools: :inherit` on the task
8. **Cleanup**: Always call `robot.disconnect` when done to release MCP connections

## See Also

- [MCP Integration Guide](../guides/mcp-integration.md)
- [MCP API Reference](../api/mcp/index.md)
- [Transports](../api/mcp/transports.md)
