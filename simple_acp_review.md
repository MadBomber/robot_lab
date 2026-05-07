# Review: `simple_acp` Ruby Library

**Path:** `/Users/dewayne/sandbox/git_repos/madbomber/simple_acp`
**Version:** 0.0.1
**Protocol:** ACP (Agent Communication Protocol) — Bee AI community standard, not Google's A2A
**Reviewed:** 2026-05-05

---

## What It Is

A complete Ruby implementation of ACP — an HTTP+SSE protocol for communication between AI agents, applications, and humans. Provides both a server (Roda/Falcon) and a client (Faraday), with pluggable storage backends, streaming, stateful sessions, and an await/resume pattern for interactive multi-turn flows.

---

## Wire Protocol

| Endpoint | Purpose |
|---|---|
| `GET /ping` | Health check |
| `GET /agents` | List registered agents (params: limit, offset) |
| `GET /agents/:name` | Agent manifest (capabilities, MIME types) |
| `POST /runs` | Create a run (body: agent_name, input[], mode, session_id) |
| `GET /runs/:id` | Run status |
| `POST /runs/:id` | Resume an awaited run (body: await_resume, mode) |
| `POST /runs/:id/cancel` | Cancel a run |
| `GET /runs/:id/events` | Full SSE event history (params: limit, offset) |
| `GET /session/:id` | Session state and history |

### Run Modes

- `SYNC` — wait for completion, return finished run
- `ASYNC` — return immediately with run ID, poll for completion
- `STREAM` — SSE event stream for real-time progress

### Task State Machine

`CREATED → IN_PROGRESS → AWAITING → COMPLETED / FAILED / CANCELLED / CANCELLING`

### Message Format (JSON)

```json
{
  "role": "user|agent|agent/name",
  "parts": [
    {
      "name": "optional",
      "content_type": "text/plain|application/json|image/*",
      "content": "string or base64",
      "content_encoding": "plain|base64",
      "content_url": "https://...",
      "metadata": { "kind": "citation|trajectory", ... }
    }
  ],
  "created_at": "ISO8601",
  "completed_at": "ISO8601"
}
```

### Run Response (JSON)

```json
{
  "run_id": "uuid",
  "agent_name": "string",
  "session_id": "uuid|null",
  "status": "created|in-progress|awaiting|completed|failed|cancelled|cancelling",
  "output": [{ "role": "agent", "parts": [...] }],
  "error": { "code": "server_error|invalid_input|not_found", "message": "...", "data": null },
  "await_request": { "type": "message", "message": { ... } },
  "created_at": "ISO8601",
  "finished_at": "ISO8601"
}
```

### SSE Event Types (11)

`message.created`, `message.part`, `message.completed`, `run.created`, `run.in_progress`, `run.awaiting`, `run.completed`, `run.cancelled`, `run.failed`, `generic`, `error`

---

## Key Classes and Their Roles

### Server

| Class | Role |
|---|---|
| `SimpleAcp::Server::Base` | Main server; registers agents, drives all execution modes |
| `SimpleAcp::Server::App` | Roda HTTP router — maps endpoints to server methods |
| `SimpleAcp::Server::Agent` | Wraps handler block; normalizes return types (String/Message/Array/Enumerator → consistent enumerable) |
| `SimpleAcp::Server::Context` | Passed to handler blocks; provides `await_message`, `cancel!`, `history`, `state`, `log` |
| `SimpleAcp::Server::FalconRunner` | Fiber-based Falcon server runner |

### Client

| Class | Role |
|---|---|
| `SimpleAcp::Client::Base` | Faraday-based; all endpoints as snake_case methods |
| `SimpleAcp::Client::SSE` | SSE event stream parser (event type + JSON data) |

**Client methods:** `ping`, `agents`, `agent(name)`, `run_sync`, `run_async`, `run_stream`, `run_resume_sync`, `run_resume_stream`, `run_status`, `run_events`, `run_cancel`, `wait_for_run`, `use_session`, `clear_session`, `session(id)`

### Models

