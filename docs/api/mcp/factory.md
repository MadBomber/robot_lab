# MCP Factory

Builds `RubyLLM::MCP` servers from robot_lab config Hashes.

## Module: `RobotLab::MCP`

`RobotLab::MCP` is the namespace for robot_lab's MCP layer and a set of module
functions that turn the config Hash shape (used in template front matter,
`RunConfig#mcp`, `RobotLab.build(mcp: [...])` and `Network#task(mcp:)`) into
ruby_llm's `RubyLLM::MCP` class DSL. Instances and subclasses of
`RubyLLM::MCP` pass through unchanged.

```ruby
server = RobotLab::MCP.build(
  name: "filesystem",
  transport: { type: "stdio", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "."] },
  timeout: 30,
  only: %w[read_text_file list_directory]
)
# => #<RobotLab::MCP::Server ...>  (a RubyLLM::MCP)

server.tools                                   # connects, lists tools
server.call(:list_directory, path: ".").text
server.close
```

## Module Functions

### build

```ruby
RobotLab::MCP.build(spec)  # => RubyLLM::MCP
```

| `spec` | Result |
|--------|--------|
| `RubyLLM::MCP` instance | Returned as is |
| `RubyLLM::MCP` subclass | `spec.new` |
| `Hash` | `define(spec).new` |
| anything else | `RobotLab::MCPError` (`Cannot build an MCP server from Integer; pass a Hash, a RubyLLM::MCP, or a RubyLLM::MCP subclass`) |

A `Class` that is not a `RubyLLM::MCP` subclass raises
`RobotLab::MCPError` (`String is not a RubyLLM::MCP subclass`).

### define

```ruby
RobotLab::MCP.define(config)  # => Class < RobotLab::MCP::Server
```

Turns a config Hash into an anonymous `RobotLab::MCP::Server` subclass with
ruby_llm's class DSL applied. Public so hosts can build a class once and
instantiate it per request (ruby_llm's recommended pattern). Keys may be
Symbols or Strings.

```ruby
klass = RobotLab::MCP.define(name: "fs", command: "npx", args: ["-y", "server-fs", "."])
klass.default_name   # => "fs"
klass.command        # => ["npx", "-y", "server-fs", "."]
klass.new.name       # => "fs"
```

**Raises** `RobotLab::MCPError` when the Hash has no `name`, no usable transport
(neither `command` nor `url`), a stdio transport without `command`, an HTTP
transport without `url`, an unknown transport type, or an unsupported one
(`sse`, `ws`, `websocket`).

### name_of

```ruby
RobotLab::MCP.name_of(spec)  # => String
```

The name a spec will be registered under: `spec[:name]` / `spec["name"]` for a
Hash, `default_name` for a class, `name` for an instance. Raises
`RobotLab::MCPError` when the name is missing or blank.

### seconds

```ruby
RobotLab::MCP.seconds(value)  # => Float
```

Normalizes a timeout to seconds. Values of 1000 or more are taken to be
milliseconds (the convention aia and older configs used); the result is never
below one second.

| Given | Result |
|-------|--------|
| `5` | `5.0` |
| `5000` | `5.0` |
| `"2500"` | `2.5` |
| `999` | `999.0` |
| `0.2` | `1.0` |

## Config Hash Keys

Top-level keys are symbolized. Transport keys may be nested under `transport:`
or flat at the top level; a nested key wins over a flat one of the same name.

| Key | DSL applied | Notes |
|-----|-------------|-------|
| `name` | `default_name=` | **Required** |
| `description` | `Server.description` | Read by `MCP::ServerDiscovery` |
| `transport` | | A Hash (`type:` plus transport keys), a String/Symbol type, or a transport object |
| `transport.type` | | `stdio`, or one of `HTTP_TYPES`. Absent: inferred from `command` / `url` |
| `command`, `args` | `command(*argv)` | `command` may be a String or Array; `args` appended; all coerced to Strings |
| `env` | `env(**)` | Keys symbolized |
| `directory` / `cwd` | `directory` | `directory` wins when both are given |
| `url` | `url` | Streamable HTTP; ruby_llm requires `https` except on loopback |
| `headers` | `header(k, v)` per entry | |
| `bearer_token` | `bearer_token` | |
| `oauth` | `oauth` / `oauth(**settings)` | `true` enables defaults; a Hash passes settings (`scopes`, `client_id`, ...) |
| `timeout` | `timeout(seconds(value))` | Absent: ruby_llm's `request_timeout` |
| `prefix` | `prefix` | Tool names become `prefix_name` |
| `only`, `except` | `only(*)`, `except(*)` | A single name or an Array |
| `requires_approval` | `requires_approval` | `true`, an Array of tool names, or a Hash such as `{ if: :destructive? }`; `false`/`nil` leaves none |
| `defer` | `defer` | `true` or an Array of tool names |
| `log_level` | `log_level` | A level ruby_llm knows (`debug`, `info`, `warning`, ...) |
| `input_requests` | `input_requests(*kinds)` | `["form"]`, `["url"]`, or `false` to disable |
| `extensions` | `extension(name, **settings)` | A list (`["tasks"]`) or a Hash (`{ "tasks" => {} }`). Names with a `/` are vendor-prefixed Strings; others are ruby_llm's Symbols |

A `transport:` value that is not a Hash and responds to `request` and `close`
is installed directly with `transport(obj)` (tunnels, in-process test
transports). ruby_llm expects such an object to also respond to `notify` and
`cancel`.

Keys in `IGNORED_KEYS` are skipped silently. Any other unknown key is skipped
and logged once at `debug`: `MCP server 'fs': ignoring unknown keys
something_new`.

## Constants

```ruby
RobotLab::MCP::HTTP_TYPES
# => ["streamable-http", "streamable_http", "http", "https"]

RobotLab::MCP::UNSUPPORTED_TYPES
# => ["sse", "ws", "websocket"]      # raise MCPError with guidance

RobotLab::MCP::IGNORED_KEYS
# => [:topics, :independent, :group, :session_id, :auth_provider]

RobotLab::MCP::TRANSPORT_KEYS
# => [:type, :command, :args, :env, :url, :headers, :bearer_token, :oauth, :directory, :cwd]

RobotLab::MCP::SETTING_KEYS
# => [:name, :description, :transport, :timeout, :prefix, :only, :except,
#     :requires_approval, :defer, :log_level, :input_requests, :extensions]

RobotLab::MCP::CONNECT_ERRORS
# => [RubyLLM::Error, RubyLLM::ConfigurationError, SystemCallError, IOError, ArgumentError]
```

`CONNECT_ERRORS` are the errors a server can raise while connecting or listing
tools. A robot rescues these per server (recording them in `mcp_failures`) so
one dead server does not abort a run. `RubyLLM::MCP::Error` is a
`RubyLLM::Error`, so it is covered.

The unsupported-transport message reads:

```
MCP server 'x' uses transport 'sse', which ruby_llm 2.1 does not provide
(only stdio and Streamable HTTP). Point the server at its Streamable HTTP
endpoint, or pass a transport: object that responds to request/notify/cancel/close.
```

## See Also

- [MCP Overview](index.md)
- [Server](server.md) - the class `define` produces
- [Registry](registry.md) - how a robot holds its servers
- [MCP Integration Guide](../../guides/mcp-integration.md)
