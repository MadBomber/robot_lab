#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 27: Production Incident War Room
#
# A payment-service outage is in progress. Three SRE scouts investigate
# different layers in parallel — database, network, and application. Each
# scout writes findings to shared reactive memory and broadcasts a status
# update to the war-room coordinator via TypedBus.
#
# Phase 5 infrastructure features demonstrated:
#
#   REACTIVE MEMORY  (IO.pipe Waiter — #13)
#   ──────────────────────────────────────────────────────────────
#   db_scout   ─┐  memory[:db_finding] = "..."  ─┐
#   net_scout  ─┼  memory[:net_finding] = "..." ─┼→ IO.pipe signal
#   app_scout  ─┘  memory[:app_finding] = "..." ─┘
#                                                  ↓
#                     commander.get(:db_finding, :net_finding, :app_finding, wait: 60)
#                     wakes via IO.select on the pipe — no busy-wait, Async-safe
#
#   BUS POLLER  (serialized delivery — #14)
#   ──────────────────────────────────────────────────────────────
#   db_scout, net_scout, app_scout each send a bus message to :war_room.
#   If two scouts finish simultaneously, their deliveries queue in BusPoller
#   so war_room processes them one at a time — no re-entrancy, no dropped
#   messages, arrival order preserved.
#
#   POLLER GROUPS  (#15)
#   ──────────────────────────────────────────────────────────────
#   task :db_scout,  poller_group: :investigation   (fast, no LLM in final stage)
#   task :net_scout, poller_group: :investigation
#   task :app_scout, poller_group: :investigation
#   task :commander, poller_group: :command         (expensive synthesis call)
#
# Usage:
#   bundle exec ruby examples/27_incident_response/incident_response.rb

ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "../prompts")

require_relative "../common"
require "fileutils"

OUTPUT_DIR = File.join(__dir__, "output")
FileUtils.mkdir_p(OUTPUT_DIR)

# ── Scout ──────────────────────────────────────────────────────────────────
#
# Investigates one subsystem, stores a terse finding in shared memory,
# and broadcasts a status line to the war-room via bus.
#
# NOTE: we bypass extract_run_context's delete() pattern and hold a direct
# reference to shared memory — the same technique used in example 15 —
# because parallel pipeline steps would otherwise lose the memory reference
# after the first step runs.

class SREScout < RobotLab::Robot
  attr_writer :shared_memory

  def initialize(name:, subsystem:, memory_key:, bus: nil)
    super(
      name: name,
      **llm_opts,
      system_prompt: "You are a senior SRE responding to a production outage. " \
                     "Diagnose one infrastructure layer in 2 sentences: " \
                     "first sentence is root cause, second is customer impact.",
      bus: bus
    )
    @subsystem  = subsystem
    @memory_key = memory_key
  end

  def call(result)
    incident = extract_message(result)

    finding = run("Investigate the #{@subsystem} layer. #{incident}").reply.strip

    # Write to reactive memory — wakes the IO.pipe waiter in the commander
    if @shared_memory
      @shared_memory.current_writer = name
      @shared_memory.set(@memory_key, finding)
    end

    puts "  [#{name}] #{finding[0..100]}#{"..." if finding.length > 100}"

    # Notify war room — BusPoller queues this if war_room is already processing
    send_message(to: :war_room, content: "[#{@subsystem}] #{finding}") if bus

    result.with_context(name.to_sym, finding).continue(finding)
  end

  private

  def extract_message(result)
    case result.value
    when Hash               then result.value[:message].to_s
    when RobotLab::RobotResult then result.value.reply.to_s
    else result.value.to_s
    end
  end
end

# ── War Room ───────────────────────────────────────────────────────────────
#
# Receives scout status updates via TypedBus.
# BusPoller serializes delivery: even if all three scouts finish at the
# same instant their messages are processed one at a time and none is
# dropped.  Delivery order is preserved by the queue.

class WarRoom < RobotLab::Robot
  attr_reader :updates

  def initialize(bus:)
    super(name: "war_room", **llm_opts, system_prompt: "SRE war-room coordinator.", bus: bus)
    @updates = []

    on_message do |msg|
      # BusPoller ensures this block is never re-entered for the same robot.
      # Simulate brief processing work so a second delivery would have to queue.
      @updates << msg.content
      puts "  [war_room] Update ##{@updates.size} processed: #{msg.content[0..70]}..."
    end
  end
end

# ── Incident Commander ─────────────────────────────────────────────────────
#
# Waits until all three scout findings land in shared memory, then calls
# the LLM once to synthesize an action plan.
#
# memory.get(:db_finding, :net_finding, :app_finding, wait: 60)
#   → internally each key uses an IO.pipe-backed Waiter
#   → IO.select wakes the call as soon as all three keys are written
#   → no busy-wait, no mutex spin, works cleanly with Async

