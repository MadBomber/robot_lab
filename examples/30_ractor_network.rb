#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 30: Ractor Network Scheduler
#
# Demonstrates Track 2 of RobotLab's Ractor parallelism: running a
# multi-robot pipeline under RactorNetworkScheduler, which dispatches
# independent tasks in parallel waves and respects depends_on ordering.
#
# Concepts covered:
#   - Network.new(parallel_mode: :ractor) — opt the network into Ractor dispatch
#   - Dependency waves                    — independent tasks run concurrently,
#                                           dependent tasks wait for their wave
#   - RobotSpec                           — frozen, Ractor-shareable robot descriptor
#   - RactorNetworkScheduler              — direct use for testing / custom wiring
#   - Result Hash                         — run_pipeline returns { name => result }
#
# Part 1 — simulated scheduler, no LLM traffic.
#   Overrides execute_spec with a sleep-based stub so the wave ordering and
#   timing characteristics are visible without real LLM calls.
#
# Part 2 — Network.new(parallel_mode: :ractor) API walkthrough.
#   Shows how to configure the network and inspects the dependency graph.
#   No run() call is made, so no LLM traffic either.
#
# Part 3 — live LLM run (opt-in via RUN_LIVE).
#   Expected to fail against ruby_llm today; the rescue clauses explain why.
#
# Usage:
#   bundle exec ruby examples/30_ractor_network.rb            # Parts 1 & 2
#   RUN_LIVE=1 bundle exec ruby examples/30_ractor_network.rb # Parts 1, 2 & 3

require_relative "common"
require "robot_lab/ractor"

banner "Ractor Network Scheduler"

DIVIDER = ("─" * 54).freeze

# =============================================================================
# Part 1: Simulated scheduler — dependency waves and timing
# =============================================================================
#
# Pipeline topology:
#
#   headline_finder  ─────────────────────────────────┐
#                                                      ├──► report_writer
#   background_brief ─────────────────────────────────┤
#                                                      │
#   fact_checker     ─────────────────────────────────┘
#
# Wave 1 — headline_finder, background_brief, fact_checker: parallel (none depend on each other)
# Wave 2 — report_writer: sequential (depends on all three)
#
# Simulated latencies (seconds):
LATENCIES = {
  "headline_finder"   => 0.60,
  "background_brief"  => 0.50,
  "fact_checker"      => 0.40,
  "report_writer"     => 0.70
}.freeze
#
# Expected times:
#   Parallel   — wave1 = max(0.60, 0.50, 0.40) = 0.60s
#                wave2 = 0.70s
#                total ≈ 1.30s
#
#   Sequential — 0.60 + 0.50 + 0.40 + 0.70 = 2.20s
#
#   Speedup    ≈ 1.7×

section "Part 1: Simulated Parallel Run (no LLM traffic)"

# SimulatedScheduler overrides execute_spec so that instead of
# constructing a real Robot and calling the LLM, it just sleeps for
# the robot's configured latency and returns a synthetic result string.
# All dependency-ordering and wave-dispatch logic is inherited unchanged.
class SimulatedScheduler < RobotLab::RactorNetworkScheduler
  private

  def execute_spec(spec, _message)
    delay = LATENCIES[spec.name] || 0.30
    sleep delay
    "#{spec.name}: completed after #{delay}s".freeze
  end
end

# Build RobotSpec objects directly.
# (Normally Network#run_with_ractor_scheduler builds these from Task wrappers.)
def make_spec(name, deps = :none)
  spec = RobotLab::RobotSpec.new(
    name:          name.freeze,
    template:      nil,
    system_prompt: "You are the #{name} robot.".freeze,
    config_hash:   {}.freeze
  )
  { spec: spec, depends_on: deps }
end

specs_with_deps = [
  make_spec("headline_finder"),
  make_spec("background_brief"),
  make_spec("fact_checker"),
  make_spec("report_writer", ["headline_finder", "background_brief", "fact_checker"])
]

memory    = RobotLab::Memory.new
scheduler = SimulatedScheduler.new(memory: memory)

topic = "artificial intelligence regulation in 2025"

t0      = Process.clock_gettime(Process::CLOCK_MONOTONIC)
results = scheduler.run_pipeline(specs_with_deps, message: topic)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

scheduler.shutdown

sequential_total = LATENCIES.values.sum

puts "  Pipeline topology:"
puts "    Wave 1 (parallel): headline_finder · background_brief · fact_checker"
puts "    Wave 2 (sequential): report_writer  ← waits for all three"
puts

puts "  Results (Hash { name => result_string }):"
results.each { |name, val| puts "    \"#{name}\" => #{val.inspect}" }
puts

puts "  Wall time:         #{"%.3f" % elapsed}s"
puts "  Sequential equiv:  #{"%.3f" % sequential_total}s  (#{LATENCIES.map { |n, d| "#{n}=#{d}" }.join(' + ')})"
puts "  Speedup:           #{(sequential_total / elapsed).round(1)}×"
puts

