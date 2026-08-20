#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 35: Hooks Architecture with robot_lab-xyzzy
#
# Demonstrates the hook handler class pattern. Hooks are named classes that
# inherit from RobotLab::Hook and implement class methods for each lifecycle
# phase they care about. All hooks are Ractor-safe by default.
#
# Usage:
#   bundle exec ruby examples/35_hooks.rb

require_relative "common"

# RobotLab::Hook has no logger accessor — handlers own their own output.
# xyzzy.rb freezes its log destination into a constant at load time, so the
# redirect has to happen before the require.
XYZZY_LOG = File.join(__dir__, "xyzzy_hooks.log")
ENV["XYZZY_LOG_PATH"] = XYZZY_LOG

require_relative "xyzzy"

# ---------------------------------------------------------------------------
# Handler classes used in this demo
# ---------------------------------------------------------------------------

class RuntimeDemoHook < RobotLab::Hook
  self.namespace = :runtime_demo

  def self.after_run(ctx)
    ctx.local.reply_seen = ctx.response.reply
  end
end

class LocalDemoHook < RobotLab::Hook
  self.namespace = :local_demo

  def self.before_run(ctx)
    ctx.local.note = "local robot hook state"
    ctx.local.demo = "robot_run"
  end
end

class PerfHook < RobotLab::Hook
  self.namespace = :perf
  @timings = []
  @mutex = Mutex.new

  class << self
    def reset!
      @mutex.synchronize { @timings = [] }
    end

    def timings
      @mutex.synchronize { @timings.dup }
    end

    def around_run(ctx, &block)
      t0     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = block.call
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000).round(3)
      @mutex.synchronize { @timings << elapsed }
      puts "  [perf]      #{ctx.request.inspect} — #{elapsed}ms"
      result
    end
  end
end

class GenerationTracerHook < RobotLab::Hook
  self.namespace = :tracer

  def self.before_llm_generation(ctx)
    puts "  [tracer]    llm_generation start  request=#{ctx.request.inspect}"
  end

  def self.after_llm_generation(ctx)
    msg = ctx.generation_response
    puts "  [tracer]    llm_generation done   model=#{msg&.model_id}  tokens=#{msg&.output_tokens}"
  end
end

class GenCacheHook < RobotLab::Hook
  self.namespace = :gen_cache
  @cache = {}
  @mutex = Mutex.new
  @call_count = 0

  class << self
    def reset!
      @mutex.synchronize do
        @cache = {}
        @call_count = 0
      end
    end

    def call_count
      @mutex.synchronize { @call_count }
    end

    def around_llm_generation(ctx, &block)
      cached = @mutex.synchronize { @cache[ctx.request] }
      if cached
        puts "  [gen_cache] HIT  — skipping LLM"
        cached
      else
        puts "  [gen_cache] MISS — calling LLM"
        @mutex.synchronize { @call_count += 1 }
        block.call.tap { |r| @mutex.synchronize { @cache[ctx.request] = r } }
      end
    end
  end
end

class NetworkDemoHook < RobotLab::Hook
  self.namespace = :network_demo

  def self.before_task(ctx)
    ctx.local.task_note = "network-scoped task hook"
  end
end

# ---------------------------------------------------------------------------

HookDemoResponse = Data.define(:content, :tool_calls, :stop_reason) do
  def initialize(content:, tool_calls: nil, stop_reason: "end_turn")
    super
  end
end

class HookDemoTool < RobotLab::Tool
  description "Returns a deterministic hook demo value"
  param :label, type: "string", desc: "The label to echo"

  def execute(label:)
    { label: label, status: "handled by HookDemoTool" }
  end
end

