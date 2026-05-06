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
        new(
          content:    hash["content"]    || hash[:content],
          reasoning:  hash["reasoning"]  || hash[:reasoning],
          category:   (hash["category"] || hash[:category]).to_sym,
          domain:     hash["domain"]     || hash[:domain],
          confidence: (hash["confidence"] || hash[:confidence]).to_f,
          use_count:  (hash["use_count"]  || hash[:use_count]).to_i,
          created_at: hash["created_at"] || hash[:created_at],
          updated_at: hash["updated_at"] || hash[:updated_at]
        )
      end
    end
  end
end
