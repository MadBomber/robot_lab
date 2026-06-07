# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

### Added
- `.loki` Asgard task file: `test`, `rubocop`, `rubocop_fix`, `flog`, `flay`, `quality`, `build`, `install`, `release`, `integration`, `docs`, and `examples` tasks via the Asgard task runner
- `flay_check` Rake task: structural code duplication gate (mass threshold 50); integrated into the `quality` Rake task
- `flay` gem added to development dependencies
- `test_output.txt`, `flay_output.txt`, `flog_output.txt`, and `rubocop_output.txt` added to `.gitignore`

### Changed
- `test/test_helper.rb`: test output redirected to `test_output.txt` via `$stdout` reassignment; `TerminalSummaryReporter` prints a single PASS/FAIL summary line to the terminal
- `Rakefile`: `rubocop` and `rubocop_fix` tasks removed (now owned by Asgard); `flay_check` integrated into the `quality` gate

## [0.2.6] - 2026-05-23

### Added

- **`:compaction` hook family** — fires when `maybe_compact` determines that conversation history should be compressed. Provides `before_compaction`, `around_compaction`, `after_compaction`, and `on_compaction` callbacks.
  - `on_compaction` allows an extension to supply a complete replacement message set via `ctx.compacted_messages`; when set, the core skips its own compaction strategy entirely (`ctx.handled?` returns true).
  - `CompactionHookContext` — carries `robot`, `messages_before` (frozen snapshot), `config`, `strategy` (`:context_window`, `:custom`, or other symbol), `compacted_messages`, and `handled?`.
- **`:learn` hook family** — fires on every `robot.learn(text)` call with non-empty text. Provides `before_learn`, `around_learn`, `after_learn`, and `on_learn` callbacks.
  - `on_learn` fires after the text has been stored and `ctx.stored = true`, giving extensions a reliable hook point for cross-session persistence.
  - `LearnHookContext` — carries `robot`, `text`, `learnings_before` (frozen snapshot), and `stored`.
- **`over_compact_threshold?`** private predicate extracted from `compact_if_over_context_window` for independent testability.
- Hook tests for both new families added to `test/robot_lab/hooks_test.rb` (18 new tests across `RobotLabCompactionHooksTest` and `RobotLabLearnHooksTest`).
- Documentation for `:compaction` and `:learn` hook families added to `docs/guides/hooks.md`.

### Changed

- **`Robot#on`** now accepts and forwards `context:` to `HookRegistry#on`, allowing extensions to pass per-registration domain config at registration time (e.g. `robot.on(MyHook, context: { domain: "finance" })`). Previously `context:` was silently dropped.
- **`maybe_compact`** refactored to dispatch through the `:compaction` hook family and delegate to `on_compaction` before falling back to the built-in strategy.
- **`Robot#learn`** refactored to dispatch through the `:learn` hook family; `on_learn` fires after deduplication with `ctx.stored` reflecting whether the text was actually added.

### Added

- **`RobotLab::Hook` base class** (`lib/robot_lab/hook.rb`) — all hook handlers inherit from this class. Subclasses define lifecycle callbacks as `class << self` methods (`before_run`, `after_run`, etc.). Namespace is auto-derived from the class name via snake_case conversion of the final class name segment (e.g. `AuditHook` → `:audit_hook`); override with `self.namespace = :custom`. Ractor-safe by design: handler classes are Ruby constants, not Procs, so registrations are natively serializable across Ractor boundaries.
- **Hook system** — lifecycle hooks across all execution boundaries. Register handler classes with `RobotLab.on`, `network.on`, or `robot.on` for five families: `:run`, `:llm_generation`, `:tool_call`, `:network_run`, and `:task`, each with `before_*`, `around_*`, `after_*`, and (where applicable) `on_error` variants.
  - `HookRegistry::Registration` — `Data.define(:handler_class, :context)`; stores a handler class reference and optional per-registration default `DotState` values. No Proc, no namespace field — namespace is read from the handler class.
  - `HookContext` and five typed subclasses: `RunHookContext`, `LlmGenerationHookContext`, `ToolCallHookContext`, `NetworkRunHookContext`, `TaskHookContext` — unchanged
  - `DotState` / `ExtensionState` — namespace-isolated dot-access state carried on every context object; `ctx.local` reads/writes state for the active handler's namespace
  - `context:` parameter on `on(handler_class, context: {...})` — sets per-registration default `DotState` values merged in before each callback fires
  - Around hooks chain correctly across handler class registrations; return value is propagated up the chain
  - Per-run hooks via `robot.run("msg", hooks: MyHook)` or `robot.run("msg", hooks: [MyHook, OtherHook])`
  - `on_error` fires for `:run`, `:network_run`, and `:task` families; exception is re-raised after all error handlers complete
