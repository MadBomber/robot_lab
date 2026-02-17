# frozen_string_literal: true

# ── Scout Tools ────────────────────────────────────────────
#
# Each tool accesses the owning robot via the `robot` accessor
# inherited from RobotLab::Tool.

class RecruitAnalyst < RobotLab::Tool
  description "Bring in a specialist to analyze a specific aspect " \
              "of the comedian's performance. The analyst will " \
              "review your accumulated notes and provide insight."

  param :specialty, type: "string",
        desc: "What to analyze: timing, crowd_work, " \
              "originality, adaptability, stage_presence, " \
              "material_evolution"

  def execute(specialty:)
    @analysts ||= {}
    specialty = specialty.to_s.downcase.gsub(/\s+/, "_")
    analyst = @analysts[specialty] ||= begin
      robot.analysts_spawned += 1
      robot.spawn(
        name: "#{specialty}_analyst",
        system_prompt:
          "You are an expert #{specialty.tr('_', ' ')} analyst " \
          "for stand-up comedy. You've studied the craft for decades. " \
          "Analyze the performance notes you're given. Be concise " \
          "and insightful. 2-3 sentences max."
      )
    end
    analysis = analyst.run(robot.log.join("\n")).reply.strip
    robot.display&.scout_analyst(specialty, analysis)
    analysis
  rescue => e
    robot.display&.scout_analyst(specialty, "ERROR: #{e.message}")
    "Analysis unavailable for #{specialty}. Rely on your own observations."
  end
end

class RefineCriteria < RobotLab::Tool
  description "Update your own evaluation criteria based on what " \
              "you're observing. Use when you realize the most " \
              "important qualities aren't what you initially expected. " \
              "The update takes effect on your next evaluation."

  param :updated_criteria, type: "string",
        desc: "Your refined evaluation criteria and focus areas"

  def execute(updated_criteria:)
    robot.pending_criteria = updated_criteria
    robot.display&.scout_criteria(updated_criteria)
    "Criteria refinement accepted: #{updated_criteria}. " \
    "Apply these updated criteria to all future evaluations."
  end
end


# ── The Talent Scout ─────────────────────────────────────────
#
# Has two tools with side effects:
#
#   recruit_analyst  — spawns a specialist to analyze an aspect
#                      of the performance (dynamic creation)
#   refine_criteria  — queues a rewrite of the scout's own
#                      evaluation criteria (self-modification)
#
# The scout observes each round, accumulates notes, and spawns
# analysts when they see something worth examining closely.
#
# Subscribes to the :room channel to observe performances.
# Room deliveries are routed through the core processing guard
# (BusMessaging#handle_incoming_delivery), which serializes all
# run() calls to prevent Async fiber interleaving from corrupting
# chat history.
#
class Scout < RobotLab::Robot
  attr_accessor :log, :analysts_spawned, :pending_criteria, :display

  def initialize(bus:, display:)
    @log = []
    @analysts_spawned = 0
    @pending_criteria = nil
    @display = display

    super(
      name: "scout",
      template: :open_mic_scout,
      bus: bus,
      local_tools: [
        RecruitAnalyst.new(robot: self),
        RefineCriteria.new(robot: self)
      ]
    )

    # Handle incoming messages — the core processing guard
    # serializes all deliveries, preventing concurrent run()
    # calls from corrupting chat history.
    on_message do |message|
      next unless message.from == "comic"
      observe_and_note(message.content.to_s)
    end

    # Listen to the room for the comic's performances.
    # Route through the core processing guard.
    @bus.subscribe(:room) do |delivery|
      handle_incoming_delivery(delivery)
    end
  end

  # Build the final verdict prompt with any pending criteria applied
  def verdict_prompt
    prompt = ""

    if @pending_criteria
      prompt += "CRITERIA UPDATE: #{@pending_criteria}. " \
                "Apply these updated criteria to your final assessment.\n\n"
      @pending_criteria = nil
    end

    prompt += "The show is over. Based on everything you've observed " \
              "(#{@log.size} rounds), all your notes, and any analyst " \
              "reports, write your final talent assessment. Should this " \
              "comedian get a callback? Be specific about what worked, " \
              "what didn't, and what potential you see."

    prompt
  end

  private

  def observe_and_note(content)
    @log << content

    # Build the prompt, injecting any queued criteria refinement.
    # This embeds self-modification in the user prompt rather than
    # rewriting system messages, avoiding chat message ordering issues.
    prompt = ""

    if @pending_criteria
      prompt += "CRITERIA UPDATE: #{@pending_criteria}. " \
                "Apply these updated criteria to this and all future evaluations.\n\n"
      @pending_criteria = nil
    end

    prompt += "You just observed: \"#{content}\"\n\n" \
              "This is round #{@log.size} of the performance. " \
              "Write your notes. If you've seen enough to identify " \
              "patterns, consider recruiting an analyst or refining " \
              "your evaluation criteria."

    notes = run(prompt).reply.strip

    @display.scout(@log.size, notes)
  end
end