class HookDemo
  def run
    banner "Hooks Architecture with robot_lab-xyzzy"

    explain_setup
    run_robot
    run_llm_loop
    run_tool
    run_network
    run_error

    hr
    puts "Hook demo complete."
  end

  private

  def explain_setup
    section "Extension Registration"
    puts <<~TEXT
      xyzzy.rb is a single-file hook extension loaded from examples/.

      It is a RobotLab::Hook subclass registered under namespace :#{RobotLab::Xyzzy.namespace}.
      stdout  : [xyzzy] timestamp hook_name  (one line per call)
      logfile : full context snapshot  →  #{XYZZY_LOG}
    TEXT
  end

  def run_robot
    section "Robot Run Hooks"
    robot = hooked_robot("hook_demo_robot")
    robot.on(LocalDemoHook)

    result = robot.run("show the hook pipeline", hooks: RuntimeDemoHook)

    puts "Robot reply: #{result.reply}"
  end

  def run_llm_loop
    section "LLM Request/Response Loop"
    puts <<~TEXT
      Demonstrates before/around/after_llm_generation hooks.
      GenCacheHook implements around_llm_generation: on a cache hit the block
      (the real LLM call) is never invoked. PerfHook times each robot.run call.
    TEXT

    GenCacheHook.reset!
    PerfHook.reset!

    puts "  provider=#{LLM[:default].provider}  model=#{LLM[:default].model}\n\n"

    # with_model alone would leave the provider unset, and an Ollama model is
    # not in RubyLLM's registry — pass provider and model together.
    robot = RobotLab.build(
      name: "loop_demo_robot",
      system_prompt: "You are a helpful assistant. Answer every question in one concise sentence.",
      **llm_opts
    )

    robot.on(PerfHook)
    robot.on(GenerationTracerHook)
    robot.on(GenCacheHook)

    queries = [
      "what is the boiling point of water?",
      "what is 6 * 7?",
      "what is the boiling point of water?",
      "what is 6 * 7?"
    ]

    queries.each_with_index do |query, i|
      puts "\n--- query #{i + 1}: #{query.inspect} ---"
      result = robot.run(query)
      puts "  reply:      #{result.reply}"
    end

    timings     = PerfHook.timings
    cache_hits  = queries.size - GenCacheHook.call_count
    avg_ms      = (timings.sum / timings.size).round(3)
    puts "\n--- summary ---"
    puts "  robot.run calls : #{queries.size}"
    puts "  LLM calls made  : #{GenCacheHook.call_count}  (#{cache_hits} served from gen_cache)"
    puts "  avg run time    : #{avg_ms}ms"
  end

  def run_tool
    section "Tool Call Hooks"
    tool   = HookDemoTool.new
    result = tool.call({ "label" => "tool hook payload" })
    puts "Tool result: #{result.inspect}"
  end

  def run_network
    section "Network and Task Hooks"
    network = RobotLab::Network.new(name: "hook_demo_network")
    network.on(NetworkDemoHook)
    network.task(:summarize, hooked_robot("network_worker"), depends_on: :none)

    result = network.run(message: "summarize hook activity")
    reply = result.respond_to?(:reply) ? result.reply : result&.value&.reply
    puts "Network result: #{reply}"
  end

  def run_error
    section "Error Hook"
    failing_robot = RobotLab.build(name: "failing_hook_robot", system_prompt: "raise", **llm_opts)
    # Robot#chat is a public reader — no need to reach for @chat.
    failing_robot.chat.define_singleton_method(:ask) do |_message = nil, **_kwargs|
      raise "planned hook demo failure"
    end

    failing_robot.run("trigger the on_error hook")
  rescue RuntimeError => e
    puts "Caught expected error: #{e.message}"
  end

  # Stubs the chat so the hook pipeline is exercised deterministically with no
  # LLM traffic. Robot#chat is public, so this needs no ivar surgery.
  def hooked_robot(name)
    RobotLab.build(name: name, system_prompt: "deterministic hook demo", **llm_opts).tap do |robot|
      robot.chat.define_singleton_method(:ask) do |message = nil, **_kwargs, &_block|
        HookDemoResponse.new(content: "deterministic response to #{message.inspect}")
      end
    end
  end
end

HookDemo.new.run
