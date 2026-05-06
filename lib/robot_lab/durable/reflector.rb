# frozen_string_literal: true

module RobotLab
  module Durable
    class Reflector
      def initialize(store:, domain:)
        @store  = store
        @domain = domain.to_s
      end

      # Examine plain-text learnings accumulated during a session and promote
      # any that are not already represented in the store.
      #
      # @param learnings [Array<String>] robot.learnings from the completed session
      def reflect(learnings)
        Array(learnings).each do |text|
          next if text.nil? || text.strip.empty?

          text = text.strip
          next if already_stored?(text)

          now = Time.now.iso8601
          @store.record(
            Entry.new(
              content:    text,
              reasoning:  "Observed during session (auto-promoted by Reflector)",
              category:   :pattern,
              domain:     @domain,
              confidence: 0.1,
              use_count:  0,
              created_at: now,
              updated_at: now
            )
          )
        end
      end

      private

      def already_stored?(text)
        @store.recall(query: text, domain: @domain, min_confidence: 0.0).any? do |e|
          e.content.downcase == text.downcase
        end
      end
    end
  end
end
