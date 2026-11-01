# MCP Registry

The MCP servers a robot knows, keyed by server name.

## Class: `RobotLab::MCP::Registry`

A robot resolves its `mcp` config on every run. The registry makes that cheap
and side-effect free: adding the same config Hash (by value), the same
`RubyLLM::MCP` instance, or the same class again returns the server already
built, so a stdio server's process is started once and reused across runs.
Adding a different spec under an existing name closes the old server and
replaces it.

Servers are closed only by `delete`, `clear`, or the robot's `disconnect`;
selecting a subset of servers for one run never closes the others.

`Registry` includes `Enumerable`; `each` yields the `RubyLLM::MCP` instances.

```ruby
registry = robot.mcp            # every Robot owns one

registry.names                  # => ["filesystem", "github"]
registry[:github]               # => #<GitHub ...>   (a RubyLLM::MCP)
registry.map(&:name)            # Enumerable
registry.select(&:connected?)   # RobotLab::MCP::Server instances know whether they have answered
```

## Methods

### add

```ruby
registry.add(spec)  # => RubyLLM::MCP
```

Register a server, or return the one already registered for `spec`. `spec` is
a config Hash, a `RubyLLM::MCP` instance, or a `RubyLLM::MCP` subclass; it is
built with [`RobotLab::MCP.build`](factory.md#build) and keyed by
[`RobotLab::MCP.name_of`](factory.md#name_of).

| Re-adding | Result |
|-----------|--------|
| A Hash equal (`==`) to the one registered under that name | The existing server |
| The same instance | The existing server |
| The same class | The existing server |
| A different spec under the same name | The old server is closed and replaced |

```ruby
config = { name: "fs", command: "npx", args: ["-y", "server-fs", "."] }
a = registry.add(config)
b = registry.add(config.dup)      # same value
a.equal?(b)                       # => true

registry.add(name: "fs", command: "other-server")   # closes a, registers a new server
```

**Raises** `RobotLab::MCPError` for a spec without a name or one `MCP.build`
rejects.

### []

```ruby
registry[name]  # => RubyLLM::MCP or nil
```

Look up a server by name (String or Symbol).

### key?

```ruby
registry.key?(name)  # => Boolean
```

### names

```ruby
registry.names  # => Array<String>
```

Registered server names, in registration order.

### each

```ruby
registry.each { |server| ... }
```

Yields each `RubyLLM::MCP` instance. Backs the `Enumerable` methods.

### empty? / size

```ruby
registry.empty?  # => Boolean
registry.size    # => Integer
```

### delete

```ruby
registry.delete(name)  # => RubyLLM::MCP or nil
```

Close and forget one server. Returns the removed server, or `nil` when no
server had that name.

### clear

```ruby
registry.clear  # => self
```

Close and forget every server. `robot.with_mcp(nil)` calls this.

## Relationship to the Robot

| Robot call | Registry effect |
|------------|-----------------|
| `RobotLab.build(mcp: [...])` | Nothing yet; specs are registered on `connect_mcp!` or the first run that selects them |
| `robot.with_mcp(*specs)` | `add` for each spec |
| `robot.with_mcp(nil)` | `clear` |
| `robot.run(..., mcp: [...])` | `add` for each spec resolved for this run (new ones are registered, known ones reused) |
| `robot.run(..., mcp: :none)` | No change; the run just sends no MCP tools |
| `robot.disconnect` | `each(&:close)`; servers stay registered and reconnect on next use |
| `robot.mcp_tools` | `collect` of `server.tools` over the registry (or a given subset), connecting as needed |

## See Also

- [MCP Overview](index.md)
- [Factory](factory.md)
- [Server](server.md)
- [Robot#mcp](../core/robot.md#mcp)
