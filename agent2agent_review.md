# Review: `agent2agent` Ruby Gem

**Source:** https://github.com/general-intelligence-systems/agent2agent
**Docs:** https://general-intelligence-systems.github.io/agent2agent/
**License:** Apache 2.0
**Ruby:** >= 3.2
**Reviewed:** 2026-05-05

---

## What It Is

A complete Ruby implementation of Google's A2A (Agent-to-Agent) protocol — an open standard for interoperable, cross-vendor AI agent communication over HTTP. The gem provides both a server (Rack app) and a client, plus SSE streaming, task persistence, and push notifications.

---

## Wire Protocol

Two parallel transport bindings, both implemented:

| Transport | Path | Format |
|---|---|---|
| JSON-RPC 2.0 | `POST /a2a` | `{"jsonrpc":"2.0","method":"SendMessage","params":{...}}` |
| HTTP+JSON/REST | `POST /message:send`, `GET /tasks/{id}`, etc. | Plain JSON |
| Agent Discovery | `GET /.well-known/agent-card.json` | Capabilities manifest |

### The 11 Protocol Operations

1. `SendMessage` — POST `/message:send` (synchronous)
2. `SendStreamingMessage` — POST `/message:stream` (SSE, server-streaming)
3. `GetTask` — GET `/tasks/{id}`
4. `ListTasks` — GET `/tasks`
5. `CancelTask` — POST `/tasks/{id}:cancel`
6. `SubscribeToTask` — SSE stream of task updates
7. `CreateTaskPushNotificationConfig` — POST `/tasks/{id}/push`
8. `GetTaskPushNotificationConfig` — GET `/tasks/{id}/push/{config_id}`
9. `ListTaskPushNotificationConfigs` — GET `/tasks/{id}/push`
10. `DeleteTaskPushNotificationConfig` — DELETE `/tasks/{id}/push/{config_id}`
11. `GetExtendedAgentCard` — GET extended agent card

### Task State Machine

`SUBMITTED → WORKING → INPUT_REQUIRED → COMPLETED / FAILED / CANCELED / REJECTED`

---

## Key Classes and Their Roles

| Class | Role |
|---|---|
| `A2A::Agent` | DSL: `on("SendMessage") { \|req\| respond(...) }` — registers operation handlers |
| `A2A::Server` | Rack app — mountable in any Rack stack or Rails router |
| `A2A::Client` | Async-HTTP client; all 11 ops auto-generated as snake_case methods |
| `A2A::Proto` | Parses the real `data/a2a.proto` file — single source of truth for operations |
| `A2A::Schema` | Loads 47-type `data/a2a.json`; validates with `json_schemer`; camelCase/snake_case |
| `A2A::TaskStore` | In-memory task CRUD with `Thread::Queue` pub/sub and webhook delivery |
| `A2A::Store::SQLite` | Production drop-in: WAL mode, indexed, fiber-safe `Async::Queue` pub/sub |
| `A2A::SSE::Stream` | Subclasses `Protocol::HTTP::Body::Writable`; Falcon passes it untouched |
| `A2A::Bindings::JsonRpc` | Rack middleware that parses JSON-RPC envelopes and wraps responses |

### Agent DSL Example

```ruby
agent = A2A::Agent.new do
  on "SendMessage", "SendStreamingMessage" do |context|
    task = context.store.create(context.request)
    stream = context.stream

    Async do
      result = robot.run(context.request.params[:message])
      context.store.complete(task.id, result)
      stream.event(result, type: "result")
      stream.finish
    end

    context.respond(task)
  end
end

server = A2A::Server.new
server.register(agent)
run server
```

### Client Example

```ruby
Async do
  client = A2A::Client.new("http://localhost:9292")
  card = client.agent_card
  result = client.send_message(message: { role: "user", parts: [{ text: "Hello" }] })
  puts result
end
```

---

## Notable Patterns

- **Duck-typed stores:** Any object implementing the task store interface can be swapped in — `TaskStore` (in-memory) or `Store::SQLite` (production), or a custom implementation.
- **Proto as source of truth:** `Proto` parses `data/a2a.proto` directly to extract operation metadata — stays in sync with the Google A2A spec automatically.
- **Fiber-native:** The SQLite store's pub/sub uses `Async::Queue`; SSE bodies use `Protocol::HTTP::Body::Writable`. Fully fiber-safe when run under Falcon.
- **`returnImmediately` flag:** Background jobs return a task ID immediately; updates stream via SSE as work proceeds.
- **`STATE_INPUT_REQUIRED`:** Multi-turn conversations — agent transitions to this state when it needs more user input before continuing. Client sends another `SendMessage` referencing the same task context.
- **Inline tests via `scampi`:** Tests live inside source files (`test do ... end`), not a separate test directory.
- **Tenant-prefixed paths:** Every REST route has a variant: `/{tenant}/message:send` for multi-tenant deployments.