class IncidentCommander < RobotLab::Robot
  attr_writer :shared_memory

  FINDING_KEYS = %i[db_finding net_finding app_finding].freeze

  def call(result)
    puts "  [commander] Blocking on reactive memory — waiting for all scout findings..."

    findings = collect_findings

    prompt = <<~PROMPT
      Three SRE scouts have reported their findings for a payment-service outage.
      Issue a concise incident action plan (3–5 bullet points) covering immediate
      mitigation, next investigation steps, and stakeholder communication.

      Database layer: #{findings[:db_finding] || "no data"}
      Network layer:  #{findings[:net_finding] || "no data"}
      Application:    #{findings[:app_finding] || "no data"}
    PROMPT

    report = run(prompt).reply.strip

    @shared_memory[:incident_report] = report

    path = File.join(OUTPUT_DIR, "incident_report.md")
    File.write(path, "# Incident Action Plan\n\n#{report}\n")
    puts "  [commander] Action plan written to #{path}"

    result.with_context(:commander, report).continue(report)
  end

  private

  # Blocking multi-key read with a real degradation path.
  #
  # Memory#get(wait:) signals a timeout by RAISING RobotLab::AwaitTimeout — it
  # never returns a :timeout sentinel value. Rescue it and re-read without
  # wait:, which never blocks and simply omits keys that were never written,
  # so a slow scout degrades the report instead of killing the commander.
  def collect_findings
    @shared_memory.get(*FINDING_KEYS, wait: 60)
  rescue RobotLab::AwaitTimeout => e
    puts "  [commander] WARNING: #{e.message}"
    partial = @shared_memory.get(*FINDING_KEYS)
    missing = FINDING_KEYS - partial.keys
    puts "  [commander] Proceeding without: #{missing.join(', ')}" if missing.any?
    partial
  end
end

# ── Wire up ────────────────────────────────────────────────────────────────

bus = TypedBus::MessageBus.new

db_scout  = SREScout.new(name: "db_scout",  subsystem: "database",    memory_key: :db_finding,  bus: bus)
net_scout = SREScout.new(name: "net_scout", subsystem: "network",     memory_key: :net_finding, bus: bus)
app_scout = SREScout.new(name: "app_scout", subsystem: "application", memory_key: :app_finding, bus: bus)
war_room  = WarRoom.new(bus: bus)
commander = IncidentCommander.new(name: "commander", **llm_opts, system_prompt: "SRE incident commander.")

# Build the investigation network
# poller_group: labels are registered on the network's shared BusPoller.
network = RobotLab.create_network(name: "incident_response") do
  task :db_scout,  db_scout,  depends_on: :none, poller_group: :investigation
  task :net_scout, net_scout, depends_on: :none, poller_group: :investigation
  task :app_scout, app_scout, depends_on: :none, poller_group: :investigation
  task :commander, commander, depends_on: [:db_scout, :net_scout, :app_scout], poller_group: :command
end

# Assign direct shared-memory references (avoids the extract_run_context
# mutation problem with parallel pipeline steps — see example 15).
shared_memory = network.memory
[db_scout, net_scout, app_scout, commander].each do |r|
  r.shared_memory = shared_memory
end

# Subscribe to memory changes — fires as each scout writes its finding.
# The callback runs asynchronously; the IO.pipe waiter in commander wakes
# independently when the key is set.
network.memory.subscribe(:db_finding, :net_finding, :app_finding) do |change|
  puts "  [memory] :#{change.key} written by #{change.writer}"
end

# ── Run ────────────────────────────────────────────────────────────────────

puts "=" * 65
puts "Example 27: Production Incident War Room"
puts "  Phase 5 — BusPoller · Reactive Memory · Poller Groups"
puts "=" * 65
puts
puts network.visualize
puts

puts "Poller groups declared on the network's tasks:"
puts "  :investigation — db_scout, net_scout, app_scout"
puts "  :command       — commander"
puts "(Network#task registers each group on the shared BusPoller; the poller"
puts " itself is internal, so the groups are documented here rather than"
puts " introspected.)"
puts

puts "INCIDENT: Payment service degraded — elevated error rates and timeouts"
puts "-" * 65
puts

result = network.run(message: "Payment service is degraded: elevated HTTP 500 " \
                               "error rates (~12%) and p99 latency spiked to 8s. " \
                               "Investigate your assigned infrastructure layer.")

puts
puts "-" * 65
puts "War-room updates received (BusPoller order):"
war_room.updates.each.with_index(1) { |u, i| puts "  #{i}. #{u.gsub(/\s+/, " ")[0..90]}" }
puts
puts "Reactive memory keys written by scouts:"
%i[db_finding net_finding app_finding].each do |key|
  val = network.memory[key]
  puts "  :#{key.to_s.ljust(14)} #{val&.gsub(/\s+/, " ")&.slice(0, 80)}..."
end
puts
puts "Incident action plan (from #{OUTPUT_DIR}/incident_report.md):"
puts "-" * 65
report = network.memory[:incident_report].to_s
puts report
puts
puts "=" * 65