- **`examples/xyzzy.rb`** — updated reference extension: `RobotLab::Xyzzy < RobotLab::Hook` with `class << self` methods for every hook family; logs each callback with a timestamped stdout tagline and a structured logger context snapshot; registered globally with `RobotLab.on(RobotLab::Xyzzy)`
- **Example 35** (`examples/35_hooks.rb`) — updated full hook pipeline demo: xyzzy extension tracing all hooks, `around_run` perf timer handler class, `around_llm_generation` response cache handler class (cache hits skip the LLM entirely), `before/after_llm_generation` tracer, tool call hooks, network/task hooks, and `on_error`
- **`examples/common.rb`** — added explicit `openai_api_key`, `openai_organization_id`, and `openai_project_id` to `RubyLLM.configure` to match provider configurator expectations; updated default model to `gpt-4.1-mini`

## [0.2.1] - 2026-05-19

### Added

- **`examples/common.rb`** — shared setup file required by all numbered examples. Defines:
  - `LlmConfig = Data.define(:provider, :model)` and a frozen `LLM` hash with `:default` (OpenAI/gpt-5.4), `:local` (Ollama/llama3.2), and `:anthropic` (claude-opus-4-7) entries — access as `LLM[:default].model`
  - `RubyLLM.configure` with null logger and `LLM[:default].model` as `default_model`
  - `RobotLab.configure` with null logger
  - Output helpers: `banner(title)`, `section(title)`, `hr`, `show_code(ruby_string, label:)` using `rouge` for syntax highlighting
