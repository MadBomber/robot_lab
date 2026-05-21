#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 35: Hooks Architecture with robot_lab-xyzzy
#
# Demonstrates the new hook architecture using the robot_lab-xyzzy test
# extension. The extension registers for every hook and logs each callback
# with the context object it receives.
#
# Usage:
#   bundle exec ruby examples/35_hooks.rb

require_relative "common"

xyzzy_lib = File.expand_path("../../robot_lab-xyzzy/lib", __dir__)
$LOAD_PATH.unshift(xyzzy_lib) unless $LOAD_PATH.include?(xyzzy_lib)

require "robot_lab/xyzzy"

class CompactHookLogger
  def info(message)
    puts message
  end
end

module CompactHookSnapshot
  module_function

  def call(context)
    case context
    when RobotLab::RunHookContext
      run_context(context)
    when RobotLab::ToolCallHookContext
      tool_context(context)
    when RobotLab::NetworkRunHookContext
      network_context(context)
    when RobotLab::TaskHookContext
      task_context(context)
    else
      context.respond_to?(:to_h) ? context.to_h : context.inspect
    end
  end

  def run_context(context)
    {
      event: context.event,
      robot: context.robot&.name,
      network: context.network&.name,
      task: context.task&.name,
      request: context.request,
      response: context.response&.reply,
      error: context.error&.message,
      metadata: context.metadata.to_h
    }
  end

  def tool_context(context)
    {
      event: context.event,
      tool_name: context.tool_name,
      tool_args: context.tool_args,
      tool_result: context.tool_result,
      tool_error: context.tool_error&.message,
      metadata: context.metadata.to_h
    }
  end

  def network_context(context)
    {
      event: context.event,
      network: context.network&.name,
      context: summarize_hash(context.context),
      result: result_summary(context.result),
      error: context.error&.message,
      metadata: context.metadata.to_h
    }
  end

  def task_context(context)
    {
      event: context.event,
      network: context.network&.name,
      task_name: context.task_name,
      robot: context.robot&.name,
      result: result_summary(context.result),
      error: context.error&.message,
      metadata: context.metadata.to_h
    }
  end

  def summarize_hash(value)
    return value unless value.is_a?(Hash)

    value.transform_values do |item|
      case item
      when RobotLab::Network then item.name
      when RobotLab::Memory then "RobotLab::Memory"
      else item
      end
    end
  end

  def result_summary(result)
    case
    when result.nil?
      nil
    when result.respond_to?(:reply)
      result.reply
    when result.respond_to?(:value)
      result_summary(result.value)
    else
      result.class.name
    end
  end
end

