#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 17: Composable Skills
#
# Demonstrates using skills to compose robot behaviors from reusable templates.
# Skills are regular templates whose prompt bodies are prepended before the main
# template. They support nesting (a skill can reference other skills) with
# automatic cycle detection.
#
# Scenario: An SRE incident response system where the on-call analyst robot
# is composed from reusable behavioral skills.
#
# Skill architecture:
#
#   incident_responder (main template)
#   ├── runbook_protocol        (flat skill — structured diagnosis steps)
#   ├── structured_output       (flat skill — JSON response format)
#   └── sre_compliance          (recursive skill — bundles two sub-skills)
#       ├── pii_redactor        (leaf skill — redact PII from output)
#       └── audit_trail         (leaf skill — include audit metadata)
#
# Prompt assembly order (depth-first):
#   1. runbook_protocol     — "follow these 5 steps..."
#   2. structured_output    — "respond with JSON..."
#   3. pii_redactor         — "redact PII..." (nested via sre_compliance)
#   4. audit_trail          — "include audit fields..." (nested via sre_compliance)
#   5. sre_compliance       — "operate under SRE compliance..."
#   6. incident_responder   — "you are the on-call analyst for..."
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/17_skills.rb
#
# Templates:
#   examples/prompts/
#   ├── incident_responder.md   — Main template (team name, services, runbook URL)
#   ├── runbook_protocol.md     — Flat skill: 5-step incident protocol
#   ├── structured_output.md    — Flat skill: JSON response format
#   ├── sre_compliance.md       — Recursive skill: bundles pii_redactor + audit_trail
#   ├── pii_redactor.md         — Leaf skill: redact PII
#   └── audit_trail.md          — Leaf skill: audit metadata in every response

# Configure template path before loading (MywayConfig reads env vars on init)
ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

# Send logger output to a file instead of stdout
require 'logger'
log_file = File.join(__dir__, "17.log")
RobotLab.config.logger = Logger.new(log_file)
RubyLLM.configure { |c| c.logger = Logger.new(log_file) }

# =============================================================================
# Simulated Alert Data
# =============================================================================

ALERTS = [
  {
    label: "Database Connection Pool Exhaustion",
    data: <<~ALERT
      ALERT: PostgreSQL connection pool exhausted
      Service: payments-api
      Severity: SEV-2
      Time: 2025-02-22T03:14:00Z
      Region: us-east-1

      Metrics:
      - Active connections: 100/100 (pool max)
      - Connection wait time: 12.4s (p99), normally 0.02s
      - Failed queries: 847 in last 5 minutes
      - Error rate: 23% (baseline: 0.1%)

      Recent changes:
      - Deploy payments-api v2.41.0 at 02:50 UTC (added batch reconciliation job)
      - No infrastructure changes in 24h

      Affected users: ~3,200 checkout attempts failing
      Downstream: order-service seeing 504 timeouts from payments-api

      Sample error log:
      [2025-02-22T03:12:44Z] ERROR payments-api: PG::ConnectionBad: could not obtain connection
        from pool within 10s — user=svc_payments@10.0.3.47 db=payments_prod
      [2025-02-22T03:13:01Z] ERROR payments-api: ActiveRecord::ConnectionTimeoutError
        request_id=req_8f3a2b user=jane.doe@acme.com account_id=acct_99321
    ALERT
  },
  {
    label: "Memory Leak in User Service",
    data: <<~ALERT
      ALERT: Container OOMKilled — repeated restarts
      Service: user-service
      Severity: SEV-3
      Time: 2025-02-22T09:30:00Z
      Region: eu-west-1

      Metrics:
      - Container restarts: 14 in last hour (normally 0)
      - Memory usage: ramps from 256MB to 2GB limit in ~4 minutes
      - Request latency: p99 spikes to 8s before each OOMKill
      - Heap profile: String allocations growing linearly

      Recent changes:
      - Deploy user-service v1.18.3 at 08:00 UTC (added avatar upload endpoint)
      - Kubernetes node pool scaled from 3 to 5 nodes at 07:00 UTC

      Affected users: intermittent 503 errors on profile pages (~500 users/hr)
      Downstream: session-service cache miss rate elevated (users re-authenticating)

      Sample error log:
      [2025-02-22T09:28:11Z] WARN user-service: Memory usage 1.8GB approaching 2GB limit
        pod=user-service-7f8b9c-x4k2j node=ip-10-0-5-112.ec2.internal
      [2025-02-22T09:29:03Z] ERROR user-service: OOMKilled — container exceeded memory limit
        user_email=bob.smith@example.org ip=192.168.1.42 endpoint=/api/v2/avatar/upload
    ALERT
  }
]

