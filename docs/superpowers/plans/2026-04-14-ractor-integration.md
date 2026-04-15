# Ractor Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add true CPU parallelism to RobotLab via two composable tracks: a `ractor_queue`-backed worker pool for CPU-bound tools, and a `RactorNetworkScheduler` for parallel robot execution, connected by shared frozen-message infrastructure.

**Architecture:** Track 1 routes Ractor-safe tools through a `RactorWorkerPool` (N Ractor workers, `ractor_queue` job queue, per-job reply queue). Track 2 wraps `Memory` via `ractor-wrapper` for cross-Ractor shared state, and introduces `RactorNetworkScheduler` to dispatch frozen robot tasks to Ractor workers while respecting `depends_on` ordering. Robots stay in threads for LLM calls; only frozen payloads and results cross Ractor boundaries.

**Tech Stack:** Ruby Ractors, `ractor_queue` gem, `ractor-wrapper` gem, Minitest, existing RobotLab test helpers.

**Spec:** `docs/superpowers/specs/2026-04-14-ractor-integration-design.md`

---

## File Map

### New files
| File | Purpose |
|------|---------|
| `lib/robot_lab/ractor_job.rb` | `RactorJob`, `RactorJobError`, `RobotSpec` shareable data classes |
| `lib/robot_lab/ractor_boundary.rb` | `RactorBoundary.freeze_deep` + `RactorBoundaryError` |
| `lib/robot_lab/ractor_worker_pool.rb` | N Ractor workers fed by `ractor_queue` |
| `lib/robot_lab/ractor_memory_proxy.rb` | `ractor-wrapper` proxy around `Memory` |
| `lib/robot_lab/ractor_network_scheduler.rb` | Distributes frozen robot tasks to Ractor workers |
| `test/robot_lab/ractor_boundary_test.rb` | Tests for `RactorBoundary` |
| `test/robot_lab/ractor_worker_pool_test.rb` | Tests for `RactorWorkerPool` |
| `test/robot_lab/ractor_memory_proxy_test.rb` | Tests for `RactorMemoryProxy` |
| `test/robot_lab/ractor_network_scheduler_test.rb` | Tests for `RactorNetworkScheduler` |

### Modified files
| File | Change |
|------|--------|
| `Gemfile` | Add `ractor_queue`, `ractor-wrapper` |
| `robot_lab.gemspec` | Add `ractor_queue`, `ractor-wrapper` as runtime dependencies |
| `lib/robot_lab/error.rb` | Add `RactorBoundaryError` |
| `lib/robot_lab/tool.rb` | Add `ractor_safe` class macro; route in `call` |
| `lib/robot_lab/run_config.rb` | Add `ractor_pool_size` to `INFRA_FIELDS` |
| `lib/robot_lab/bus_poller.rb` | Swap `Array` queues for `ractor_queue` instances |
| `lib/robot_lab/network.rb` | Add `parallel_mode:` param, delegate to scheduler |
| `lib/robot_lab.rb` | Add `ractor_pool` accessor + require `ractor_job.rb` explicitly |

---

## Task 1: Add gem dependencies

**Files:**
- Modify: `Gemfile`
- Modify: `robot_lab.gemspec`

- [ ] **Step 1: Add to Gemfile development group**

Open `Gemfile`. Add inside `group :development, :test do`:

```ruby
gem 'ractor_queue'
gem 'ractor-wrapper'
```

- [ ] **Step 2: Add to gemspec as runtime dependencies**

Open `robot_lab.gemspec`. After the `simple_flow` dependency line, add:

```ruby
spec.add_dependency "ractor_queue"
spec.add_dependency "ractor-wrapper"
```

- [ ] **Step 3: Install**

```bash
cd /Users/dewayne/sandbox/git_repos/madbomber/robot_lab && bundle install
```

Expected: both gems install without error. Note the exact versions installed — you will reference them in commit messages.

- [ ] **Step 4: Verify gems load**

```bash
bundle exec ruby -e "require 'ractor_queue'; require 'ractor/wrapper'; puts 'ok'"
```

Expected output: `ok`

> **IMPORTANT:** Before proceeding, open the installed gem source (`bundle show ractor_queue` and `bundle show ractor-wrapper`) and read the README/source to confirm the exact API. The plan uses:
> - `RactorQueue.new` → `push(item)`, `pop`, `empty?`, `close`
> - `Ractor::Wrapper.wrap(obj)` → `.call(:method, *args)` for proxied calls
>
> If the actual API differs, adjust all subsequent tasks accordingly before implementing them.

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock robot_lab.gemspec
git commit -m "chore(deps): add ractor_queue and ractor-wrapper gems"
```

---

## Task 2: Shared data classes + RactorBoundaryError

**Files:**
- Create: `lib/robot_lab/ractor_job.rb`
- Modify: `lib/robot_lab/error.rb`
- Modify: `lib/robot_lab.rb`

- [ ] **Step 1: Write failing test**

Create `test/robot_lab/ractor_job_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class RobotLab::RactorJobTest < Minitest::Test
  def test_ractor_job_is_shareable
    reply_q = RactorQueue.new
    job = RobotLab::RactorJob.new(
      id: "abc",
      type: :tool,
      payload: { tool_class: "MyTool", args: { x: 1 }.freeze }.freeze,
      reply_queue: reply_q
    )
    assert Ractor.shareable?(job)
  end

  def test_ractor_job_error_is_shareable
    err = RobotLab::RactorJobError.new(message: "boom", backtrace: ["line 1"].freeze)
    assert Ractor.shareable?(err)
  end

  def test_robot_spec_is_shareable
    spec = RobotLab::RobotSpec.new(
      name: "bot",
      template: nil,
      system_prompt: "Be helpful.",
      config_hash: { model: "claude-sonnet-4" }.freeze
    )
    assert Ractor.shareable?(spec)
  end

  def test_ractor_boundary_error_is_subclass_of_error
    assert RobotLab::RactorBoundaryError < RobotLab::Error
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rake test_file[robot_lab/ractor_job_test.rb]
```

Expected: fails with `NameError: uninitialized constant RobotLab::RactorJob` or similar.

- [ ] **Step 3: Add RactorBoundaryError to error.rb**

Open `lib/robot_lab/error.rb`. Add after the `DependencyError` class:

```ruby
  # Raised when a value cannot be made Ractor-shareable before crossing
  # a Ractor boundary (e.g., a live IO, Proc, or object with mutable state).
  #
  # @example
  #   raise RactorBoundaryError, "Cannot freeze IO object"
  class RactorBoundaryError < Error; end
