#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 31: Product Launch Assessment — 6 Parallel Analysts, Cap of 4
#
# Six specialist robots evaluate a product launch simultaneously.
# max_concurrent_robots: 4 ensures at most 4 LLM API calls are in-flight
# at once. Robots 5 and 6 queue behind the Async::Semaphore and start as
# soon as any of the first 4 finishes — providing natural back-pressure
# without slowing the pipeline more than necessary.
#
# Architecture:
#
#   ┌──────────────────────────────────────────────────────────────────────┐
#   │          PARALLEL ANALYSIS PHASE  (max_concurrent_robots: 4)        │
#   │                                                                      │
#   │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
#   │  │  Market  │  │  Compet. │  │   Tech   │  │   Risk   │  slots 1-4 │
#   │  │ Analyst  │  │ Analyst  │  │ Reviewer │  │ Assessor │            │
#   │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘            │
#   │       │             │             │             │                    │
#   │    start          start         start         start                 │
#   │                                                                      │
#   │  ┌──────────┐  ┌──────────┐                                         │
#   │  │Financial │  │  Legal   │  queued — start when a slot opens       │
#   │  │ Reviewer │  │ Reviewer │                                         │
#   │  └────┬─────┘  └────┬─────┘                                         │
#   │       │             │                                                │
#   │    (deferred)    (deferred)                                          │
#   │                                                                      │
#   │  ┌─────────────────────────────────────────────────────────────┐    │
#   │  │                  SHARED MEMORY                               │    │
#   │  │  :market  :competitive  :tech  :risk  :financial  :legal     │    │
#   │  └─────────────────────────────────────────────────────────────┘    │
#   │                              │                                       │
#   │                              ▼                                       │
#   │  ┌─────────────────────────────────────────────────────────────┐    │
#   │  │                 Launch Director                               │    │
#   │  │   Blocks on reactive memory until all 6 findings arrive,     │    │
#   │  │   then issues a GO / NO-GO recommendation.                   │    │
#   │  └─────────────────────────────────────────────────────────────┘    │
#   └──────────────────────────────────────────────────────────────────────┘
#
# Key config:
#   RunConfig.new(max_concurrent_robots: 4)
#
# Usage:
#   ruby examples/31_launch_assessment.rb

require_relative "common"

# ── AnalystRobot ────────────────────────────────────────────────────────────────
#
# Runs its LLM call, writes the verdict to shared memory, and logs a timing line
# so you can see when the semaphore releases robots 5 and 6.

class AnalystRobot < RobotLab::Robot
  attr_reader :memory_key
  attr_writer :shared_memory

  def initialize(name:, memory_key:, role:)
    super(
      name:          name,
      **llm_opts,
      system_prompt: "You are a #{role}. " \
                     "Review the product brief in 2-3 crisp sentences from your area of expertise. " \
                     "Close with a one-word verdict: READY or NOT-READY."
    )
    @memory_key = memory_key
  end

  def call(result)
    brief   = extract_brief(result)
    started = Time.now
    puts "  [#{name}] started at +#{"%.1f" % (started - $run_start)}s"

    verdict = run(brief).reply.strip

    elapsed = "%.1f" % (Time.now - started)
    puts "  [#{name}] finished in #{elapsed}s — #{verdict.split.last(2).join(" ")}"

    if @shared_memory
      @shared_memory.current_writer = name
      @shared_memory.set(@memory_key, verdict)
    end

    result.with_context(name.to_sym, verdict).continue(verdict)
  end

  private

  def extract_brief(result)
    case result.value
    when Hash                  then result.value[:message].to_s
    when RobotLab::RobotResult then result.value.reply.to_s
    else                            result.value.to_s
    end
  end
end

# ── LaunchDirector ──────────────────────────────────────────────────────────────
#
# Waits for all 6 findings via reactive memory, then issues the final call.
# SimpleFlow guarantees the six analyst tasks are done before this task runs,
# so the memory.get is effectively a non-blocking read by the time we arrive here.