| Class | Role |
|---|---|
| `SimpleAcp::Models::Message` | Role + array of `MessagePart`s; factory: `Message.user(...)`, `Message.agent(...)` |
| `SimpleAcp::Models::MessagePart` | Content unit: text, JSON, image, URL; factory: `.text(s)`, `.json(h)`, `.image(data, mime)`, `.from_url(url, ct)` |
| `SimpleAcp::Models::Run` | Execution lifecycle with state transitions: `start!`, `await!`, `complete!`, `fail!`, `cancel!` |
| `SimpleAcp::Models::Session` | Conversation history (Message array) + arbitrary state dict; `add_to_history`, `set_state` |
| `SimpleAcp::Models::AgentManifest` | Discovery: name, description, input/output MIME types, status, metadata |
| `SimpleAcp::Models::AwaitRequest` | Prompt to display when agent pauses |
| `SimpleAcp::Models::AwaitResume` | Client's response when resuming a paused run |
| `SimpleAcp::Models::Events` | SSE event hierarchy (all 11 types); `sse_format` for wire encoding |
| `SimpleAcp::Models::Error` | Structured error: code, message, data; factory: `.server_error`, `.invalid_input`, `.not_found` |
| `SimpleAcp::Models::Metadata` | Agent metadata: citations, trajectory, authors, links, dependencies, capabilities |

### Storage (pluggable — duck-typed interface)

| Class | Backend |
|---|---|
| `SimpleAcp::Storage::Memory` | `Concurrent::Map` — default, thread-safe |
| `SimpleAcp::Storage::Redis` | Redis backend |
| `SimpleAcp::Storage::PostgreSQL` | PostgreSQL via Sequel |

**Interface:** `get_run`, `save_run`, `delete_run`, `list_runs`, `get_session`, `save_session`, `delete_session`, `add_event`, `get_events`, `close`, `ping`

---

## Agent DSL

```ruby
server = SimpleAcp::Server::Base.new

server.agent("assistant",
  description: "A helpful assistant",
  input_content_types: ["text/plain"],
  output_content_types: ["text/plain"]
) do |context|
  input = context.input.text_content
  result = my_robot.run(input).reply
  SimpleAcp::Models::Message.agent(result)
end

server.run(port: 9292)
```

### Streaming Agent

```ruby
server.agent("streamer", description: "Streams responses") do |context|
  Enumerator.new do |yielder|
    my_robot.run(context.input.text_content) do |chunk|
      yielder << SimpleAcp::Models::MessagePart.text(chunk.content)
    end
  end
end
```

### Await/Resume Agent (interactive)

```ruby
server.agent("interactive", description: "Asks for clarification") do |context|
  clarification = context.await_message("Please clarify your intent:")
  answer = clarification.text_content
  result = my_robot.run("#{context.input.text_content} (clarification: #{answer})").reply
  SimpleAcp::Models::Message.agent(result)
end
```

### Client Usage

```ruby
client = SimpleAcp::Client::Base.new("http://localhost:9292")

# Synchronous
run = client.run_sync("assistant", input: "Hello")
puts run.output.first.text_content

# Streaming
client.run_stream("streamer", input: "Tell me a story") do |event|
  print event.part.content if event.is_a?(SimpleAcp::Models::Events::MessagePartEvent)
end

# Async with polling
run = client.run_async("assistant", input: "Long task")
completed = client.wait_for_run(run.run_id, timeout: 60)
```

---

## Dependencies

**Runtime:**
- `roda (~> 3.0)` — Rack web framework
- `falcon (~> 0.47)` — Fiber-based async HTTP server
- `async (~> 2.0)` — Async I/O primitives
- `async-http (~> 0.66)` — Async HTTP adapter
- `faraday (~> 2.0)` — HTTP client
- `concurrent-ruby (~> 1.2)` — Thread-safe data structures
- `json_schemer (~> 2.0)` — JSON schema validation
- `base64`, `uri` — stdlib backports for Ruby 3.4+

**Optional storage:**
- `redis (~> 5.0)`, `pg (~> 1.5)`, `sequel (~> 5.0)`

**Development:**
- `minitest (~> 5.0)`, `minitest-reporters`, `rack-test (~> 2.0)`, `webmock (~> 3.0)`
- `rubocop (~> 1.0)`, `rake`, `bundler`, `debug_me`, `aigcm`

---

## Comparison: `simple_acp` vs. `agent2agent` (GIS gem)