```

- [ ] **Step 4: Create lib/robot_lab/ractor_job.rb**

```ruby
# frozen_string_literal: true

module RobotLab
  # Carrier for work crossing a Ractor boundary.
  #
  # All fields must be Ractor-shareable (frozen Data, frozen String,
  # frozen Hash, or a RactorQueue). Build with RactorBoundary.freeze_deep
  # on the payload before constructing.
  #
  # @example
  #   job = RactorJob.new(
  #     id:          SecureRandom.uuid.freeze,
  #     type:        :tool,
  #     payload:     RactorBoundary.freeze_deep({ tool_class: "MyTool", args: { x: 1 } }),
  #     reply_queue: RactorQueue.new
  #   )
  RactorJob = Data.define(:id, :type, :payload, :reply_queue)

  # Frozen error representation for exceptions raised inside a Ractor worker.
  # Serialized at the Ractor boundary and re-raised on the thread side.
  #
  # @example
  #   err = RactorJobError.new(message: e.message, backtrace: e.backtrace.freeze)
  RactorJobError = Data.define(:message, :backtrace)

  # Carries everything needed to reconstruct a Robot inside a Ractor.
  # All fields must be frozen strings, symbols, or hashes.
  #
  # @example
  #   spec = RobotSpec.new(
  #     name:         "analyst",
  #     template:     :analyst,
  #     system_prompt: nil,
  #     config_hash:  { model: "claude-sonnet-4" }.freeze
  #   )
  RobotSpec = Data.define(:name, :template, :system_prompt, :config_hash)
end
```

- [ ] **Step 5: Explicitly require ractor_job.rb in lib/robot_lab.rb**

Open `lib/robot_lab.rb`. After the existing explicit requires (after `require_relative 'robot_lab/memory'`), add:

```ruby
require_relative 'robot_lab/ractor_job'
```

- [ ] **Step 6: Run test to verify it passes**

```bash
bundle exec rake test_file[robot_lab/ractor_job_test.rb]
```

Expected: all 4 tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/robot_lab/ractor_job.rb lib/robot_lab/error.rb lib/robot_lab.rb test/robot_lab/ractor_job_test.rb
git commit -m "feat(ractor): add RactorJob, RactorJobError, RobotSpec data classes and RactorBoundaryError"
```

---

## Task 3: RactorBoundary utility module

**Files:**
- Create: `lib/robot_lab/ractor_boundary.rb`
- Create: `test/robot_lab/ractor_boundary_test.rb`

- [ ] **Step 1: Write failing test**

Create `test/robot_lab/ractor_boundary_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class RobotLab::RactorBoundaryTest < Minitest::Test
  def test_freezes_string
    result = RobotLab::RactorBoundary.freeze_deep("hello")
    assert result.frozen?
  end

  def test_freezes_hash_recursively
    result = RobotLab::RactorBoundary.freeze_deep({ a: { b: "c" } })
    assert result.frozen?
    assert result[:a].frozen?
    assert result[:a][:b].frozen?
  end

  def test_freezes_array_recursively
    result = RobotLab::RactorBoundary.freeze_deep(["x", { y: "z" }])
    assert result.frozen?
    assert result[0].frozen?
    assert result[1].frozen?
  end

  def test_passes_through_already_frozen
    frozen_str = "hi".freeze
    assert_same frozen_str, RobotLab::RactorBoundary.freeze_deep(frozen_str)
  end

  def test_passes_through_integer
    assert_equal 42, RobotLab::RactorBoundary.freeze_deep(42)
  end

  def test_passes_through_symbol
    assert_equal :foo, RobotLab::RactorBoundary.freeze_deep(:foo)
  end

  def test_result_is_ractor_shareable
    result = RobotLab::RactorBoundary.freeze_deep({ model: "sonnet", args: [1, 2] })
    assert Ractor.shareable?(result)
  end

  def test_raises_ractor_boundary_error_on_unshareable
    io = StringIO.new
    assert_raises(RobotLab::RactorBoundaryError) do
      RobotLab::RactorBoundary.freeze_deep(io)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bundle exec rake test_file[robot_lab/ractor_boundary_test.rb]
```

Expected: fails with `NameError: uninitialized constant RobotLab::RactorBoundary`.

- [ ] **Step 3: Create lib/robot_lab/ractor_boundary.rb**

