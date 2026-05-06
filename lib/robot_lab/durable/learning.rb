# frozen_string_literal: true

module RobotLab
  module Durable
    module Learning
      # Configure durable learning on a robot after initialization.
      #
      # @param domain [String] topic area for this robot's knowledge
      # @param store_path [String, nil] override default ~/.robot_lab/durable path
      def setup_durable_learning(domain:, store_path: nil)
        @learn_domain  = domain.to_s
        opts           = store_path ? { path: store_path } : {}
        @durable_store = Store.new(**opts)

        seed_from_store
        @local_tools = (@local_tools + [RecallKnowledge, RecordKnowledge]).uniq
      end

      # Run the end-of-session reflection pass.
      # Called automatically from Robot#run when durable learning is active.
      def run_reflector
        return unless @durable_store && @learn_domain && @learnings&.any?

        Reflector.new(store: @durable_store, domain: @learn_domain).reflect(@learnings)
      end

      private

      def seed_from_store
        return unless @durable_store && @learn_domain

        entries = @durable_store.recall(query: @learn_domain, domain: @learn_domain, min_confidence: 0.0)
        entries.each do |e|
          learn("[#{e.category}] #{e.content}: #{e.reasoning}")
        end
      end
    end
  end
end
