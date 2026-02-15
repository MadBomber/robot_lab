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
      robot.instance_variable_set(
        :@analysts_spawned,
        robot.analysts_spawned + 1
      )
      robot.spawn(
        name: "#{specialty}_analyst",
        system_prompt:
          "You are an expert #{specialty.tr('_', ' ')} analyst " \
          "for stand-up comedy. You've studied the craft for decades. " \
          "Analyze the performance notes you're given. Be concise " \
          "and insightful. 2-3 sentences max."
      )
    end
    analysis = analyst.run(robot.log.join("\n")).last_text_content.strip
    robot.instance_variable_get(:@display)&.scout_analyst(specialty, analysis)
    analysis
  rescue => e
    robot.instance_variable_get(:@display)&.scout_analyst(specialty, "ERROR: #{e.message}")
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
    robot.instance_variable_set(:@pending_criteria, updated_criteria)
    robot.instance_variable_get(:@display)&.scout_criteria(updated_criteria)
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
# Uses a processing guard to serialize run() calls — TypedBus
# delivers messages in concurrent Async fibers, and interleaved
# run() calls on the same @chat would corrupt tool_use/tool_result
# ordering in the Anthropic API.
#
class Scout < RobotLab::Robot
  attr_reader :log, :analysts_spawned

  def initialize(bus:, display:)
    @log = []
    @analysts_spawned = 0
    @pending_criteria = nil
    @processing = false
    @observation_queue = []
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

    # Listen to the room for the comic's performances.
    # Processing guard prevents concurrent run() calls on @chat —
    # observations that arrive while processing are queued and
    # drained sequentially after the current one completes.
    @bus.subscribe(:room) do |delivery|
      delivery.ack!
      message = delivery.message
      next unless message.from == "comic"

      if @processing
        @observation_queue << message.content.to_s
      else
        process_observation(message.content.to_s)
      end
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

  def process_observation(content)
    @processing = true

    observe_and_note(content)

    # Drain any observations that arrived while we were processing
    while (queued = @observation_queue.shift)
      observe_and_note(queued)
    end

    @processing = false
  end

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

    notes = run(prompt).last_text_content.strip

    @display.scout(@log.size, notes)
  end
end