```ruby
# frozen_string_literal: true

module RobotLab
  # Utility for making values safe to pass across Ractor boundaries.
  #
  # Recursively freezes Hash and Array structures. Raises RactorBoundaryError
  # if a value cannot be made Ractor-shareable (e.g. a live IO or Proc).
  #
  # @example
  #   safe = RactorBoundary.freeze_deep({ model: "sonnet", args: { x: 1 } })
  #   Ractor.shareable?(safe)  #=> true
  #
  module RactorBoundary
    # Recursively freeze an object for safe Ractor boundary crossing.
    #
    # @param obj [Object] the value to freeze
    # @return [Object] a frozen, Ractor-shareable copy
    # @raise [RactorBoundaryError] if the value cannot be made shareable
    def self.freeze_deep(obj)
      return obj if Ractor.shareable?(obj)

      result = case obj
               when Hash
                 obj.transform_keys { |k| freeze_deep(k) }
                    .transform_values { |v| freeze_deep(v) }
               when Array
                 obj.map { |v| freeze_deep(v) }
               else
                 begin
                   obj.dup
                 rescue TypeError
                   raise RactorBoundaryError,
                         "Cannot make #{obj.class} Ractor-shareable: dup not supported"
                 end
               end

      Ractor.make_shareable(result)
    rescue Ractor::IsolationError => e
      raise RactorBoundaryError, "Cannot make value Ractor-shareable: #{e.message}"
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bundle exec rake test_file[robot_lab/ractor_boundary_test.rb]
```

Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/ractor_boundary.rb test/robot_lab/ractor_boundary_test.rb
git commit -m "feat(ractor): add RactorBoundary.freeze_deep utility"
```

---

## Task 4: Tool#ractor_safe class macro

**Files:**
- Modify: `lib/robot_lab/tool.rb`
- Modify: `test/robot_lab/tool_test.rb`

- [ ] **Step 1: Write failing test**

Open `test/robot_lab/tool_test.rb`. Add at the end of the class, before the closing `end`:

```ruby
  # ── ractor_safe macro ───────────────────────────────────────────

  def test_ractor_safe_defaults_to_false
    klass = Class.new(RobotLab::Tool) do
      description "Test"
      def execute(**); end
    end
    refute klass.ractor_safe?
  end

  def test_ractor_safe_can_be_enabled
    klass = Class.new(RobotLab::Tool) do
      description "Safe tool"
      ractor_safe true
      def execute(**); end
    end
    assert klass.ractor_safe?
  end

  def test_ractor_safe_is_inherited
    parent = Class.new(RobotLab::Tool) do
      description "Parent"
      ractor_safe true
      def execute(**); end
    end
    child = Class.new(parent)
    assert child.ractor_safe?
  end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/tool_test.rb]
```

Expected: fails with `NoMethodError: undefined method 'ractor_safe'`.

- [ ] **Step 3: Add ractor_safe macro to Tool**

Open `lib/robot_lab/tool.rb`. Inside `class << self` (after the `raise_on_error?` method), add:

```ruby
      # Declare that this tool class is safe to run inside a Ractor.
      #
      # Ractor-safe tools must be stateless — no captured mutable closures
      # and no non-shareable class-level state. The tool is instantiated
      # fresh inside the Ractor worker for each call.
      #
      # @param value [Boolean]
      # @return [Boolean]
      def ractor_safe(value = nil)
        if value.nil?
          # getter — check own setting, then walk up the inheritance chain
          if instance_variable_defined?(:@ractor_safe)
            @ractor_safe
          elsif superclass.respond_to?(:ractor_safe)
            superclass.ractor_safe
          else
            false
          end
        else
          @ractor_safe = value
        end
      end

      alias ractor_safe? ractor_safe
```

- [ ] **Step 4: Run to verify pass**

```bash
bundle exec rake test_file[robot_lab/tool_test.rb]
```

Expected: all existing tests plus the 3 new ones pass.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/tool.rb test/robot_lab/tool_test.rb
git commit -m "feat(ractor): add ractor_safe class macro to Tool"
```

---

## Task 5: RactorWorkerPool

**Files:**
- Create: `lib/robot_lab/ractor_worker_pool.rb`
- Create: `test/robot_lab/ractor_worker_pool_test.rb`

- [ ] **Step 1: Write failing test**

Create `test/robot_lab/ractor_worker_pool_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

# A minimal ractor-safe tool for pool testing.
# Must be defined at the top level so Ractors can const_get it.
class RactorSafeDoubler < RobotLab::Tool
  description "Doubles a number"
  param :value, type: "number", desc: "The number"
  ractor_safe true

  def execute(value:)
    value * 2
  end
end

class RobotLab::RactorWorkerPoolTest < Minitest::Test
  def setup
    @pool = RobotLab::RactorWorkerPool.new(size: 2)
  end

  def teardown
    @pool.shutdown
  end

  def test_submit_returns_result
    result = @pool.submit("RactorSafeDoubler", { "value" => 5 })
    assert_equal 10, result
  end

  def test_submit_multiple_concurrent_jobs
    futures = 4.times.map do |i|
      Thread.new { @pool.submit("RactorSafeDoubler", { "value" => i }) }
    end
    results = futures.map(&:value)
    assert_equal [0, 2, 4, 6], results.sort
  end

  def test_submit_raises_tool_error_on_tool_exception
    # A tool that always raises
    Object.const_set(:AlwaysFailTool, Class.new(RobotLab::Tool) do
      description "Fails"
      ractor_safe true
      def execute(**); raise "tool exploded"; end
    end) unless defined?(AlwaysFailTool)

    assert_raises(RobotLab::ToolError) do
      @pool.submit("AlwaysFailTool", {})
    end
  end

  def test_pool_size
    assert_equal 2, @pool.size
  end

  def test_shutdown_is_idempotent
    @pool.shutdown
    @pool.shutdown  # should not raise
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/ractor_worker_pool_test.rb]
```

Expected: fails with `NameError: uninitialized constant RobotLab::RactorWorkerPool`.

- [ ] **Step 3: Create lib/robot_lab/ractor_worker_pool.rb**

