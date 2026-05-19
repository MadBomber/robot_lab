# frozen_string_literal: true

# ── Comic Tools ─────────────────────────────────────────────
#
# Each tool accesses the owning robot via the `robot` accessor
# inherited from RobotLab::Tool.

class ReinventStyle < RobotLab::Tool
  description "Completely rewrite your comedy persona and approach. " \
              "Use when your current style is clearly not working. " \
              "Be bold — try something totally different. " \
              "The new style takes effect on your next bit."

  param :new_persona, type: "string",
        desc: "Your new comedy persona, style, and approach. " \
              "Be specific: what kind of humor, what voice, what attitude."

  def execute(new_persona:)
    robot.pending_reinvention = new_persona
    robot.style_changes += 1
    robot.display&.comic_tool("[reinvent_style] -> #{new_persona[0..70]}...")
    "Style reinvention accepted: #{new_persona}. " \
    "Commit to this new approach starting now."
  end
end

class AdjustEnergy < RobotLab::Tool
  description "Adjust your creative energy level. " \
              "Higher (0.8-1.0) = wilder, riskier, more unpredictable. " \
              "Lower (0.2-0.4) = tighter, more controlled, precise."

  param :level, type: "number",
        desc: "Energy level from 0.1 (very controlled) to 1.0 (unhinged)"
  param :reason, type: "string",
        desc: "Why you're adjusting", required: false

  def execute(level:, reason: "tactical adjustment")
    clamped = [[level.to_f, 0.1].max, 1.0].min
    robot.with_temperature(clamped)
    robot.display&.comic_tool("[adjust_energy] -> %.1f (%s)" % [clamped, reason])
    "Energy adjusted to #{clamped}. Reason: #{reason}"
  end
end

class GetCoaching < RobotLab::Tool
  description "Summon a comedy coach backstage for quick advice. " \
              "Use when you're struggling with the crowd and need " \
              "an outside perspective on what to try next."

  param :situation, type: "string",
        desc: "Describe what's happening and what you need help with"

  def execute(situation:)
    @coaches ||= {}
    coach = @coaches["comedy_coach"] ||= begin
      robot.coaches_spawned += 1
      robot.spawn(
        name: "comedy_coach",
        model: LLM[:default].model,
        system_prompt:
          "You are a veteran comedy coach backstage at a live show. " \
          "A comedian is struggling and needs quick, actionable advice. " \
          "Be direct and specific. One paragraph max. Tell them " \
          "exactly what to do differently in their next bit."
      )
    end
    advice = coach.run(situation).reply.strip
    robot.display&.comic_tool("[get_coaching] -> #{advice[0..70]}...")
    advice
  rescue => e
    robot.display&.comic_tool("[get_coaching] ERROR: #{e.message}")
    "Coach unavailable right now. Trust your instincts."
  end
end


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
  attr_accessor :round, :style_changes, :coaches_spawned,
                :pending_reinvention, :display

  def initialize(bus:, display:)
    @round              = 0
    @style_changes      = 0
    @coaches_spawned    = 0
    @pending_reinvention = nil
    @display            = display

    super(
      name: "comic",
      model: LLM[:default].model,
      template: :open_mic_comic,
      bus: bus,
      local_tools: [
        ReinventStyle.new(robot: self),
        AdjustEnergy.new(robot: self),
        GetCoaching.new(robot: self)
      ]
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
      bit = result.reply.strip

      @display.comic("Comic [Round #{@round}]", bit)

      # Publish to the room — heckler and scout both pick it up
      send_message(to: :room, content: "ROUND #{@round}: #{bit}")
    end
  end
end