| Feature | `simple_acp` (yours) | `agent2agent` (GIS) |
|---|---|---|
| **Protocol** | ACP (Bee AI community) | A2A (Google) |
| **Await/Resume** | First-class — agents pause, client resumes | `INPUT_REQUIRED` state only |
| **Session state** | Arbitrary state dict + full history | Task-scoped only |
| **Storage backends** | Memory, Redis, PostgreSQL | Memory, SQLite |
| **HTTP framework** | Roda + Falcon | Pure Rack + Falcon |
| **Client** | Faraday-based, full API surface | `async-http`, fiber-only |
| **Content types** | Multimodal: text, JSON, image, URL refs | Text/JSON focused |
| **Agent DSL** | Block-based, normalized return types | Block-based |
| **Tests** | Minitest in `test/` | `scampi` inline |
| **Proto/Schema** | JSON Schema via `json_schemer` | `.proto` file + 47-type JSON schema |

---

## Applicability to RobotLab

### High Value — Natural Fit

**Robot-as-ACP-Agent:**
Each `Robot` maps directly to an ACP agent registration:

```ruby
server.agent(robot.name, description: robot.description) do |context|
  result = robot.run(context.input.text_content)
  SimpleAcp::Models::Message.agent(result.reply)
end
```

**Streaming robot output:**
`run_stream` + SSE `message.part` events maps onto RubyLLM's streaming callbacks — emit one `MessagePartEvent` per chunk. Real-time progress for free.

**Await/Resume ↔ AskUser:**
`ctx.await_message(prompt)` / `ctx.resume_message` is a network-protocol equivalent of RobotLab's `AskUser` tool. Exposes interactive robot flows to web and API clients without a terminal dependency. This is the most direct protocol-level replacement for `AskUser`.

**Session ↔ Memory:**
`Session#state` (arbitrary dict) mirrors `Memory#data` (StateProxy). `Session#history` mirrors `Memory#messages`. A thin bridge adapter could keep them in sync, giving RobotLab robots persistent cross-request state without Redis.

**Async runs ↔ background jobs:**
`run_async` returns a run ID immediately; `wait_for_run` polls. Maps cleanly onto `RobotLab::Job` (ActiveJob) — the job creates the run, Turbo Streams broadcast `message.part` events as SSE.

**Network-as-single-agent:**
Expose an entire `Network` pipeline as one ACP agent — clients send one message, the network orchestrates internally across all robots, the final result comes back as one response. Callers don't need to know the internal topology.

**PostgreSQL storage:**
`SimpleAcp::Storage::PostgreSQL` aligns with RobotLab's Rails integration and existing ActiveRecord setup. No new infrastructure required.

**Multimodal inputs:**
`MessagePart` supports images, JSON blobs, and URL references out of the box — richer than plain text, useful for vision-capable robots or structured-data workflows.

### Integration Pattern

```ruby
# Expose a RobotLab Network as an ACP server
network = RobotLab.create_network(name: "support") { ... }

server = SimpleAcp::Server::Base.new(
  storage: SimpleAcp::Storage::PostgreSQL.new(db_url)
)

server.agent("support",
  description: "Multi-robot support pipeline",
  input_content_types: ["text/plain"],
  output_content_types: ["text/plain"]
) do |context|
  memory = RobotLab.create_memory(
    data: { session_id: context.session_id }
  )
  result = network.run(message: context.input.text_content, memory: memory)
  SimpleAcp::Models::Message.agent(result.reply)
end
```

---

## Bottom Line

`simple_acp` is a cleaner fit for RobotLab than the `agent2agent` gem for three reasons:

1. **Await/resume directly replaces `AskUser`'s terminal dependency** with a proper HTTP protocol state — robots can request human input without blocking a terminal session
2. **PostgreSQL backend** aligns with the existing Rails integration — no SQLite impedance mismatch
3. **Multimodal message parts** (image, JSON, URL) give RobotLab robots richer input/output than plain text

The most impactful integration would be a `RobotLab::ACPServer` adapter class that wraps any `Robot` or `Network` as an ACP agent, mapping `AskUser` calls to `await_message`, streaming callbacks to `message.part` events, and `RobotResult` to a completed `Message`.