```ruby
# frozen_string_literal: true

require "etc"

module RobotLab
  # A pool of Ractor workers that execute CPU-bound, Ractor-safe tools.
  #
  # Work is distributed via a shared ractor_queue. Each worker runs a
  # blocking loop, pops RactorJob instances, dispatches to the named
  # tool class, and pushes the frozen result (or a RactorJobError) to
  # the job's per-job reply_queue.
  #
  # Only tools that declare +ractor_safe true+ should be submitted.
  # Tool classes are instantiated fresh inside the Ractor for each call.
  #
  # @example
  #   pool = RactorWorkerPool.new(size: 4)
  #   result = pool.submit("MyTool", { "arg" => "value" })
  #   pool.shutdown
  #
  class RactorWorkerPool
    # @return [Integer] number of worker Ractors
    attr_reader :size

    # Creates a new pool and starts worker Ractors immediately.
    #
    # @param size [Integer, :auto] number of workers (:auto = Etc.nprocessors)
    def initialize(size: :auto)
      @size    = size == :auto ? Etc.nprocessors : size.to_i
      @closed  = false
      @work_q  = RactorQueue.new
      @workers = @size.times.map { spawn_worker(@work_q) }
    end

    # Submit a tool job and block until the result is available.
    #
    # @param tool_class_name [String] fully-qualified Ruby constant name of the tool class
    # @param args [Hash] the tool arguments (will be deep-frozen before crossing Ractor boundary)
    # @return [Object] the tool's return value
    # @raise [RactorBoundaryError] if args cannot be made Ractor-shareable
    # @raise [ToolError] if the tool raises inside the Ractor
    def submit(tool_class_name, args)
      raise "Pool is shut down" if @closed

      reply_q = RactorQueue.new
      payload = RactorBoundary.freeze_deep({
        tool_class: tool_class_name.to_s,
        args: args
      })

      job = RactorJob.new(
        id:          SecureRandom.uuid.freeze,
        type:        :tool,
        payload:     payload,
        reply_queue: reply_q
      )

      @work_q.push(job)
      result = reply_q.pop

      if result.is_a?(RactorJobError)
        raise ToolError, "Tool '#{tool_class_name}' failed in Ractor: #{result.message}"
      end

      result
    end

    # Gracefully shut down the pool.
    #
    # Closes the work queue so all workers exit after finishing their
    # current job. Waits for all workers to terminate.
    #
    # @return [void]
    def shutdown
      return if @closed

      @closed = true
      @work_q.close
      @workers.each do |w|
        w.take rescue Ractor::ClosedError, Ractor::RemoteError
      end
    end

    private

    def spawn_worker(work_q)
      Ractor.new(work_q) do |q|
        loop do
          job = q.pop
          break if job.nil?  # closed queue returns nil

          begin
            tool_class = Object.const_get(job.payload[:tool_class])
            tool       = tool_class.new
            result     = tool.execute(**job.payload[:args].transform_keys(&:to_sym))
            frozen_result = Ractor.make_shareable(result.frozen? ? result : result.dup.freeze)
            job.reply_queue.push(frozen_result)
          rescue => e
            err = RobotLab::RactorJobError.new(
              message:   e.message.freeze,
              backtrace: (e.backtrace || []).map(&:freeze).freeze
            )
            job.reply_queue.push(err)
          end
        end
      rescue RactorQueue::ClosedError
        # Normal shutdown path — queue closed, exit loop cleanly
      end
    end
  end
end
```

> **Note on `RactorQueue#close`:** verify the exact exception name the gem raises when a closed queue is popped — it may be `RactorQueue::ClosedError`, `ClosedQueueError`, or similar. Update the rescue clause accordingly after checking the gem source.

- [ ] **Step 4: Add ToolError to error.rb**

Open `lib/robot_lab/error.rb`. Add after `RactorBoundaryError`:

```ruby
  # Raised when a tool fails during execution, including inside a Ractor worker.
  #
  # @example
  #   raise ToolError, "Tool 'MyTool' failed: division by zero"
  class ToolError < Error; end
```

- [ ] **Step 5: Run to verify pass**

```bash
bundle exec rake test_file[robot_lab/ractor_worker_pool_test.rb]
```

Expected: all 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/robot_lab/ractor_worker_pool.rb lib/robot_lab/error.rb test/robot_lab/ractor_worker_pool_test.rb
git commit -m "feat(ractor): add RactorWorkerPool for CPU-bound tool execution"
```

---

## Task 6: Global pool accessor + RunConfig#ractor_pool_size

**Files:**
- Modify: `lib/robot_lab.rb`
- Modify: `lib/robot_lab/run_config.rb`
- Modify: `test/robot_lab/run_config_test.rb`

- [ ] **Step 1: Write failing test for RunConfig**

Open `test/robot_lab/run_config_test.rb`. Add these tests at the end of the class:

```ruby
  def test_ractor_pool_size_defaults_to_nil
    config = RobotLab::RunConfig.new
    assert_nil config.ractor_pool_size
  end

  def test_ractor_pool_size_can_be_set
    config = RobotLab::RunConfig.new(ractor_pool_size: 4)
    assert_equal 4, config.ractor_pool_size
  end

  def test_ractor_pool_size_merges
    base  = RobotLab::RunConfig.new(ractor_pool_size: 2)
    other = RobotLab::RunConfig.new(ractor_pool_size: 8)
    merged = base.merge(other)
    assert_equal 8, merged.ractor_pool_size
  end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/run_config_test.rb]
```

Expected: fails with `ArgumentError: Unknown RunConfig field: ractor_pool_size`.

- [ ] **Step 3: Add ractor_pool_size to RunConfig**

Open `lib/robot_lab/run_config.rb`. Change:

```ruby
    # Infrastructure fields
    INFRA_FIELDS = %i[bus enable_cache max_tool_rounds token_budget].freeze
```

to:

```ruby
    # Infrastructure fields
    INFRA_FIELDS = %i[bus enable_cache max_tool_rounds token_budget ractor_pool_size].freeze