# =============================================================================
# Build the Incident Responder with Composable Skills
# =============================================================================

puts "=" * 70
puts "RobotLab Skills Demo — SRE Incident Response System"
puts "=" * 70
puts

# Show the skill composition
puts "Skill composition:"
puts "  incident_responder (main template)"
puts "  ├── runbook_protocol        (flat skill)"
puts "  ├── structured_output       (flat skill)"
puts "  └── sre_compliance          (recursive skill)"
puts "      ├── pii_redactor        (leaf)"
puts "      └── audit_trail         (leaf)"
puts

# Build the robot with skills
#
# - runbook_protocol:  Flat skill — adds the 5-step incident diagnosis protocol
# - structured_output: Flat skill — forces JSON output, sets temperature to 0.2
# - sre_compliance:    Recursive skill — auto-expands to include pii_redactor
#                      and audit_trail before its own compliance instructions
responder = RobotLab.build(
  name: "incident_responder",
  template: :incident_responder,
  skills: [:runbook_protocol, :structured_output, :sre_compliance],
  context: {
    team_name: "Platform Engineering",
    services: ["payments-api", "user-service", "order-service", "session-service"],
    on_call_runbook_url: "https://wiki.internal/runbooks/platform-eng"
  }
)

# Show what the robot got
puts "Robot: #{responder.name}"
puts "Skills: #{responder.skills.inspect}"
puts "Expanded skills: #{responder.instance_variable_get(:@expanded_skills).inspect}"
puts "Model: #{responder.model}"
puts

# Display the assembled system prompt
chat = responder.instance_variable_get(:@chat)
messages = chat.instance_variable_get(:@messages)
system_msg = messages.find { |m| m.role.to_s == "system" }
if system_msg
  prompt = system_msg.content
  puts "-" * 70
  puts "Assembled system prompt (#{prompt.length} chars, #{prompt.lines.count} lines):"
  puts "-" * 70
  prompt.lines.each_with_index do |line, i|
    puts "  %3d  %s" % [i + 1, line]
  end
  puts "-" * 70
end

# =============================================================================
# Also build a plain responder WITHOUT skills for comparison
# =============================================================================

plain_responder = RobotLab.build(
  name: "plain_responder",
  template: :incident_responder,
  context: {
    team_name: "Platform Engineering",
    services: ["payments-api", "user-service", "order-service", "session-service"],
    on_call_runbook_url: "https://wiki.internal/runbooks/platform-eng"
  }
)

plain_chat = plain_responder.instance_variable_get(:@chat)
plain_messages = plain_chat.instance_variable_get(:@messages)
plain_msg = plain_messages.find { |m| m.role.to_s == "system" }
if plain_msg
  puts
  puts "For comparison — plain responder (no skills): #{plain_msg.content.length} chars"
  puts
end

# =============================================================================
# Run Against Simulated Incidents
# =============================================================================

ALERTS.each_with_index do |alert, index|
  puts
  puts "=" * 70
  puts "Incident #{index + 1}: #{alert[:label]}"
  puts "=" * 70
  puts

  result = responder.run(alert[:data])
  content = result.output.first&.content.to_s

  # Display the response
  puts "Response:"
  puts content
  puts
end

puts "=" * 70
puts
puts <<~FOOTER
  This example demonstrates:

  Flat skills (prepended directly):
    - runbook_protocol: Adds a 5-step incident diagnosis protocol
    - structured_output: Forces JSON output and lowers temperature to 0.2

  Recursive skill (auto-expands nested skills):
    - sre_compliance bundles:
      - pii_redactor: Redacts email, IP, username, account ID from output
      - audit_trail: Adds confidence, sources, and assumptions metadata

  Key behaviors:
    - Skills are just templates — no special syntax or directories
    - Depth-first expansion: pii_redactor and audit_trail appear before sre_compliance
    - Config cascade: structured_output sets temperature: 0.2, inherited by the robot
    - Shared context: all skills and the main template render with the same context hash
    - Constructor kwargs always override skill/template config

  Template files: #{File.join(__dir__, 'prompts')}
FOOTER