---

## Authentication

- **AgentCard** declares supported auth schemes in the capabilities manifest
- **Push notification configs** carry per-webhook auth: `scheme` + `credentials` sent as `Authorization: Bearer <credentials>` on webhook delivery; optionally also `X-A2A-Notification-Token`
- Incoming request authentication is left to the application layer (standard Rack middleware pattern)

---

## Dependencies

**Runtime:**
- `async (~> 2.0)`, `async-http (~> 0.95)` — fiber concurrency and HTTP
- `rack (~> 3.0)` — server composition (pure Rack, Rails-mountable)
- `json_schemer (~> 2.5)` — schema validation against 47 A2A types
- `google-protobuf (~> 4.34)` — proto file parsing
- `sqlite3` — persistent task store
- `protocol-http (~> 0.62)` — `Body::Writable` for SSE
- `scampi` — inline test framework
- `console` — structured logging

**Development:**
- `falcon (~> 0.55)` — async HTTP server for running agents

---

## Applicability to Your Projects

### RobotLab — High Value

The most compelling integration: expose each `Robot` or `Network` as a standard A2A service. This enables cross-language orchestration (Python LangChain, JS Genkit, Go agents, Google Cloud agents) without any shared code.

**Robot-as-A2A-Service:**
- `A2A::Agent` adapter delegates `SendMessage` → `robot.run(request.message)`, result becomes the A2A task result
- Publish an AgentCard at `/.well-known/agent-card.json` advertising each robot's capabilities and tools
- Use `A2A::Store::SQLite` to persist tasks across requests (stateless HTTP tier in front of stateful robots)

**Streaming:**
- `SendStreamingMessage` + `SSE::Stream` maps directly onto RubyLLM's streaming callbacks
- Streaming events become real-time SSE — no additional infrastructure needed

**Cross-process robot networks:**
- Instead of `TypedBus` (in-process pub/sub only), robots in separate processes or machines call each other via `A2A::Client`
- A Network router can delegate to remote robots via `client.send_message(...)` — standard HTTP replaces shared-memory message passing

**Background jobs:**
- A2A's push notification config CRUD gives external systems a standard webhook protocol for task completion
- Maps cleanly onto RobotLab's existing async robot semantics

**Multi-turn conversations:**
- `STATE_INPUT_REQUIRED` maps directly to RobotLab's `AskUser` tool pattern — robot needs user input before continuing
- Web clients get a proper protocol for handling confirmation flows rather than a terminal prompt

**Compatibility note:** Both RobotLab and `agent2agent` use the `async` gem — they compose cleanly. The main requirement is running under Falcon rather than a plain Ruby process. `TypedBus` (`Async::Queue`) and `A2A::Store::PubSub` (`Async::Queue`) are both fiber-based and compatible.

### AIA — Moderate Value

- `A2A::Client` could delegate tasks to remote A2A-compliant agents (specialized coding agents, search agents, etc.) instead of calling LLM APIs directly
- AIA could optionally expose itself as a local A2A server on `localhost:PORT` so IDE plugins or other tools can send it tasks via standard protocol
- AgentCard discovery would let AIA auto-configure available capabilities when connecting to remote agents

### Rails Apps Generally

`A2A::Server` is pure Rack:

```ruby
# config/routes.rb
mount A2A::Server.new(agent: my_agent), at: "/agents/myagent"
```

This works as-is. The 47-type schema validation via `json_schemer` is also useful standalone for validating A2A protocol payloads.

---

## Bottom Line

Production-quality gem for its scope. Clean architecture: Rack middleware chain, duck-typed stores, fiber-safe pub/sub, SSE via `protocol-http`. Inline test coverage is extensive.

**Highest-value opportunity for RobotLab:** Robot-as-A2A-Service — exposing robots as standards-compliant HTTP endpoints enables cross-language agent orchestration that the current `TypedBus` approach (in-process only) cannot support. This would position RobotLab robots as first-class participants in the emerging A2A ecosystem alongside Python, JavaScript, and Go agent frameworks.

**Specific algorithms/patterns worth porting:**
1. `A2A::Store::SQLite` pub/sub pattern (Async::Queue-based) — applicable to RobotLab's Memory system
2. AgentCard capability manifest — useful for RobotLab's planned tool/capability discovery
3. `STATE_INPUT_REQUIRED` state machine entry — formalizes the `AskUser` pattern with a standard protocol state