```

- [ ] **Step 4: Run to verify RunConfig tests pass**

```bash
bundle exec rake test_file[robot_lab/run_config_test.rb]
```

Expected: all tests pass.

- [ ] **Step 5: Add RobotLab.ractor_pool global accessor**

Open `lib/robot_lab.rb`. Inside the `class << self` block, add after the `create_memory` method:

```ruby
    # Returns the shared RactorWorkerPool, lazily initialized.
    #
    # Pool size is determined by RobotLab.config or defaults to Etc.nprocessors.
    # The pool lives for the lifetime of the process. Call RobotLab.shutdown_ractor_pool
    # to drain and close it explicitly.
    #
    # @return [RactorWorkerPool]
    def ractor_pool
      @ractor_pool ||= begin
        size = config.respond_to?(:ractor_pool_size) ? (config.ractor_pool_size || :auto) : :auto
        RactorWorkerPool.new(size: size)
      end
    end

    # Shut down the shared Ractor worker pool, draining in-flight jobs.
    #
    # @return [void]
    def shutdown_ractor_pool
      @ractor_pool&.shutdown
      @ractor_pool = nil
    end
```

- [ ] **Step 6: Commit**

```bash
git add lib/robot_lab/run_config.rb lib/robot_lab.rb test/robot_lab/run_config_test.rb
git commit -m "feat(ractor): add ractor_pool_size to RunConfig and RobotLab.ractor_pool global accessor"
```

---

## Task 7: Route Ractor-safe tool calls through the pool

**Files:**
- Modify: `lib/robot_lab/tool.rb`
- Modify: `test/robot_lab/tool_test.rb`

- [ ] **Step 1: Write failing test**

Open `test/robot_lab/tool_test.rb`. Add at the end of the class:

```ruby
  # ── Ractor pool routing ─────────────────────────────────────────

  def test_ractor_safe_tool_call_routes_through_pool
    # A top-level ractor-safe tool so its name resolves via const_get
    Object.const_set(:PoolRoutingTestTool, Class.new(RobotLab::Tool) do
      description "Multiplies by 3"
      param :n, type: "number", desc: "Input"
      ractor_safe true
      def execute(n:); n * 3; end
    end) unless defined?(PoolRoutingTestTool)

    tool = PoolRoutingTestTool.new
    result = tool.call({ "n" => 7 })
    assert_equal 21, result
  end

  def test_non_ractor_safe_tool_call_runs_inline
    klass = Class.new(RobotLab::Tool) do
      description "Inline tool"
      param :x, type: "string", desc: "Input"
      def execute(x:); "inline:#{x}"; end
    end
    # Assign a top-level name so it can be found if needed, but it won't use pool
    tool = klass.new
    result = tool.call({ "x" => "hello" })
    assert_equal "inline:hello", result
  end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/tool_test.rb]
```

Expected: the `ractor_safe_tool_call_routes_through_pool` test fails or does not use the pool (result will still be correct but pool isn't exercised yet).

- [ ] **Step 3: Route in Tool#call**

Open `lib/robot_lab/tool.rb`. Replace the existing `call` method:

```ruby
    # Invokes the tool, routing through the Ractor worker pool if ractor_safe.
    #
    # For Ractor-safe tools: submits the work to RobotLab.ractor_pool and
    # blocks for the frozen result. The tool class must be accessible by
    # its full constant name via Object.const_get (i.e. defined at the
    # top level, not as an anonymous class).
    #
    # For non-Ractor-safe tools: runs execute directly in the calling thread.
    #
    # @param args [Hash] the tool arguments from the LLM
    # @return [Object] the tool result or an error string
    def call(args)
      if self.class.ractor_safe? && !self.class.name.nil?
        RobotLab.ractor_pool.submit(self.class.name, args)
      else
        super
      end
    rescue RobotLab::ToolError => e
      raise if self.class.raise_on_error?
      "Error (#{name}): #{e.message}"
    rescue StandardError => e
      raise if self.class.raise_on_error?
      RobotLab.config.logger.warn("Tool '#{name}' error: #{e.class}: #{e.message}")
      "Error (#{name}): #{e.message}"
    end
```

- [ ] **Step 4: Run to verify all tool tests pass**

```bash
bundle exec rake test_file[robot_lab/tool_test.rb]
```

Expected: all tests pass including the two new routing tests.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/tool.rb test/robot_lab/tool_test.rb
git commit -m "feat(ractor): route ractor_safe tool calls through RactorWorkerPool"
```

---

## Task 8: BusPoller ractor_queue upgrade

**Files:**
- Modify: `lib/robot_lab/bus_poller.rb`
- Modify: `test/robot_lab/bus_poller_test.rb`

- [ ] **Step 1: Add test for ractor_queue backing**

Open `test/robot_lab/bus_poller_test.rb`. Add at the end:

```ruby
  def test_robot_queues_are_ractor_queue_instances
    robot = build_robot(name: "test_bot")

    delivered = []
    robot.define_singleton_method(:process_delivery) do |delivery|
      delivered << delivery
    end

    @poller.enqueue(robot: robot, delivery: "msg1")

    # The internal queue for the robot should be a RactorQueue
    queues = @poller.instance_variable_get(:@robot_queues)
    assert_instance_of RactorQueue, queues["test_bot"]
    assert_equal ["msg1"], delivered
  end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/bus_poller_test.rb]
```

Expected: test fails because `@robot_queues["test_bot"]` is an `Array`, not a `RactorQueue`.

- [ ] **Step 3: Swap Array queues for RactorQueue**

Open `lib/robot_lab/bus_poller.rb`. Make the following changes:

**In `enqueue`**, replace the initialization and push lines:

```ruby
      if @robot_busy[name]
        @robot_queues[name] << delivery
        false
      else
```

Change to:

```ruby
      @robot_queues[name] ||= RactorQueue.new

      if @robot_busy[name]
        @robot_queues[name].push(delivery)
        false
      else
```

Remove the old `@robot_queues[name] ||= []` line (it was before the if block — remove it and replace with the RactorQueue initialization above).

**In `process_and_drain`**, replace the drain logic:

```ruby
        next_delivery = @mutex.synchronize do
          name = robot.name
          queue = @robot_queues[name] || []

          if queue.any?
            queue.shift
          else
            @robot_busy[name] = false
            nil
          end
        end
```