- **`rouge` gem** added to development group for syntax-highlighted example output
- **`.envrc` files** in `examples/`, `examples/14_rusty_circuit/`, `examples/15_memory_network_and_bus/`, and `examples/16_writers_room/` — each exports `ROBOT_LAB_TEMPLATE_PATH` pointing at the local `prompts/` directory for use with [direnv](https://direnv.net/)

### Changed

- **All 27+ numbered examples** refactored to `require_relative "common"` instead of requiring the gem directly, and to use `LLM[:default].model` instead of the hardcoded string `"gpt-5.4"`
- **Example 04 (MCP)** now calls `robot.connect_mcp!` before inspecting MCP attributes, fixing a lazy-initialization issue where `mcp_clients` and `mcp_tools` were empty until the first `run()` call

## [0.2.1] - 2026-05-11 (unreleased)

### Added

- **`flog` complexity gate** — `flog_check` Rake task enforces method-level complexity limits (warn ≥20, fail ≥50); `quality` task runs tests, RuboCop, and Flog in sequence with a unified pass/fail summary
- `flog` gem added to development/test group
- Branch coverage enabled unconditionally (previously CI-only) with minimum thresholds: line 95%, branch 75%

### Changed

- Bumped version to 0.2.1
- **`Robot#initialize` decomposed** into focused private methods: `assign_identity_ivars`, `build_effective_config`, `extract_config_ivars`, `initialize_runtime_state`, `initialize_memory`, `configure_learning`, `apply_template`, `apply_system_prompt`, `apply_chat_params`, `register_chat_callbacks`
- **`Robot#run` decomposed** into: `resolve_run_memory`, `prepare_tools`, `invoke_ask`, `enforce_token_budget!`
- **`BusPoller#process_and_drain`** split into `drain_queued_deliveries` and `release_robot` for independent testability
- **`TemplateRendering#apply_skills_and_template_to_chat`** split into `collect_prompt_content` (pure computation) and `apply_prompt_to_chat` (pure mutation)
- Removed `.serena/` project configuration files from version control
- Removed `.claude/memory.sqlite3` database files from version control

## [0.2.0] - 2026-05-07

### Added

- **`Durable::Learning`** — cross-session and within-session learning capability for robots. Robots accept `learn: true` and `learn_domain:` constructor params to persist knowledge across sessions via `~/.robot_lab/durable/` YAML files.
- **`Durable::Store`** — YAML-backed knowledge store with file locking, keyword recall, and confidence tracking.
- **`Durable::Entry`** — immutable value object for knowledge records with confidence progression.
- **`Durable::Reflector`** — promotes session learnings to durable storage at end of each run.
- **`RecallKnowledge` tool** — robots query past knowledge before uncertain decisions.
- **`RecordKnowledge` tool** — robots persist new knowledge learned during a session.
- **`AgentSkill`** — value object for discoverable skills defined by `SKILL.md` files with YAML front matter (name, description, version, dependencies, parameters)
- **`AgentSkillCatalog`** — service for locating and indexing `AgentSkills/` directories at runtime
- **`AgentSkillMatching`** — `Robot` mixin enabling runtime embedding-based skill injection: the robot selects the most relevant skills from a catalog based on semantic similarity before each run
- **`ScriptTool`** — factory that wraps shell scripts as robot tools; auto-generates JSON schema from script `--help` output
- **`DoomLoopDetector`** — detects consecutive and cyclic tool-call repetition; wired into `Robot#run` via singleton `execute_tool` override
- **`doom_loop_threshold`** field on `RunConfig` — configures the repetition threshold before a `ToolLoopError` is raised
- **`auto_compact` and `compact_threshold`** fields on `RunConfig` — `:context_window` mode estimates token usage before each run and calls `compress_history` when usage exceeds the threshold (default 80%); a `Proc` value delegates the decision and strategy entirely to the caller

### Changed

- Bumped version to 0.2.0
- **Extension gems extracted** — `robot_lab-document_store`, `robot_lab-durable`, `robot_lab-ractor`, and `robot_lab-rails` are now separate gems distributed via rubygems.org; the core gemspec drops `fastembed`, `ractor_queue`, and `ractor-wrapper` as hard dependencies
- **`Durable::Learning` inclusion** is now conditional on the `robot_lab-durable` gem being loaded
- **Tool Ractor routing** guarded on `RobotLab.respond_to?(:ractor_pool)` so the core gem runs without the ractor extension
- **Memory drainer scheduling** — `@drainer_scheduled` remains `true` when rescheduling to prevent concurrent writers from spawning competing drain fibers
- `@chat` state reset now uses `reset_messages!` / `add_message` public API instead of internal instance variable manipulation
- Rails generators moved to `robot_lab-rails` extension gem

### Fixed

- Memory drainer double-schedule race when concurrent writers triggered overlapping drain cycles
- `DocumentStore` instantiation guarded with a `LoadError` message when the extension gem is absent
- `AgentSkill` YAML parsing hardened against empty strings and non-Hash front matter
- Missing requires added to examples after gem extraction
- `doom_loop_threshold` and `auto_compact` documented in README and guides
- `learn:` parameter and `robot_lab-acp` documented in README

## [0.1.0] - 2026-04-29

### Added

- **`RobotLab::Job` base class** (`lib/robot_lab/rails_integration/job.rb`) — `ActiveJob::Base` subclass encapsulating the full robot-run lifecycle for Rails background jobs
  - `robot_class` DSL — bind a job subclass to a specific robot class at the class level; per-subclass, not inherited
  - `perform(message:, robot_class: nil, thread_id: nil, **context)` — resolves robot class, wires Turbo Stream callbacks, runs robot, persists `RobotResult`, broadcasts completion/error
  - `thread_id` omitted → fire-and-forget mode (no persistence, no broadcasting)
  - Turbo Stream wiring is a graceful no-op when `turbo-rails` is absent
  - `retry_on StandardError, wait: 5.seconds, attempts: 3` and `discard_on ActiveJob::DeserializationError` configured by default
  - `RobotLab::Job` top-level alias registered in `robot_lab.rb` when Rails is present so job subclasses can write `< RobotLab::Job`
- **`rails generate robot_lab:job NAME`** (`lib/generators/robot_lab/job_generator.rb`) — generates a dedicated job subclass pre-wired to `<NAME>Robot` via `robot_class` DSL
  - `--queue` option (default `"default"`)
  - Template: `lib/generators/robot_lab/templates/robot_job.rb.tt`
- **`max_concurrent_robots` field on `RunConfig`** — caps the number of fiber-concurrent robots in a parallel network execution; passed to `SimpleFlow::Pipeline#call_parallel` as `max_concurrent:`
- **Example 31: Launch Assessment** (`examples/31_launch_assessment.rb`) — six `AnalystRobot` instances run in parallel (market, competitive, tech, risk, financial, legal) with a cap of 4 concurrent robots; a `LaunchDirector` synthesizes findings into a GO/NO-GO decision
- **20 unit tests for `RobotLab::RailsIntegration::Job`** (`test/robot_lab/rails_integration/job_test.rb`) covering `robot_class` DSL, `resolve_robot_class`, `setup_thread`, `build_robot`, `broadcast_completion`, `broadcast_error`, and `turbo_available?`

### Changed

- Bumped version to 0.1.0
- **`RobotRunJob` (generated job)** is now a thin two-line subclass of `RobotLab::Job` — all lifecycle logic lives in the base class
- **`job.rb.tt` install generator template** updated to the thin-subclass pattern
- **`examples/18_rails` `RobotRunJob`** updated to thin subclass
- **`Network#call_parallel`** now forwards `max_concurrent: @config.max_concurrent_robots` to `SimpleFlow::Pipeline`, enabling the concurrency cap introduced in `RunConfig`

### Fixed

- **`Message.from_hash`** — records persisted without a `type` key (e.g. legacy user-message rows) previously raised `ArgumentError: missing keyword: :type`; `from_hash` now defaults a nil or absent `type` to `"text"` so old rows deserialize as `TextMessage` without error

### Documentation

- **`docs/guides/rails-integration.md`** — rewrote Background Jobs section to document `RobotLab::Job` base class, lifecycle steps, `robot_class` DSL, dedicated job generator, fire-and-forget mode, and when to use a custom `ApplicationJob` instead
- **`docs/api/messages/index.md`** — added "Deserializing from Hash" section documenting `Message.from_hash` dispatch logic and the missing-type fallback
- **README.md** — expanded Rails Integration section with full Background Jobs documentation including both generic and dedicated job patterns

## [0.0.12] - 2026-04-18

### Added

- **README: Context Window Compression section** — documents `robot.compress_history` with threshold tuning (`recent_turns`, `keep_threshold`, `drop_threshold`) and summarizer lambda pattern
- **README: Convergence Detection section** — documents `RobotLab::Convergence.detected?` / `.similarity` with network router fast-path example
- **README: Structured Delegation section** — documents `robot.delegate(to:, task:)` sync and async modes, `DelegationFuture` fan-out pattern, and timeout handling
- **README: Ractor Parallelism section** — documents `ractor_safe true` tool macro and `parallel_mode: :ractor` network mode with link to full guide
- **`docs/guides/building-robots.md`** — added matching sections for all four features above with expanded API detail, `DelegationFuture` method table, and convergence router example
- **`docs/api/core/result.md`** — new API reference for `RobotResult`: attributes, token tracking, delegation metadata, persistence (`export`, `from_hash`, `checksum`), and debug fields
- **`docs/api/errors.md`** — new error hierarchy reference covering all `RobotLab::Error` subclasses (`ConfigurationError`, `DependencyError`, `InferenceError`, `ToolLoopError`, `ToolNotFoundError`, `MCPError`, `BusError`, `RactorBoundaryError`, `ToolError`, `DelegationFuture::DelegationTimeout`) with rescue examples

### Changed

- Bumped version to 0.0.12
- Updated `bigdecimal` to 4.1.2
- Updated `protocol-http` to 0.62.2
- Updated `protocol-websocket` to 0.21.0
- Updated `rake` to 13.4.2
- Updated `sqlite3` to 2.9.3

## [0.0.11] - 2026-04-14

### Added

- **Ractor parallelism — Track 1: CPU-bound tools** (`RactorWorkerPool`)
  - `ractor_safe true` class macro on `Tool` — opts a tool class into Ractor execution; subclasses inherit automatically
  - `RobotLab.ractor_pool` — global `RactorWorkerPool` singleton, one Ractor worker per CPU core by default
  - `ractor_pool_size` field on `RunConfig` for configuring pool capacity
  - `RactorWorkerPool#submit(tool_name, args)` — submits a job and blocks for the frozen result; raises `ToolError` on failure
  - Tool dispatch routes `ractor_safe` tools through the pool automatically, bypassing the GVL for CPU-intensive work
  - `RactorBoundary.freeze_deep(obj)` — deep-freezes nested hashes/arrays/strings to make them Ractor-shareable; raises `RactorBoundaryError` for non-shareable objects (Procs, IOs, etc.)
- **Ractor parallelism — Track 2: parallel robot pipelines** (`RactorNetworkScheduler`)
  - `parallel_mode: :ractor` on `Network.new` — routes `network.run` through `RactorNetworkScheduler` instead of `SimpleFlow::Pipeline`
  - `RactorNetworkScheduler` dispatches dependency waves: independent tasks run concurrently (one Thread per task); dependent tasks wait for their wave to complete
  - `RobotSpec` — frozen `Data.define` descriptor carrying robot name, template, system prompt, and config; safely crosses Ractor boundaries
  - `RactorNetworkScheduler#run_pipeline` returns `Hash { robot_name => result_string }` for the full pipeline
  - `RactorNetworkScheduler#run_spec` for single-spec dispatch
  - `RactorNetworkScheduler#shutdown` for graceful poison-pill cleanup
  - `network.parallel_mode` reader exposes the configured mode (default `:async`)
- **Ractor memory proxy** — `RactorMemoryProxy` wraps `Memory` via `ractor-wrapper` for safe cross-Ractor memory access
- **Infrastructure data classes** — `RactorJob`, `RactorJobError` (`Data.define` structs) for job submission and error propagation across Ractor boundaries
- **`RactorBoundaryError`** — raised by `freeze_deep` when a non-shareable value (Proc, IO, etc.) would cross a Ractor boundary
- **`ToolError`** — raised by `RactorWorkerPool#submit` when a tool raises inside a Ractor; propagates message and frozen backtrace
- **Dependencies** — `ractor_queue` (~> 0.1) and `ractor-wrapper` (~> 0.4) added to gemspec
- **Ractor Parallelism guide** (`docs/guides/ractor-parallelism.md`) — covers architecture, two-track design, configuration, error handling, constraints, and best practices
- **Example 29: Ractor-Safe CPU Tools** (`examples/29_ractor_tools.rb`) — demonstrates `ractor_safe` flag, inheritance, `freeze_deep`, pool submissions, `ToolError` propagation, and parallel batch timing; no API key required
- **Example 30: Ractor Network Scheduler** (`examples/30_ractor_network.rb`) — demonstrates `RactorNetworkScheduler` wave ordering with simulated latencies, `Network.new(parallel_mode: :ractor)` API, and dependency graph inspection; no API key required for Parts 1 & 2

### Fixed

- `ToolConfig::NONE_VALUES` constant was not Ractor-shareable because its inner empty array `[]` was mutable; fixed by replacing `[]` with `[].freeze` so the entire constant is deeply frozen and safe to read from any Ractor

## [0.0.9] - 2026-03-02

### Added

- **Provider passthrough** — `provider:` parameter on Robot constructor for local LLM providers (Ollama, GPUStack, etc.)
  - Automatically sets `assume_model_exists: true` when provider is specified
  - Exposed via `robot.provider` accessor
- **MCP request timeouts** — configurable timeout for all MCP transports
  - `MCP::Server` accepts `timeout:` parameter (default 15s); auto-converts millisecond values
  - `MCP::Transports::Base` extracts and exposes `timeout` from config
  - `MCP::Transports::Stdio` wraps all blocking I/O with `Timeout.timeout` — hung servers no longer block the caller forever
  - Timeout propagated from `MCP::Server` through `MCP::Client` to transport layer
- **MCP connection resilience** — improved error handling and retry logic
  - `ensure_mcp_clients` retries previously failed servers on subsequent calls
  - `@failed_mcp_configs` tracks servers that failed to connect
  - `robot.failed_mcp_server_names` — query which MCP servers are down
  - `robot.connect_mcp!` — eagerly connect to MCP servers (normally lazy)
  - `init_mcp_client` rescues `StandardError` so one bad server doesn't prevent others from connecting
  - `cleanup_process` in Stdio transport for reliable resource cleanup
  - Better error messages for command-not-found (`Errno::ENOENT`), broken pipe (`Errno::EPIPE`), and EOF conditions
- **`robot.inject_mcp!`** — inject pre-connected MCP clients and tools from an external host application
- **Conversation management APIs** on Robot
  - `robot.chat` — access the underlying `RubyLLM::Chat` instance
  - `robot.messages` — return conversation messages
  - `robot.clear_messages(keep_system:)` — clear history, optionally preserving the system prompt
  - `robot.replace_messages(messages)` — restore a saved conversation (checkpoint/restore)
  - `robot.chat_provider` — query the provider name without reaching into chat internals
  - `robot.mcp_client(server_name)` — find an MCP client by server name
- **`RobotResult#duration`** — elapsed seconds for a robot run, set automatically during pipeline execution
- **`RobotResult#raw`** — raw LLM response stored on every result (previously only settable via accessor)
- **Pipeline error resilience** — `Robot#call` (pipeline step) rescues all exceptions so one failing robot doesn't crash the entire network; error is captured in a `RobotResult` with the elapsed duration

### Changed

- Bumped version to 0.0.9
- Display `scout_path` in Rusty Circuit example updated to use `output/` subdirectory
- Updated `onnxruntime` dependency to 0.11.0
- Updated Gemfile.lock dependencies (erb, minitest, rails-html-sanitizer, json_schemer)

## [0.0.8] - 2026-02-22

### Added

- **Skills as composable templates** — prepend reusable prompt snippets at build time via `skills:` parameter
  - Skills are regular PromptManager templates (no special subdirectory)
  - Recursive expansion — skills can declare nested skills via front matter `skills:` key
  - Depth-first ordering — nested skills appear before their parent
  - Cycle detection via `Set` of visited IDs; cycles log a warning and skip
  - Config cascade — skill₁ → skill₂ → ... → main template → constructor kwargs
  - Shared context — all skills and the main template render with the same `context:` hash
  - Example: `examples/17_skills.rb` — SRE incident response system with flat and recursive skills
  - 20 new tests covering expansion, ordering, cycles, config cascade, and factory passthrough
- **Streaming content callback (`on_content:`)** — wire streaming at robot build time
  - Stored callback fires on every `run()` call automatically
  - Pass-through block on `run()` for per-call streaming
  - When both exist, both fire (stored first, then runtime block)
  - `effective_streaming_block` merges stored + runtime into a single Proc
  - Added `:on_content` to `RunConfig::CALLBACK_FIELDS`
  - 12 new tests
- **Graceful tool error handling** — `RobotLab::Tool#call` wraps `execute` with `rescue StandardError`
  - Errors returned as plain string (`"Error (tool_name): message"`) so the LLM can reason about them
  - Class-level `raise_on_error` opt-out for critical tools
  - MCP tools inherit the same wrapper via `Tool.create` subclasses
  - 10 new tests
- **`RobotRunJob` generator template** (`job.rb.tt`) — turnkey ActiveJob background job for robot runs
  - Resolves robot class via `constantize.build`
  - Wires `TurboStreamCallbacks` when `turbo-rails` is available (graceful no-op otherwise)
  - Persists results via `result.export`; broadcasts completion/error via Turbo Streams
  - `--skip-job` option on install generator
- **`TurboStreamCallbacks` module** (`lib/robot_lab/rails_integration/turbo_stream_callbacks.rb`)
  - `available?` — runtime check for `Turbo::StreamsChannel`
  - `build_content_callback(stream_name:, target:)` — broadcasts HTML-escaped content chunks
  - `build_tool_call_callback(stream_name:, target:)` — broadcasts tool call badges
  - 13 tests
- **Rails demo app** (`examples/18_rails/`) — minimal hand-built Rails 8 app exercising all Rails integration
  - ChatRobot with TimeTool, RobotRunJob, Turbo Stream token streaming, SQLite persistence
  - No asset pipeline — Turbo JS via importmap from CDN
  - `:async` adapters for both ActiveJob and ActionCable (no Redis, no Solid Queue)
  - User messages persisted in history; auto-scrolling via MutationObserver; form clears after submit
  - Rake tasks: `examples:rails_setup`, `examples:rails`
- **Routing robot example** in Rails integration docs — `ClassifierRobot` subclass with `call(result)` override
- **Custom tool example** in Rails integration docs — `OrderLookup` tool with ActiveRecord

### Changed

- Bumped version to 0.0.8
- **Renamed `RobotLab::Rails` → `RobotLab::RailsIntegration`** — eliminates constant shadowing where bare `Rails` inside `module RobotLab` resolved to the gem's own namespace instead of `::Rails`
  - Moved `lib/robot_lab/rails/` → `lib/robot_lab/rails_integration/`
  - Updated all require paths, loader.ignore, generator templates, tests, and documentation
  - Reverted `::Rails` back to bare `Rails` in `config.rb` (shadow eliminated)
- Rakefile updated with `STANDALONE_APPS` map for standalone demo apps
- Documentation updates across README, guides, API reference, and examples for all new features
- Updated Gemfile.lock dependencies

### Fixed

- `RobotLab::Rails` namespace shadowing `::Rails` in `config.rb` (`NoMethodError: undefined method 'root' for module RobotLab::Rails`)
- MkDocs broken anchor link in `docs/examples/index.md` (`#with-conversation-history` → `#with-memory`)

## [0.0.7] - 2026-02-17 [unreleased]

### Added

- **Screenplay mode** for Writers' Room — adapts a finished book into a 4-act made-for-TV movie screenplay (pilot for a series) using the same self-organizing group infrastructure
  - **Mode Descriptor pattern** — `BOOK_MODE` and `SCREENPLAY_MODE` frozen hashes centralize all mode-variant values (template, unit name/range, completion key, bible/outline keys, output filename)
  - **Dynamic scene registry** — screenplay writers work at the scene level with a `scene_registry` in shared memory (comma-separated scene numbers); scenes can be dropped or reordered as the adaptation takes shape
  - **`Room#expected_units`** — public method that returns fixed range for book mode or parses the dynamic registry for screenplay mode; used by heartbeat, completion check, and assembly
  - **`--screenplay-from PATH`** CLI flag — loads `memory.json` from a previous book run into shared memory before screenplay writers start
  - **Memory dump** — book mode automatically saves all creative artifacts (story bible, outline, chapters) to `output/memory.json` after completion, enabling the book-to-screenplay pipeline
  - **Screenplay writer prompt template** (`prompts/screenplay_writer.md`) — source material is read-only, writes to `screenplay_bible`, `scene_outline`, `scene_registry`, `claims`, `scene_1..N`; encourages spawning when unclaimed scenes exceed active writers
  - **Heartbeat spawn nudging** — heartbeat messages now suggest spawning when unclaimed units outnumber active writers
- **Output README** (`examples/16_writers_room/output/README.md`) documenting the creative works produced by robot teams (opus_001, opus_002, opus_002_screenplay)
- **Opus 002** — second novella (*The Awakening of Meridian*) with session notes
- **Opus 002 Screenplay** — first screenplay adaptation with adaptation discussion notes

### Changed

- Bumped version to 0.0.7
- **Room class** now requires `mode:` parameter; `assemble_book` renamed to `assemble_output`; `wait_for_completion` and `send_heartbeat` read unit names, ranges, and keys from mode descriptor
- **Writer class** reads template from `room.mode[:template]` instead of hardcoded `:writer`
- **MarkCompleteTool** reads mode from `robot.room.mode` for unit range, unit name, and completion key; handles empty registry for dynamic modes
- **Display#complete** uses mode-neutral "work" instead of "book"
- Memory subscriptions in CLI are mode-aware (subscribe to mode-specific unit patterns and keys)
- Updated Gemfile.lock dependencies (Nokogiri, Parser, Rack)

## [0.0.6] - 2026-02-17 [unreleased]

### Added

- **Writers' Room example** (`examples/16_writers_room/`) — Self-Organizing Group (SOG) demo where identical writer robots collaborate to produce a 10-chapter fiction novella
  - Writer class with `fresh_chat!` pattern to prevent RubyLLM empty text content block corruption in bus-based robots
  - 7 tools: Broadcast, DirectMessage, ReadMemory, WriteMemory, ListMemory, SpawnWriter, MarkComplete
  - Room class with bus, shared memory, writer roster, heartbeat-based progress nudging, and structured logging
  - Display class with color-coded terminal output, word wrapping, and optional log file
  - CLI with `--premise`, `--writers`, `--log`, `--timeout`, `-h`/`--help` options
  - Shared prompt template (`prompts/writer.md`) — all writers use the same instructions with no hierarchy
- **Network pipeline tests** (`test/robot_lab/network_pipeline_test.rb`) for sequential robot execution and memory sharing
- **`dispatch_async` error handling** — exceptions inside async dispatch are now logged and contained instead of propagating

### Changed

- Bumped version to 0.0.6
- **Removed `Errors` module** and related test file — unused error classes cleaned out
- **Zeitwerk autoloading optimized** — streamlined loader configuration in `lib/robot_lab.rb`
- Rakefile updated with `16_writers_room` entry point in `SUBDIR_ENTRY_POINTS`

## [0.0.5] - 2026-02-17 [unreleased]

### Added

- **`RunConfig` class** (`lib/robot_lab/run_config.rb`) for shared operational defaults
  - Field categories: LLM (`model`, `temperature`, `top_p`, `top_k`, `max_tokens`, `presence_penalty`, `frequency_penalty`, `stop`), tools (`mcp`, `tools`), callbacks (`on_tool_call`, `on_tool_result`), infrastructure (`bus`, `enable_cache`)
  - Keyword construction, block DSL, and method chaining
  - Merge semantics: more-specific config's non-nil values win
  - `apply_to(chat)` applies LLM fields to a RubyLLM chat
  - `from_front_matter(metadata)` extracts config from template YAML front matter
  - `to_h`, `to_json_hash` (skips Procs/IO), `empty?`, `key?`, `==`, `inspect`
  - Full test suite (`test/robot_lab/run_config_test.rb`, 39 tests)
- **`config:` parameter** on `Robot.new`, `Network.new`, `Network#task`, `RobotLab.build`, and `RobotLab.create_network` for passing RunConfig instances
- **Configuration inheritance chain**: `RobotLab.config` (global) -> `network.config` -> task `config:` -> `robot.config` -> template front matter -> constructor kwargs
- **`robot.config` / `network.config` accessors** (`attr_reader`) returning the effective RunConfig
- **`RobotLab.configure`** block-style configuration method yielding the config object
- **Bus processing guard** (`handle_incoming_delivery`) serializing message deliveries across bus-connected robots to prevent Async fiber re-entrancy corrupting chat message ordering
- Documentation for RunConfig across README, configuration guide, network guide, and API reference
- Updated examples (`03_network`, `08_llm_config`, `09_chaining`, `11_network_introspection`) demonstrating RunConfig usage

### Changed

- Bumped version to 0.0.5
- **Template rendering refactored** to use `RunConfig.from_front_matter` instead of `apply_front_matter_config` — front matter config is now merged with the robot's RunConfig before applying to chat
- **MCP/tools hierarchy resolution** now accepts `network_config:` parameter instead of directly accessing the network object, enabling RunConfig-driven configuration flow
- **`dispatch_async`** simplified to exclusively use Async fibers, removing Thread-based fallback
- **`Memory#get`** improved nil value handling — uses `@backend.key?()` instead of nil check for correct nil value storage and retrieval
- **`Memory#clone`** optimized — results and messages are referenced directly instead of duplicated

## [0.0.4] - 2026-02-16 [unreleased]

### Added

- **`AskUser` tool** for human-in-the-loop interactions
  - Supports open-ended text, multiple choice, and default values
  - IO sourced from `robot.input`/`robot.output` (defaults to `$stdin`/`$stdout`)
  - Full test suite (`test/robot_lab/ask_user_test.rb`)
- **`Robot#input` / `Robot#output` accessors** for configurable IO streams
- **`reply` alias** for `RobotResult#last_text_content` — shorter, more natural API
- **`.irbrc`** for loading RobotLab in project-level IRB sessions
- **`wait_until` test helper** replacing flaky `sleep`-based assertions in async tests
- Documentation for AskUser tool across API reference, guides, and examples

### Changed

- Bumped version to 0.0.4
- **Made Rails dependencies optional** — removed `railties`, `activerecord`, `state_machines`, `state_machines-activemodel`, `state_machines-activerecord` from gemspec hard dependencies; moved to Gemfile `:test` group
- Replaced `require 'active_support'` with targeted `require 'active_support/core_ext/module/delegation'` — only loads what ruby_llm actually needs
- Added `activesupport >= 7.0` as explicit gemspec dependency with comment explaining it's required by ruby_llm (undeclared upstream)
- **Tool JSON schema keys are now symbolized** via `deep_symbolize_keys` in `Tool#to_json_schema`
- Updated all examples to use `reply` alias instead of `last_text_content`
- Replaced `sleep`-based test assertions with `wait_until` helper in memory, waiter, and robot tests
- Disabled branch coverage in SimpleCov except in CI

### Fixed

- Gem install conflict (`activesupport` version mismatch) when running outside Bundler
- IRB loading issue where `require_relative` was a no-op due to partial load in `$LOADED_FEATURES` — switched to `load`
- Robot tests for `send_message` now register a message handler on the receiver to avoid TypedBus warnings

## [0.0.3] - 2026-02-15 [unreleased]

### Added

- **Self-contained templates** with extended YAML front matter support
  - `robot_name` — override robot name from template
  - `description` — set robot description from template
  - `tools` — declare tool class names (resolved via `Object.const_get` at build time)
  - `mcp` — declare MCP server configurations
  - Constructor-provided values always take precedence over front matter
- **Editorial pipeline example** (`15_memory_network_and_bus/`) demonstrating multi-stage workflow with network, memory, and bus coordination
  - OS-specific writer robots, editor, and editor-in-chief roles
  - New prompt templates: `os_advocate`, `os_editor`, `os_chief`
- Rakefile support for running subdirectory-based examples with `SUBDIR_ENTRY_POINTS` mapping

### Changed

- Bumped version to 0.0.3
- Refactored Comic and Scout classes to use `attr_accessor` instead of `instance_variable_set`/`instance_variable_get`
- Extensive documentation updates across README, guides, API reference, and examples for front matter extras

## [0.0.2] - 2026-02-15 (unreleased)

### Added

- **TypedBus message bus** for robot-to-robot communication
  - `RobotMessage` immutable data class (`Data.define`) with `id`, `from`, `content`, `in_reply_to`
  - Optional `bus:` parameter on Robot constructor — purely additive
  - `on_message` handler with auto-ACK (1-arg block) and manual ACK/NACK (2-arg block)
  - `publish_to_bus` with Async-aware fiber wrapping
  - Typed channels accepting only `RobotMessage` objects
- **Dynamic robot spawning** via `Robot#spawn` method for creating child robots at runtime
- **`with_bus` configuration method** for connecting robots to a message bus after creation
- **Comic robot class** with dynamic comedy tools (`reinvent_style`, `adjust_energy`, `get_coaching`)
- New examples:
  - `12_message_bus.rb` — two-robot joke critique workflow
  - `13_spawn.rb` — dynamic robot spawning
  - `14_rusty_circuit/` — multi-robot comedy open mic with bus-based coordination
- New prompt templates: `comedian`, `comedy_critic`, `dispatcher`, `open_mic_comic`, `open_mic_heckler`, `open_mic_scout`, `configurable`, `llm_config_demo`
- Rake tasks for building documentation sites
- GitHub Actions workflow for YARD documentation deployment

### Changed

- Bumped version to 0.0.2
- Replaced `ruby_llm-template` dependency with `prompt_manager` (~> 1.0)
- Updated `ruby_llm` dependency to ~> 1.12
- Added `typed_bus` as a core dependency
- Added `myway_config` (~> 0.1) dependency
- Added `amazing_print` and `hashdiff` as development dependencies
- Migrated all prompt templates from directory-based format (`system.txt.erb` / `user.txt.erb`) to single `.md` files with YAML front matter
- Refactored `Robot` class for simplified configuration
- Refactored `Config` class
- Extensive documentation updates across all guide, architecture, and API reference pages

### Fixed

- GitHub Actions platform limitation (`arm64-darwin` only in lockfile)

## [0.0.1] - 2026-01-16

- refactored the network concept
- refactored the memory concept

### Needs Refactoring

- **Network concept is unhinged and needs complete refactoring.** The current implementation has several design issues:
  - Robots have separate memory when standalone vs in a network, causing confusion about what `robot.reset_memory` affects
  - Sequential execution only - no concurrent robot support despite infrastructure hints
  - Memory thread-safety is implemented but untested in practice
  - Unclear ownership model - robots don't know they're in a network
  - The relationship between Robot, Network, NetworkRun, and Memory needs simplification

### Added

- `Network#add_robot(robot)` - adds a robot, raises if name already exists
- `Network#replace_robot(robot)` - replaces existing robot, raises if not found
- `Network#remove_robot(name_or_robot)` - removes by name (String/Symbol) or Robot instance
- `Memory#enable_cache` parameter - allows disabling semantic caching
- `RobotLab.build`, `RobotLab.create_network`, `RobotLab.create_memory` now accept `enable_cache:` parameter
- Documentation for memory behavior (standalone vs network contexts)
- Documentation explaining what a Network is and when to use one
- Full MkDocs documentation site with Material theme
  - Getting Started guides (installation, quick start, configuration)
  - Architecture documentation (core concepts, robot execution, network orchestration, state management, message flow)
  - How-to guides (building robots, creating networks, using tools, MCP integration, streaming, history, memory, Rails integration)
  - Complete API reference (Robot, Network, State, Tool, Memory, Messages, Adapters, MCP, Streaming, History)
  - Working examples (basic chat, multi-robot network, tool usage, MCP server, Rails application)
- Documentation site logo and branding
- README.md redesign with top table layout pattern
- Network memory with concurrent robots example

### Changed

- Updated README.md with new tagline: "Build robots. Solve problems."
- Enhanced Rakefile with bundler/gem_tasks and test_helper preloading
- Updated gemspec summary and description for accuracy

## [0.0.0] - 2026-01-13

- Initial design