# =============================================================================
# Part 2: Network.new(parallel_mode: :ractor) API
# =============================================================================

section "Part 2: Network.new(parallel_mode: :ractor)"

# When parallel_mode: :ractor is set on a Network, network.run(message:)
# routes through RactorNetworkScheduler instead of SimpleFlow::Pipeline.
# The default mode is :async (unchanged SimpleFlow behavior).

network = RobotLab::Network.new(name: "research_pipeline", parallel_mode: :ractor) do
  task :headline_finder,  RobotLab.build(name: "headline_finder",
                                          system_prompt: "Find the 3 most relevant news headlines. Be concise.",
                                          **llm_opts),
       depends_on: :none

  task :background_brief, RobotLab.build(name: "background_brief",
                                          system_prompt: "Provide a 2-sentence background on the topic.",
                                          **llm_opts),
       depends_on: :none

  task :fact_checker,     RobotLab.build(name: "fact_checker",
                                          system_prompt: "List 3 verifiable facts about the topic.",
                                          **llm_opts),
       depends_on: :none

  task :report_writer,    RobotLab.build(name: "report_writer",
                                          system_prompt: "Synthesize the provided context into a 3-sentence report.",
                                          **llm_opts),
       depends_on: ["headline_finder", "background_brief", "fact_checker"]
end

puts "  network.name          => #{network.name.inspect}"
puts "  network.parallel_mode => #{network.parallel_mode.inspect}"
puts
puts "  Dependency graph (from network.pipeline.step_dependencies):"

network.pipeline.step_dependencies.each do |step, deps|
  dep_str = deps.empty? ? "(entry point — Wave 1)" : "depends on: #{deps.join(', ')}"
  puts "    :#{step.to_s.ljust(18)}  #{dep_str}"
end
puts
puts "  When network.run(message: ...) is called:"
puts "    • RactorNetworkScheduler is created with the network's memory"
puts "    • Each task is converted to a frozen RobotSpec"
puts "    • Wave 1 tasks are dispatched concurrently (Thread per task)"
puts "    • Each Thread submits a RactorJob to the worker queue"
puts "    • A Ractor worker pops the job, constructs a fresh Robot from the"
puts "      spec, calls robot.run(message), and returns the frozen result"
puts "    • Wave 2 begins once all Wave 1 results are available"
puts "    • Return value is a Hash { robot_name => result_string }"
puts

# =============================================================================
# Part 3: Live LLM run (opt-in via RUN_LIVE=1)
# =============================================================================

unless ENV["RUN_LIVE"]
  section "Part 3: Live LLM Run"
  puts "   Set RUN_LIVE=1 (with Ollama running) to attempt the real pipeline."
  puts "   Expected behavior: headline_finder, background_brief, and"
  puts "   fact_checker run in parallel; report_writer follows."
  puts
  puts "   Heads-up: this is expected to fail today — see the rescue clauses"
  puts "   below. ruby_llm keeps Procs in class-level state, which cannot"
  puts "   cross a Ractor boundary. Part 1 shows the wave ordering that Part 3"
  puts "   will exercise once ruby_llm is Ractor-safe."
  puts
  hr
  puts "Example 30 complete."
  exit 0
end

require_ollama!

section "Part 3: Live LLM Run (RUN_LIVE set)"

puts "  Running 4-robot research pipeline on:"
puts "  \"#{topic}\""
puts
puts "  Wave 1 (parallel): headline_finder · background_brief · fact_checker"
puts "  Wave 2:            report_writer"
puts

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

begin
  result = network.run(message: topic)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

  puts "  Completed in #{"%.2f" % elapsed}s"
  puts
  puts "  Results:"
  result.each do |name, text|
    snippet = text.to_s.strip.lines.first.to_s.strip
    puts "    [#{name}]  #{snippet[0..90]}#{snippet.length > 90 ? '…' : ''}"
  end

rescue Ractor::IsolationError, Ractor::Error => e
  puts "  Ractor error: #{e.class}: #{e.message[0..100]}"
  puts
  puts "  ruby_llm is not yet Ractor-safe: it uses Procs in class"
  puts "  definitions that cannot cross Ractor boundaries."
  puts "  Track this at: https://github.com/crmne/ruby_llm"

rescue RobotLab::Error => e
  if e.message.include?("un-shareable Proc")
    puts "  Live LLM runs require ruby_llm to be Ractor-safe."
    puts "  ruby_llm stores Procs in class-level hooks that cannot cross"
    puts "  Ractor boundaries. Part 1 (SimulatedScheduler) demonstrates wave"
    puts "  ordering today; Part 3 will work once ruby_llm gains Ractor support."
  else
    puts "  RobotLab::Error: #{e.message}"
  end
end

puts
hr
puts "Example 30 complete."