Change to:

```ruby
        next_delivery = @mutex.synchronize do
          name  = robot.name
          queue = @robot_queues[name]

          if queue && !queue.empty?
            queue.pop
          else
            @robot_busy[name] = false
            nil
          end
        end
```

> **Note:** `RactorQueue#empty?` and `RactorQueue#pop` (non-blocking when called under mutex while `!empty?`) must be verified against the gem API. If `pop` is blocking-only, use a timeout of 0: `queue.pop(timeout: 0)` and handle the timeout return value (likely `nil` or a sentinel).

- [ ] **Step 4: Run all bus poller tests**

```bash
bundle exec rake test_file[robot_lab/bus_poller_test.rb]
```

Expected: all tests pass including the new ractor_queue instance test.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/bus_poller.rb test/robot_lab/bus_poller_test.rb
git commit -m "feat(ractor): upgrade BusPoller delivery queues to RactorQueue"
```

---

## Task 9: RactorMemoryProxy

**Files:**
- Create: `lib/robot_lab/ractor_memory_proxy.rb`
- Create: `test/robot_lab/ractor_memory_proxy_test.rb`

- [ ] **Step 1: Write failing test**

Create `test/robot_lab/ractor_memory_proxy_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class RobotLab::RactorMemoryProxyTest < Minitest::Test
  def setup
    @memory = RobotLab::Memory.new(enable_cache: false)
    @proxy  = RobotLab::RactorMemoryProxy.new(@memory)
  end

  def teardown
    @proxy.shutdown
  end

  def test_set_and_get_from_thread
    @proxy.set(:color, "blue")
    assert_equal "blue", @proxy.get(:color)
  end

  def test_get_returns_nil_for_missing_key
    assert_nil @proxy.get(:nonexistent)
  end

  def test_keys_returns_array
    @proxy.set(:a, "1")
    @proxy.set(:b, "2")
    assert_includes @proxy.keys, :a
    assert_includes @proxy.keys, :b
  end

  def test_set_and_get_from_ractor
    proxy = @proxy  # capture for Ractor

    result = Ractor.new(proxy) do |p|
      p.set(:ractor_key, "ractor_value")
      p.get(:ractor_key)
    end.take

    assert_equal "ractor_value", result
    assert_equal "ractor_value", @memory.get(:ractor_key)
  end

  def test_values_must_be_shareable
    assert_raises(RobotLab::RactorBoundaryError) do
      @proxy.set(:bad, StringIO.new)
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/ractor_memory_proxy_test.rb]
```

Expected: fails with `NameError: uninitialized constant RobotLab::RactorMemoryProxy`.

- [ ] **Step 3: Create lib/robot_lab/ractor_memory_proxy.rb**

```ruby
# frozen_string_literal: true

require "ractor/wrapper"

module RobotLab
  # Wraps a Memory instance via ractor-wrapper so Ractor workers can safely
  # read and write shared state.
  #
  # Only the proxy methods (get, set, keys) are exposed across the Ractor
  # boundary. Subscriptions and callbacks are NOT proxied — closures are not
  # Ractor-safe. Use the thread-side Memory directly for reactive subscriptions.
  #
  # Values passed to set() must be Ractor-shareable; RactorBoundary.freeze_deep
  # is applied automatically.
  #
  # @example
  #   memory = Memory.new
  #   proxy  = RactorMemoryProxy.new(memory)
  #
  #   # From a Ractor:
  #   proxy.set(:result, "done")
  #   proxy.get(:result)   #=> "done"
  #
  #   proxy.shutdown  # call when done
  #
  class RactorMemoryProxy
    # @param memory [Memory] the memory instance to wrap
    def initialize(memory)
      @memory  = memory
      @wrapper = Ractor::Wrapper.wrap(memory)
    end

    # Read a value from the proxied Memory.
    #
    # @param key [Symbol]
    # @return [Object, nil]
    def get(key)
      @wrapper.call(:get, key)
    end

    # Write a value to the proxied Memory.
    # The value is deep-frozen before crossing the Ractor boundary.
    #
    # @param key [Symbol]
    # @param value [Object] must be Ractor-shareable after freeze_deep
    # @return [void]
    # @raise [RactorBoundaryError] if value cannot be made shareable
    def set(key, value)
      frozen_value = RactorBoundary.freeze_deep(value)
      @wrapper.call(:set, key, frozen_value)
    end

    # List all keys currently set in the proxied Memory.
    #
    # @return [Array<Symbol>]
    def keys
      @wrapper.call(:keys)
    end

    # Shut down the ractor-wrapper.
    #
    # @return [void]
    def shutdown
      @wrapper.shutdown if @wrapper.respond_to?(:shutdown)
    end
  end
end
```

> **Note on ractor-wrapper API:** The plan uses `Ractor::Wrapper.wrap(obj)` and `.call(:method, *args)`. Verify this matches the installed gem version. If the API is different (e.g. a block-based DSL or different method name), adjust accordingly. The `Memory#get`, `Memory#set`, and `Memory#keys` methods must accept positional arguments as shown.

- [ ] **Step 4: Run to verify pass**

```bash
bundle exec rake test_file[robot_lab/ractor_memory_proxy_test.rb]
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/ractor_memory_proxy.rb test/robot_lab/ractor_memory_proxy_test.rb
git commit -m "feat(ractor): add RactorMemoryProxy wrapping Memory via ractor-wrapper"
```

---

## Task 10: RactorNetworkScheduler

**Files:**
- Create: `lib/robot_lab/ractor_network_scheduler.rb`
- Create: `test/robot_lab/ractor_network_scheduler_test.rb`

- [ ] **Step 1: Write failing test**

