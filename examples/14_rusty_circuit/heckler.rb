# frozen_string_literal: true

# ── The Heckler ──────────────────────────────────────────────
#
# No tools. Just reacts honestly. Drives the comedian to adapt
# by being a tough but fair audience. Stops responding after
# MAX_ROUNDS — the loop terminates naturally.
#
# The heckler doesn't have to respond every round. They can
# stay silent (the LLM replies with [SILENCE]) or tell their
# own jokes using the comedian as the punch line.
#
# Subscribes to the :room channel to hear performances.
# Sends feedback directly to the comic's personal channel.
#
class Heckler < RobotLab::Robot
  attr_reader :rounds, :won_over

  def initialize(bus:, display:)
    @rounds   = 0
    @won_over = false
    @display  = display

    super(name: "heckler", template: :open_mic_heckler, bus: bus)

    # Listen to the room for the comic's performances
    @bus.subscribe(:room) do |delivery|
      delivery.ack!
      message = delivery.message
      next unless message.from == "comic"
      next if @rounds >= MAX_ROUNDS

      @rounds += 1

      verdict = run(
        "The comedian just said: \"#{message.content}\"\n\n" \
        "React however feels right — heckle, counter-joke, " \
        "show respect, or stay silent."
      ).reply.strip

      # The heckler chose silence — no output, no feedback
      if verdict.match?(/\[SILENCE\]/i)
        next
      end

      @display.heckler("Heckler [Round #{@rounds}]", verdict)

      if verdict.match?(/laugh|love|hilarious|brilliant|great/i)
        @won_over = true
        @display.heckler_note("(won over!)")
      end

      # Send feedback to comic's personal channel until the set is done
      send_reply(to: message.from.to_sym, content: verdict, in_reply_to: message.key) if @rounds < MAX_ROUNDS
    end
  end
end
