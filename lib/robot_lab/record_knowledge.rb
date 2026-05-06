# frozen_string_literal: true

module RobotLab
  # Tool that lets a robot record a piece of knowledge learned during a session.
  #
  # Use after a decision or discussion reveals something worth remembering:
  # a user preference, a reliable pattern, or a factual insight. Recorded
  # knowledge persists across future sessions via the robot's durable store.
  #
  # @example
  #   # LLM calls: record_knowledge(
  #   #   content: "User prefers concise responses",
  #   #   reasoning: "User asked for shorter answers twice",
  #   #   category: "preference",
  #   #   domain: "communication style"
  #   # )
  #
  class RecordKnowledge < Tool
    description "Record a piece of knowledge learned during this session. " \
                "Use after a decision or discussion reveals something worth remembering: " \
                "a user preference, a reliable pattern, or a factual insight. " \
                "Recorded knowledge persists across future sessions."

    param :content,   type: "string", desc: "The knowledge to record, in plain language (one clear statement)"
    param :reasoning, type: "string", desc: "Why this is worth remembering — the observation or discussion that led to it"
    param :category,  type: "string", desc: "One of: fact, preference, pattern, correction"
    param :domain,    type: "string", desc: "Topic area this applies to (e.g. 'newsletter curation', 'ruby tooling')"

    def execute(content:, reasoning:, category:, domain:)
      store = robot&.durable_store
      return "No durable store configured on this robot." unless store

      now = Time.now.iso8601
      entry = Durable::Entry.new(
        content:,
        reasoning:,
        category:   category.to_sym,
        domain:,
        confidence: 0.1,
        use_count:  0,
        created_at: now,
        updated_at: now
      )

      store.record(entry)
      robot.learn("#{content} (#{domain})")

      "Recorded: #{content}"
    end
  end
end