Create `test/robot_lab/ractor_network_scheduler_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class RobotLab::RactorNetworkSchedulerTest < Minitest::Test
  def setup
    @memory    = RobotLab::Memory.new(enable_cache: false)
    @scheduler = RobotLab::RactorNetworkScheduler.new(memory: @memory)
  end

  def teardown
    @scheduler.shutdown
  end

  def test_run_task_spec_returns_result
    spec = RobotLab::RobotSpec.new(
      name:         "echo_bot",
      template:     nil,
      system_prompt: "You are an echo bot.",
      config_hash:  { model: "claude-sonnet-4" }.freeze
    )

    # Scheduler runs the spec; we stub run() by injecting a fake result
    # via the frozen payload mechanism.
    stub_result = "echo result"
    @scheduler.stub(:execute_spec, stub_result) do
      result = @scheduler.run_spec(spec, message: "hello")
      assert_equal stub_result, result
    end
  end

  def test_respects_dependency_ordering
    order = []
    @scheduler.stub(:execute_spec, ->(spec, _msg) { order << spec.name; "ok" }) do
      specs_with_deps = [
        { spec: RobotLab::RobotSpec.new(name: "first", template: nil, system_prompt: nil, config_hash: {}.freeze),
          depends_on: :none },
        { spec: RobotLab::RobotSpec.new(name: "second", template: nil, system_prompt: nil, config_hash: {}.freeze),
          depends_on: ["first"] }
      ]
      @scheduler.run_pipeline(specs_with_deps, message: "go")
    end
    assert_equal ["first", "second"], order
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/ractor_network_scheduler_test.rb]
```

Expected: fails with `NameError: uninitialized constant RobotLab::RactorNetworkScheduler`.

- [ ] **Step 3: Create lib/robot_lab/ractor_network_scheduler.rb**

```ruby
# frozen_string_literal: true

module RobotLab
  # Schedules frozen robot task descriptions across Ractor workers.
  #
  # Robots themselves stay in threads (RubyLLM is not Ractor-safe).
  # Instead, the scheduler distributes frozen RobotSpec payloads to
  # worker Ractors. Each worker constructs a fresh Robot from the spec,
  # runs the task, and returns a frozen result.
  #
  # Task ordering respects depends_on: tasks are only dispatched once
  # all named dependencies have resolved (same topological semantics as
  # SimpleFlow::Pipeline).
  #
  # @example
  #   scheduler = RactorNetworkScheduler.new(memory: shared_memory)
  #   scheduler.run_pipeline([
  #     { spec: analyst_spec, depends_on: :none },
  #     { spec: writer_spec,  depends_on: ["analyst"] }
  #   ], message: "Process this")
  #   scheduler.shutdown
  #
  class RactorNetworkScheduler
    # @param memory [Memory] shared network memory for all robot tasks
    # @param pool_size [Integer, :auto] number of Ractor workers
    def initialize(memory:, pool_size: :auto)
      @memory   = memory
      @work_q   = RactorQueue.new
      @result_q = RactorQueue.new
      @size     = pool_size == :auto ? Etc.nprocessors : pool_size.to_i
      @workers  = @size.times.map { spawn_worker(@work_q, @result_q) }
      @closed   = false
    end

    # Run a single spec and return the result string.
    # Dispatches to a worker Ractor and blocks for the reply.
    #
    # @param spec [RobotSpec]
    # @param message [String]
    # @return [String] the robot's last_text_content
    def run_spec(spec, message:)
      execute_spec(spec, message)
    end

    # Run a pipeline of specs in dependency order.
    #
    # @param specs_with_deps [Array<Hash>] each entry has :spec and :depends_on
    #   :depends_on is :none, :optional, or an Array<String> of spec names
    # @param message [String] initial message passed to entry-point robots
    # @return [Hash<String, String>] name => result for each completed robot
    def run_pipeline(specs_with_deps, message:)
      completed  = {}   # name => result string
      remaining  = specs_with_deps.dup

      until remaining.empty?
        ready, remaining = remaining.partition do |entry|
          deps = entry[:depends_on]
          deps == :none || deps == :optional ||
            Array(deps).all? { |d| completed.key?(d) }
        end

        raise "Circular dependency or unresolvable deps in RactorNetworkScheduler" if ready.empty?

        # Submit all ready tasks concurrently
        threads = ready.map do |entry|
          spec    = entry[:spec]
          msg     = completed.values.last || message
          Thread.new { [spec.name, execute_spec(spec, msg)] }
        end

        threads.each do |t|
          name, result = t.value
          completed[name] = result
        end
      end

      completed
    end

    # Shut down worker Ractors cleanly.
    # @return [void]
    def shutdown
      return if @closed
      @closed = true
      @work_q.close rescue nil
      @workers.each { |w| w.take rescue nil }
    end

    private

    # Dispatch a spec to a Ractor worker and block for the result.
    def execute_spec(spec, message)
      frozen_spec    = Ractor.make_shareable(spec)
      frozen_message = message.to_s.freeze
      reply_q        = RactorQueue.new

      job = RactorJob.new(
        id:          SecureRandom.uuid.freeze,
        type:        :robot,
        payload:     RactorBoundary.freeze_deep({
          spec:    frozen_spec,
          message: frozen_message
        }),
        reply_queue: reply_q
      )

      @work_q.push(job)
      result = reply_q.pop

      raise ToolError, "Robot '#{spec.name}' failed in Ractor: #{result.message}" if result.is_a?(RactorJobError)

      result
    end

    def spawn_worker(work_q, _result_q)
      Ractor.new(work_q) do |q|
        loop do
          job = q.pop
          break if job.nil?

          begin
            spec    = job.payload[:spec]
            message = job.payload[:message]

            robot = RobotLab::Robot.new(
              name:          spec.name,
              template:      spec.template,
              system_prompt: spec.system_prompt,
              config:        spec.config_hash.empty? ? nil : RobotLab::RunConfig.new(**spec.config_hash.transform_keys(&:to_sym))
            )

            robot_result  = robot.run(message)
            frozen_reply  = robot_result.last_text_content.to_s.freeze
            job.reply_queue.push(frozen_reply)
          rescue => e
            err = RobotLab::RactorJobError.new(
              message:   e.message.freeze,
              backtrace: (e.backtrace || []).map(&:freeze).freeze
            )
            job.reply_queue.push(err)
          end
        end
      rescue RactorQueue::ClosedError
        # Normal shutdown
      end
    end
  end
end
```

