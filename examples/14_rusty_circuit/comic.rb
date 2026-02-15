# frozen_string_literal: true

# ── The Comic ────────────────────────────────────────────────
#
# Has three tools, all with side effects on the robot itself:
#
#   reinvent_style — queues a system prompt rewrite (applied next round)
#   adjust_energy  — changes the comic's temperature immediately
#   get_coaching   — spawns a comedy coach on the shared bus
#
# The LLM decides when to call them. The developer provides the
# mechanism; the robot provides the judgment.
#
# Listens on personal :comic channel for heckler feedback.
# Publishes performances to the shared :room channel.
#
class Comic < RobotLab::Robot
  attr_reader :round, :style_changes, :coaches_spawned

  def initialize(bus:, display:)
    @round              = 0
    @style_changes      = 0
    @coaches_spawned    = 0
    @coaches            = {}
    @pending_reinvention = nil
    @display            = display

    comic = self # captured by tool closures
    display_ref = display

    reinvent_style = RobotLab::Tool.new(
      name: "reinvent_style",
      description: "Completely rewrite your comedy persona and approach. " \
                   "Use when your current style is clearly not working. " \
                   "Be bold — try something totally different. " \
                   "The new style takes effect on your next bit.",
      parameters: {
        type: "object",
        properties: {
          new_persona: {
            type: "string",
            description: "Your new comedy persona, style, and approach. " \
                         "Be specific: what kind of humor, what voice, what attitude."
          }
        },
        required: ["new_persona"]
      },
      handler: ->(input, **) {
        # Queue the change — applied before the next round's run
        comic.instance_variable_set(:@pending_reinvention, input[:new_persona])
        comic.instance_variable_set(:@style_changes, comic.style_changes + 1)
        display_ref.comic_tool("[reinvent_style] -> #{input[:new_persona][0..70]}...")
        "Style reinvention accepted: #{input[:new_persona]}. " \
        "Commit to this new approach starting now."
      }
    )

    adjust_energy = RobotLab::Tool.new(
      name: "adjust_energy",
      description: "Adjust your creative energy level. " \
                   "Higher (0.8-1.0) = wilder, riskier, more unpredictable. " \
                   "Lower (0.2-0.4) = tighter, more controlled, precise.",
      parameters: {
        type: "object",
        properties: {
          level: {
            type: "number",
            description: "Energy level from 0.1 (very controlled) to 1.0 (unhinged)"
          },
          reason: {
            type: "string",
            description: "Why you're adjusting"
          }
        },
        required: ["level"]
      },
      handler: ->(input, **) {
        clamped = [[input[:level].to_f, 0.1].max, 1.0].min
        comic.with_temperature(clamped)
        reason = input[:reason] || "tactical adjustment"
        display_ref.comic_tool("[adjust_energy] -> %.1f (%s)" % [clamped, reason])
        "Energy adjusted to #{clamped}. Reason: #{reason}"
      }
    )

    get_coaching = RobotLab::Tool.new(
      name: "get_coaching",
      description: "Summon a comedy coach backstage for quick advice. " \
                   "Use when you're struggling with the crowd and need " \
                   "an outside perspective on what to try next.",
      parameters: {
        type: "object",
        properties: {
          situation: {
            type: "string",
            description: "Describe what's happening and what you need help with"
          }
        },
        required: ["situation"]
      },
      handler: ->(input, **) {
        begin
          coach = comic.instance_variable_get(:@coaches)["comedy_coach"] ||= begin
            comic.instance_variable_set(
              :@coaches_spawned,
              comic.coaches_spawned + 1
            )
            comic.spawn(
              name: "comedy_coach",
              system_prompt:
                "You are a veteran comedy coach backstage at a live show. " \
                "A comedian is struggling and needs quick, actionable advice. " \
                "Be direct and specific. One paragraph max. Tell them " \
                "exactly what to do differently in their next bit."
            )
          end
          advice = coach.run(input[:situation]).last_text_content.strip
          display_ref.comic_tool("[get_coaching] -> #{advice[0..70]}...")
          advice
        rescue => e
          display_ref.comic_tool("[get_coaching] ERROR: #{e.message}")
          "Coach unavailable right now. Trust your instincts."
        end
      }
    )

    super(
      name: "comic",
      template: :open_mic_comic,
      bus: bus,
      local_tools: [reinvent_style, adjust_energy, get_coaching]
    )

    # Listen on personal channel for heckler feedback
    on_message do |message|
      next unless message.from == "heckler"

      @round += 1

      # Build the prompt, injecting any queued style reinvention.
      # This embeds self-modification in the user prompt rather than
      # rewriting system messages, avoiding chat message ordering issues.
      prompt = "Round #{@round}."

      if @pending_reinvention
        prompt += "\n\nSTYLE REINVENTION: You are now #{@pending_reinvention}. " \
                  "Commit fully to this new style. Abandon your previous approach."
        @pending_reinvention = nil
      end

      prompt += "\n\nThe heckler just shouted: \"#{message.content}\"\n\n" \
                "Process their feedback. If your material isn't landing, " \
                "use your tools to adapt — reinvent your style, adjust " \
                "your energy, or get coaching. Then deliver your next bit."

      result = run(prompt)
      bit = result.last_text_content.strip

      @display.comic("Comic [Round #{@round}]", bit)

      # Publish to the room — heckler and scout both pick it up
      send_message(to: :room, content: "ROUND #{@round}: #{bit}")
    end
  end
end
