# frozen_string_literal: true

module RobotLab
  module Durable
    Entry = Data.define(:content, :reasoning, :category, :domain, :confidence, :use_count, :created_at, :updated_at) do
      CONFIDENCE_INCREMENT = 0.1
      MAX_CONFIDENCE       = 1.0

      # Return a new Entry with confidence incremented and use_count bumped.
      def confirm
        new_confidence = [confidence + CONFIDENCE_INCREMENT, MAX_CONFIDENCE].min
        with(
          confidence: new_confidence.round(10),
          use_count:  use_count + 1,
          updated_at: Time.now.iso8601
        )
      end

      # Serialize to a plain Hash with string keys (safe for YAML round-trip).
      def to_h
        {
          "content"    => content,
          "reasoning"  => reasoning,
          "category"   => category.to_s,
          "domain"     => domain,
          "confidence" => confidence,
          "use_count"  => use_count,
          "created_at" => created_at,
          "updated_at" => updated_at
        }
      end

      # Deserialize from a Hash (string or symbol keys).
      def self.from_h(hash)
        h = hash.transform_keys(&:to_s)
        new(
          content:    h["content"],
          reasoning:  h["reasoning"],
          category:   h["category"]&.to_sym,
          domain:     h["domain"],
          confidence: h["confidence"].to_f,
          use_count:  h["use_count"].to_i,
          created_at: h["created_at"],
          updated_at: h["updated_at"]
        )
      end
    end
  end
end
