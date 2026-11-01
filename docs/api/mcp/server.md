# MCP Server

The `RubyLLM::MCP` subclass that `RobotLab::MCP.build` creates from a config Hash.

## Class: `RobotLab::MCP::Server < RubyLLM::MCP`

Everything a server can do comes from ruby_llm: `tools`, `call`, `resources`,
`resource`, `resource_templates`, `prompts`, `prompt`, `instructions`,
`version`, `listen`, `close`, the OAuth flow, and the class-level DSL
(`command`, `url`, `transport`, `env`, `directory`, `header`, `bearer_token`,
`oauth`, `timeout`, `only`, `except`, `prefix`, `tool`, `requires_approval`,
`defer`, `input_requests`, `before_input_request`, `extension`, `log_level`).
This subclass adds only:

- a class-level `description`, used by `MCP::ServerDiscovery` to pick servers
  relevant to a message;
- `connected?`, true once the server has answered a `tools` request and false
  again after `close`.

`RobotLab::MCP.define(config)` returns an anonymous subclass of this class;
`RobotLab::MCP.build(config)` returns an instance of one. Subclass it directly
when you want the description macro:

```ruby
class Brew < RobotLab::MCP::Server
  description "Install, update, and manage macOS packages via Homebrew"
  command "mcp-server-brew"
end

robot = RobotLab.build(name: "ops", mcp: [Brew], mcp_discovery: true)
```

A plain `RubyLLM::MCP` subclass works everywhere a `Server` does; it just has
no description for discovery to score.

## Class Methods

### description

```ruby
Server.description            # => String or nil
Server.description("text")    # => "text"
```

Sets or reads a short description of what the server offers. Inherited by
subclasses (a subclass may override it).

## Instance Methods

### description

```ruby
server.description  # => String
```

The class-level description, or `""` when none was set.

### connected?

```ruby
server.connected?  # => Boolean
```

Whether the server has answered a `tools` request since the last `close`. A
freshly built server is not connected; `tools` (directly, through
`robot.connect_mcp!`, or through a run that selects the server) connects it;
`close` (directly or through `robot.disconnect`) resets it. The next request
after a `close` reconnects.

### tools

```ruby
server.tools  # => Array<RubyLLM::MCP::Tool>
```

ruby_llm's `tools`, connecting on the first call and marking the server
connected. The list is shaped by `only`, `except`, `prefix` and `tool`
declarations, cached, and refreshed when the server announces a change.

### close

```ruby
server.close
```

ruby_llm's `close` (stops a stdio server's process, ends a Streamable HTTP
session, stops listening), after clearing the connected flag.

## The ruby_llm Surface

For reference, the instance methods you will reach through `robot.mcp[:name]`.
See ruby_llm's own documentation for details.

| Method | Returns |
|--------|---------|
| `name` | `String` — the registry key |
| `tools` | `Array<RubyLLM::MCP::Tool>` (`name`, `server_name`, `description`, `requires_approval?`, `read_only?`, `destructive?`, ...) |
| `call(name, **args)` | `RubyLLM::MCP::Result` (`text`, `structured`, `attachments`, `error?`, `content`) |
| `resources` / `resource(uri, **vars)` / `resource_templates` | `RubyLLM::MCP::Resource` objects |
| `prompts` / `prompt(name, **args)` | `RubyLLM::MCP::Prompt`; pass a prompt to `robot.run` |
| `instructions` / `version` | the server's usage notes / reported version, or `nil` |
| `authorized?` / `authorization_url(redirect_uri:)` / `authorize(params)` / `deauthorize` | OAuth flow, for servers declared with `oauth` |
| `listen(resources:, tasks:)` | subscribe to changes in a background thread until `close` |

Direct calls raise ruby_llm's errors (`RubyLLM::MCP::Error`, `Errno::*`, ...)
to the caller. Only inside a robot run are connection failures rescued and
recorded.

## See Also

- [MCP Overview](index.md)
- [Factory](factory.md) - the config Hash to DSL mapping
- [Registry](registry.md)