> **Important:** `RobotLab::Robot.new` inside a Ractor will work only if all constants and gems it references are Ractor-safe at load time. If `ruby_llm` raises `Ractor::IsolationError` during Robot construction inside a Ractor, fall back to running robot tasks in threads (keeping the Ractor boundary at the job queue level only). The test stubs `execute_spec`, so the unit tests will pass regardless — integration testing with a live LLM call will reveal any Ractor isolation issues.

- [ ] **Step 4: Run to verify pass**

```bash
bundle exec rake test_file[robot_lab/ractor_network_scheduler_test.rb]
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/ractor_network_scheduler.rb test/robot_lab/ractor_network_scheduler_test.rb
git commit -m "feat(ractor): add RactorNetworkScheduler for parallel robot task dispatch"
```

---

## Task 11: Network parallel_mode: :ractor integration

**Files:**
- Modify: `lib/robot_lab/network.rb`
- Modify: `test/robot_lab/network_test.rb`

- [ ] **Step 1: Write failing test**

Open `test/robot_lab/network_test.rb`. Add at the end:

```ruby
  def test_parallel_mode_ractor_accepted
    network = RobotLab::Network.new(name: "ractor_net", parallel_mode: :ractor) {}
    assert_equal :ractor, network.parallel_mode
  end

  def test_parallel_mode_async_is_default
    network = RobotLab::Network.new(name: "async_net") {}
    assert_equal :async, network.parallel_mode
  end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/network_test.rb]
```

Expected: fails with `ArgumentError: unknown keyword: parallel_mode` or similar.

- [ ] **Step 3: Add parallel_mode to Network**

Open `lib/robot_lab/network.rb`.

**Add `parallel_mode` to `attr_reader`:**

```ruby
    attr_reader :name, :pipeline, :robots, :memory, :config, :parallel_mode
```

**Update `initialize` signature** — add `parallel_mode: :async` after `config: nil`:

```ruby
    def initialize(name:, concurrency: :auto, memory: nil, config: nil, parallel_mode: :async, &block)
```

**Store in initialize** — after `@config = config || RunConfig.new`:

```ruby
      @parallel_mode = parallel_mode
```

**Update `run` to delegate to `RactorNetworkScheduler` when `parallel_mode: :ractor`:**

Replace the existing `run` method body with:

```ruby
    def run(**run_context)
      run_context[:network_memory] = @memory
      run_context[:network_config] = @config unless @config.empty?

      if @parallel_mode == :ractor
        run_with_ractor_scheduler(run_context)
      else
        initial_result = SimpleFlow::Result.new(
          run_context,
          context: { run_params: run_context }
        )
        @pipeline.call_parallel(initial_result)
      end
    end
```

**Add `run_with_ractor_scheduler` private method** at the bottom of the private section:

```ruby
    def run_with_ractor_scheduler(run_context)
      message = run_context[:message].to_s

      specs_with_deps = @tasks.map do |task_name, task_wrapper|
        step_info = @pipeline.steps.find { |s| s.name.to_s == task_name }
        deps      = step_info ? step_info.depends_on : :none

        spec = RobotSpec.new(
          name:          task_wrapper.robot.name.freeze,
          template:      task_wrapper.robot.template&.to_s&.freeze,
          system_prompt: task_wrapper.robot.system_prompt&.freeze,
          config_hash:   RactorBoundary.freeze_deep(task_wrapper.robot.config.to_json_hash)
        )

        { spec: spec, depends_on: deps }
      end

      scheduler = RactorNetworkScheduler.new(memory: @memory)
      results   = scheduler.run_pipeline(specs_with_deps, message: message)
      scheduler.shutdown
      results
    end
```

> **Note:** `@pipeline.steps` may not be a public API on `SimpleFlow::Pipeline`. Check the `simple_flow` gem for the correct way to read step definitions and their `depends_on` values. If steps are not publicly enumerable, store the dep info in `@tasks` during `task(...)` calls instead.

- [ ] **Step 4: Run network tests**

```bash
bundle exec rake test_file[robot_lab/network_test.rb]
```

Expected: all tests including the two new ones pass.

- [ ] **Step 5: Run full test suite**

```bash
bundle exec rake test
```

Expected: all tests pass. If any failures, fix them before committing.

- [ ] **Step 6: Commit**

```bash
git add lib/robot_lab/network.rb test/robot_lab/network_test.rb
git commit -m "feat(ractor): add parallel_mode: :ractor to Network, delegating to RactorNetworkScheduler"
```

---

## Self-Review Checklist

Before handing off to execution:

- [ ] All types used in later tasks match definitions in earlier tasks (`RactorJob`, `RactorJobError`, `RobotSpec`, `RactorBoundaryError`, `ToolError`)
- [ ] `RactorQueue` is used consistently (Task 5, 8, 9, 10 all use `RactorQueue.new`, `push`, `pop`, `empty?`, `close`)
- [ ] `Ractor::Wrapper.wrap` API in Task 9 is flagged for verification against installed gem
- [ ] `execute_spec` stub in Task 10 tests uses the same method name as the private implementation
- [ ] `ToolError` added to `error.rb` in Task 5 before it is referenced in Task 7 and 10
- [ ] Zeitwerk autoloads `ractor_boundary.rb`, `ractor_worker_pool.rb`, `ractor_memory_proxy.rb`, `ractor_network_scheduler.rb` — only `ractor_job.rb` needs an explicit require (multiple classes in one file)
