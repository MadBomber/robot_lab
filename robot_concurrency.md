# Ruby Concurrency Review — RobotLab

Source: https://paolino.me/ruby-concurrency-what-actually-happens/

## What Applies to RobotLab

### 1. You're Already in the Right Model — Lean Into It

RobotLab uses `async (~> 2.0)`, which is exactly the fiber-based scheduler the article describes. LLM calls are pure I/O-bound work (HTTP streaming), so fibers are the correct and lowest-cost primitive. The article validates this architecture choice. No changes needed here — but be deliberate about not mixing blocking thread-style calls into the `Async` reactor unnecessarily.

### 2. The Ractor Caution Is Real (Recent Commit: `feat(ractor-parallelism)`)

The article is clear: Ractors in Ruby 4.0 are still experimental and practically incompatible with gems that use global state. RobotLab's dependencies (`ruby_llm`, `prompt_manager`, `zeitwerk`) almost certainly use global state. Worth auditing whether the new Ractor code hits `Ractor::IsolationError` under realistic load. The article's recommendation: **use Processes** for CPU parallelism if Rails-style gems are involved.

### 3. The `Waiter` Class May Be Misfit in Fiber Context

`lib/robot_lab/waiter.rb` uses a condition variable (thread primitive) for blocking gets on `Memory`. Inside an `Async` reactor, blocking a fiber with a condition variable stalls the entire reactor thread. The fiber-native equivalent is `Async::Condition` or `Async::Semaphore`. If `Memory#get(wait:)` is ever called from within an `Async` block, this is a latent deadlock risk.

### 4. Parallel Network Execution — Check the Primitive

`call_parallel()` in `Network` (built on `SimpleFlow::Pipeline`) — if it spawns OS threads rather than async tasks, you get heavier overhead than necessary for I/O-bound robot calls. The article's guidance: for I/O work, fiber-based `Async::Barrier` with concurrent tasks is 10-20x cheaper than threads.

### 5. Resource Semaphores for Parallel Networks

When a Network runs multiple robots concurrently, each making LLM API calls, you can exhaust API rate limits or connection pools with no back-pressure. The article's semaphore pattern applies directly — cap in-flight robot tasks to match your API tier's concurrency limit. This is worth adding to `RunConfig` as a `max_concurrent_robots` infra field.

### 6. Colorless Concurrency — This Is Already Your Story

The article's main point about Ruby fibers being "colorless" (no `async/await` propagation required) is directly reflected in how `robot.run("...")` stays synchronous-looking whether run standalone or in a parallel network. This is an underappreciated design strength worth highlighting in docs/README.

---

## Summary

The async/fiber architecture is correct for LLM I/O work. The two actionable concerns are:

1. **Audit the Ractor code** for isolation errors with gem dependencies (`ruby_llm`, `prompt_manager`, `zeitwerk`).
2. **Check `Waiter`** (condition variable in `lib/robot_lab/waiter.rb`) — if called inside an `Async` reactor block, replace with `Async::Condition` to avoid stalling the reactor.