RobotLab::Xyzzy.logger = CompactHookLogger.new
RobotLab::Xyzzy.define_singleton_method(:context_snapshot) { |context| CompactHookSnapshot.call(context) }

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
        robot_lab-xyzzy has been loaded from:
          #{xyzzy_lib}

        It registers namespace :#{RobotLab::Xyzzy::NAMESPACE} for every hook.
        Each callback logs the hook name and the dot-access context snapshot.
      TEXT
    end

    def run_robot
      section "Robot Run Hooks"
      robot = hooked_robot("hook_demo_robot")

      robot.on(:before_run, namespace: :local_demo) do |ctx|
        ctx.local.note = "local robot hook state"
        ctx.local.demo = "robot_run"
      end

      result = robot.run(
        "show the hook pipeline",
        hooks: {
          namespace: :runtime_demo,
          after_run: proc { |ctx| ctx.local.reply_seen = ctx.response.reply }
        }
      )

      puts "Robot reply: #{result.reply}"
    end

    def run_llm_loop
      section "LLM Request/Response Loop"
      puts <<~TEXT
        Demonstrates before/around/after_llm_generation hooks.
        An around_llm_generation hook implements a response cache: on a cache
        hit the block (the real LLM call) is never invoked. around_run timing
        shows the cost difference between a live call and a cache hit.

        xyzzy is silenced for this section so the cache/timing output is readable.
      TEXT

      llm_call_count = 0
      gen_cache      = {}
      timings        = []

      puts "  provider=#{LLM[:default].provider}  model=#{LLM[:default].model}\n\n"

      robot = RobotLab.build(
        name: "loop_demo_robot",
        system_prompt: "You are a helpful assistant. Answer every question in one concise sentence."
      ).with_model(LLM[:default].model)

      robot.on(:around_run, namespace: :perf) do |ctx, &block|
        t0     = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = block.call
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000).round(3)
        timings << elapsed
        puts "  [perf]      #{ctx.request.inspect} — #{elapsed}ms"
        result
      end

      robot.on(:before_llm_generation, namespace: :tracer) do |ctx|
        puts "  [tracer]    llm_generation start  request=#{ctx.request.inspect}"
      end

      robot.on(:around_llm_generation, namespace: :gen_cache) do |ctx, &block|
        if (hit = gen_cache[ctx.request])
          puts "  [gen_cache] HIT  — skipping LLM"
          hit
        else
          puts "  [gen_cache] MISS — calling LLM"
          llm_call_count += 1
          response = block.call
          gen_cache[ctx.request] = response
          response
        end
      end

      robot.on(:after_llm_generation, namespace: :tracer) do |ctx|
        msg = ctx.generation_response
        puts "  [tracer]    llm_generation done   model=#{msg&.model_id}  tokens=#{msg&.output_tokens}"
      end

      queries = [
        "what is the boiling point of water?",
        "what is 6 * 7?",
        "what is the boiling point of water?",
        "what is 6 * 7?",
      ]

      with_xyzzy_silent do
        queries.each_with_index do |query, i|
          puts "\n--- query #{i + 1}: #{query.inspect} ---"
          result = robot.run(query)
          puts "  reply:      #{result.reply}"
        end
      end

      cache_hits = queries.size - llm_call_count
      avg_ms     = (timings.sum / timings.size).round(3)
      puts "\n--- summary ---"
      puts "  robot.run calls : #{queries.size}"
      puts "  LLM calls made  : #{llm_call_count}  (#{cache_hits} served from gen_cache)"
      puts "  avg run time    : #{avg_ms}ms"
    end

    def run_tool
      section "Tool Call Hooks"
      tool = HookDemoTool.new
      result = tool.call({ "label" => "tool hook payload" })

      puts "Tool result: #{result.inspect}"
    end

    def run_network
      section "Network and Task Hooks"
      network = RobotLab::Network.new(name: "hook_demo_network")
      network.on(:before_task, namespace: :network_demo) do |ctx|
        ctx.local.task_note = "network-scoped task hook"
      end
      network.task(:summarize, hooked_robot("network_worker"), depends_on: :none)

      result = network.run(message: "summarize hook activity")

      puts "Network result: #{CompactHookSnapshot.result_summary(result)}"
    end

    def run_error
      section "Error Hook"
      failing_robot = RobotLab.build(name: "failing_hook_robot", system_prompt: "raise")
      failing_robot.instance_variable_get(:@chat).define_singleton_method(:ask) do |_message = nil, **_kwargs|
        raise "planned hook demo failure"
      end

      failing_robot.run("trigger the on_error hook")
    rescue RuntimeError => e
      puts "Caught expected error: #{e.message}"
    end

    def hooked_robot(name)
      RobotLab.build(name: name, system_prompt: "deterministic hook demo").tap do |robot|
        robot.instance_variable_get(:@chat).define_singleton_method(:ask) do |message = nil, **_kwargs, &_block|
          HookDemoResponse.new(content: "deterministic response to #{message.inspect}")
        end
      end
    end

    def stub_robot(name, &response_proc)
      RobotLab.build(name: name, system_prompt: "hook loop demo").tap do |robot|
        robot.instance_variable_get(:@chat).define_singleton_method(:ask) do |message = nil, **_kwargs, &_block|
          response_proc.call(message)
        end
      end
    end

    class NullLogger
      def info(_); end
    end

    def with_xyzzy_silent
      original = RobotLab::Xyzzy.logger
      RobotLab::Xyzzy.logger = NullLogger.new
      yield
    ensure
      RobotLab::Xyzzy.logger = original
    end

    def xyzzy_lib
      File.expand_path("../../robot_lab-xyzzy/lib", __dir__)
    end
end

HookDemo.new.run
