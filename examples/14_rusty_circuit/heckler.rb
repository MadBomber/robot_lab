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
# Room deliveries are routed through the core processing guard,
# which serializes run() calls to prevent Async fiber interleaving.
# Sends feedback directly to the comic's personal channel.
#
class Heckler < RobotLab::Robot
  attr_reader :rounds, :won_over

  def initialize(bus:, display:)
    @rounds   = 0
    @won_over = false
    @display  = display

    super(name: "heckler", model: LLM[:default].model, template: :open_mic_heckler, bus: bus)

    # Handle incoming messages — the core processing guard
    # serializes all deliveries, preventing concurrent run()
    # calls from corrupting chat history.
    on_message do |message|
      next unless message.from == "comic"
      next if @rounds >= MAX_ROUNDS

      @rounds += 1

      verdict = run(
        "The comedian just said: \"#{message.content}\"\n\n" \
        "React however feels right — heckle, counter-joke, " \
        "show respect, or stay silent."
      ).reply.strip

      # The heckler chose silence — no output, no feedback
      next if verdict.match?(/\[SILENCE\]/i)

      @display.heckler("Heckler [Round #{@rounds}]", verdict)

      if verdict.match?(/laugh|love|hilarious|brilliant|great/i)
        @won_over = true
        @display.heckler_note("(won over!)")
      end

      # Send feedback to comic's personal channel until the set is done
      send_reply(to: message.from.to_sym, content: verdict, in_reply_to: message.key) if @rounds < MAX_ROUNDS
    end

    # Listen to the room for the comic's performances.
    # Route through the core processing guard.
    @bus.subscribe(:room) do |delivery|
      handle_incoming_delivery(delivery)
    end
  end
end
