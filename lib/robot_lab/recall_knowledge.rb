# frozen_string_literal: true

module RobotLab
  class RecallKnowledge < Tool
    description "Recall relevant knowledge from past sessions before making a decision. " \
                "Use this when uncertain whether to include or skip content, or when you want " \
                "to check if you have seen a similar situation before. " \
                "When in doubt and no relevant knowledge is found, skip the action."

    param :query,  type: "string", desc: "Natural language description of the decision you are about to make"
    param :domain, type: "string", desc: "Topic area to search (e.g. 'newsletter curation')", required: false

    def execute(query:, domain: nil)
      store = robot&.durable_store
      return "No durable store configured on this robot." unless store

      entries = store.recall(query: query, domain: domain, min_confidence: 0.0)

      if entries.empty?
        "No relevant past knowledge found for: #{query}. When in doubt, skip."
      else
        lines = entries.map do |e|
          "[#{e.category}/conf:#{format("%.1f", e.confidence)}] #{e.content} — #{e.reasoning}"
        end

        "Relevant past knowledge:\n#{lines.join("\n")}"
      end
    end
  end
end