class LaunchDirector < RobotLab::Robot
  attr_writer :shared_memory

  FINDING_KEYS = %i[market competitive tech risk financial legal].freeze

  def call(result)
    puts "  [#{name}] reading all findings from shared memory..."
    findings = collect_findings

    prompt = <<~PROMPT
      Six specialist analysts have reviewed our product launch readiness.
      Based on their findings, issue a final GO or NO-GO recommendation
      in 3-5 sentences. Be direct and specific about the key deciding factors.

      Market analysis:      #{findings[:market]      || "(not received)"}
      Competitive analysis: #{findings[:competitive] || "(not received)"}
      Technical review:     #{findings[:tech]        || "(not received)"}
      Risk assessment:      #{findings[:risk]        || "(not received)"}
      Financial review:     #{findings[:financial]   || "(not received)"}
      Legal review:         #{findings[:legal]       || "(not received)"}

      Begin your response with "GO -" or "NO-GO -".
    PROMPT

    recommendation = run(prompt).reply.strip
    @shared_memory.set(:recommendation, recommendation)
    puts "  [#{name}] recommendation ready"

    result.with_context(:recommendation, recommendation).continue(recommendation)
  end

  private

  # Memory#get(wait:) RAISES RobotLab::AwaitTimeout on expiry — it never
  # returns a :timeout sentinel. Rescue it and re-read without wait:, which
  # never blocks and omits keys that were never written, so a stalled analyst
  # degrades the recommendation instead of killing the director.
  def collect_findings
    @shared_memory.get(*FINDING_KEYS, wait: 120)
  rescue RobotLab::AwaitTimeout => e
    puts "  [#{name}] WARNING: #{e.message}"
    partial = @shared_memory.get(*FINDING_KEYS)
    missing = FINDING_KEYS - partial.keys
    puts "  [#{name}] Proceeding without: #{missing.join(', ')}" if missing.any?
    partial
  end
end

# ── Product Brief ───────────────────────────────────────────────────────────────

PRODUCT_BRIEF = <<~BRIEF
  Product: "Orion" — an AI-powered project management tool that auto-generates
  sprint plans from Jira backlogs, detects scope creep in real-time, and integrates
  with GitHub and Slack via webhooks. SaaS pricing: $25/seat/month, 14-day free trial.
  Target: mid-size engineering teams (20-200 developers). Launch date: 6 weeks out.
  Beta: 12 paying customers, 94% satisfaction, 0 critical bugs open. SOC 2 Type I
  certification in progress, expected within 30 days.
BRIEF

# ── Build the six analysts ───────────────────────────────────────────────────────

ANALYSTS = [
  { name: "market_analyst",      key: :market,      role: "market opportunity analyst"             },
  { name: "competitive_analyst", key: :competitive, role: "competitive intelligence analyst"       },
  { name: "tech_reviewer",       key: :tech,        role: "technical readiness and quality reviewer" },
  { name: "risk_assessor",       key: :risk,        role: "product risk assessment specialist"    },
  { name: "financial_reviewer",  key: :financial,   role: "financial viability and pricing analyst" },
  { name: "legal_reviewer",      key: :legal,       role: "legal, compliance, and IP reviewer"    },
].freeze

analyst_robots = ANALYSTS.map do |spec|
  AnalystRobot.new(name: spec[:name], memory_key: spec[:key], role: spec[:role])
end

director = LaunchDirector.new(
  name:          "launch_director",
  **llm_opts,
  system_prompt: "You are the VP of Product making the final launch call."
)

# ── Network — note the concurrency cap ──────────────────────────────────────────

config = RobotLab::RunConfig.new(max_concurrent_robots: 4)

analyst_names = analyst_robots.map { |r| r.name.to_sym }

network = RobotLab.create_network(name: "launch_assessment", config: config) do
  analyst_robots.each do |robot|
    task robot.name.to_sym, robot, depends_on: :none
  end

  task :launch_director, director, depends_on: analyst_names
end

# Assign shared memory so each robot can write to it directly
shared_memory = network.memory
(analyst_robots + [director]).each { |r| r.shared_memory = shared_memory }

# Subscribe for a memory-level audit trail
analyst_robots.each do |robot|
  network.memory.subscribe(robot.memory_key) do |change|
    puts "  [memory] :#{change.key} written by #{change.writer}"
  end
end

# ── Run ─────────────────────────────────────────────────────────────────────────

banner "Product Launch Assessment"
puts "  6 specialist analysts in parallel, max_concurrent_robots: 4"
puts
puts "Pipeline:"
puts network.visualize
puts
puts "Concurrency config: #{config.inspect}"
puts
puts "Product brief:"
puts PRODUCT_BRIEF.strip.gsub(/^/, "  ")
puts
section "Running — Analysts 5 and 6 Queue Until a Semaphore Slot Opens"

$run_start = Time.now
result     = network.run(message: PRODUCT_BRIEF)
elapsed    = "%.1f" % (Time.now - $run_start)

puts
hr
puts "All analysts complete. Total wall time: #{elapsed}s"
hr

section "Launch Director Recommendation"
puts network.memory[:recommendation]
puts
section "Individual Analyst Verdicts"
analyst_robots.each do |robot|
  label  = robot.name.gsub("_", " ").upcase
  finding = network.memory.get(robot.memory_key).to_s
  puts "#{label}"
  puts finding
  puts
end
