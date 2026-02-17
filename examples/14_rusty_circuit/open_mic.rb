#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 14: Open Mic Night — Architecture Dominates Material
#
# A comedy club where robots demonstrate Werner's prompt object patterns:
#
#   - Compounding recovery: the comedian improves through multi-turn
#     feedback with a heckler, each round an opportunity to get better
#   - Self-modification via tool side effects: the comedian rewrites
#     their own system prompt and adjusts their temperature mid-show
#   - Dynamic spawning: the comedian summons a comedy coach when
#     struggling; the talent scout recruits specialist analysts
#   - Cross-robot influence: the heckler's feedback drives adaptation;
#     the coach's advice reshapes the comedian's approach
#   - Emergent coordination: no hardcoded orchestration — the
#     conversation drives the flow
#
# The tools don't just return data. They modify the robots that call
# them. The LLM decides when to self-modify, when to spawn help, and
# when to change approach. Recovery is emergent, not engineered.
#
# Communication uses a shared :room channel — the comic publishes
# performances there, and both the heckler and scout subscribe.
# The heckler sends feedback directly to the comic's personal channel.
# Room deliveries are routed through the core processing guard
# (BusMessaging#handle_incoming_delivery), which serializes all
# run() calls to prevent Async fiber interleaving from corrupting
# chat history.
#
# Style reinventions are injected into the next round's user prompt
# rather than modifying the chat's system messages, avoiding message
# ordering issues while achieving genuine self-modification.
#
# Usage:
#   bundle exec ruby examples/14_rusty_circuit/open_mic.rb
#   bundle exec ruby examples/14_rusty_circuit/open_mic.rb --log show.log

ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "prompts")

require_relative "../../lib/robot_lab"
require_relative "display"

RubyLLM.configure { |c| c.logger = Logger.new(File::NULL) }

MAX_ROUNDS = 5

require_relative "comic"
require_relative "heckler"
require_relative "scout"

# ── The Show ─────────────────────────────────────────────────

log_path = nil
if (idx = ARGV.index("--log"))
  log_path = ARGV[idx + 1]
  abort "Usage: #{$0} [--log FILE]" unless log_path
end

bus     = TypedBus::MessageBus.new
display = Display.new(
  scout_path: File.join(__dir__, "scout_notes.md"),
  log_path: log_path
)

# Shared room channel — the comic publishes performances here,
# and both the heckler and scout subscribe independently.
bus.add_channel(:room, type: RobotLab::RobotMessage)

comic   = Comic.new(bus: bus, display: display)
heckler = Heckler.new(bus: bus, display: display)
scout   = Scout.new(bus: bus, display: display)

display.banner(<<~BANNER)
  ============================================================
    THE RUSTY CIRCUIT — Tuesday Open Mic
    Architecture Dominates Material
  ============================================================

    Cast:
      Comic   — observational humor, armed with self-modification tools
      Heckler — three-year regular, high standards, zero patience
      Scout   — talent network, sitting in the back with a notebook
BANNER

display.separator

# The opening bit — comic performs, then enters the feedback loop
opening = comic.run(
  "You just stepped on stage at The Rusty Circuit open mic. " \
  "The crowd looks tough. Do your opening bit."
).reply.strip

display.comic("Comic [Opening]", opening)

# Publish to room — both heckler and scout pick it up.
# The heckler reacts and sends feedback to the comic's personal
# channel, triggering the feedback loop:
#   room → heckler → comic → room → heckler → comic → ...
# The loop terminates when the heckler stops replying (MAX_ROUNDS).
# The scout observes each round via :room, serialized by the core guard.
comic.send_message(to: :room, content: "OPENING: #{opening}")

display.separator

# Final verdict from the talent scout
verdict = scout.run(scout.verdict_prompt).reply.strip

display.verdict("Scout [FINAL VERDICT]", verdict)

display.stats(<<~STATS)
  ────────────────────────────────────────────────────────────
    Show Stats:
      Rounds performed:   #{comic.round + 1} (opening + #{comic.round} rounds)
      Style reinventions: #{comic.style_changes}
      Coaches spawned:    #{comic.coaches_spawned}
      Analysts recruited: #{scout.analysts_spawned}
      Heckler won over:   #{heckler.won_over}
      Total robots on bus: #{[comic, heckler, scout].size + comic.coaches_spawned + scout.analysts_spawned}

STATS

display.close
