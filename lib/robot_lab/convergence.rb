# frozen_string_literal: true

module RobotLab
  # TF-IDF cosine similarity utilities for detecting semantic convergence
  # between two texts.
  #
  # Common use cases:
  # - Checking whether two independent verifiers have reached the same conclusion
  # - Skipping a reconciler LLM call when verifiers already agree (fast-path)
  # - Detecting when a multi-robot debate has converged on a consensus
  #
  # Requires the optional 'classifier' gem (~> 2.3).
  #
  # @example Skip reconciler when verifiers agree
  #   score = RobotLab::Convergence.similarity(result_a.reply, result_b.reply)
  #
  #   router = ->(args) do
  #     a = args.context[:verifier_a]&.reply.to_s
  #     b = args.context[:verifier_b]&.reply.to_s
  #     RobotLab::Convergence.detected?(a, b) ? nil : ["reconciler"]
  #   end
  module Convergence
    # Default cosine similarity threshold above which texts are convergent.
    DEFAULT_THRESHOLD = 0.85

    # Minimum text length (characters) for meaningful TF-IDF scoring.
    # Texts shorter than this always return 0.0 similarity.
    MIN_TEXT_LENGTH = 30

    # Determine whether two texts are semantically convergent.
    #
    # @param text_a [String]
    # @param text_b [String]
    # @param threshold [Float] minimum similarity to declare convergence (default 0.85)
    # @return [Boolean]
    # @raise [DependencyError] if the 'classifier' gem is not installed
    # @raise [ArgumentError] if threshold is outside [0.0, 1.0]
    def self.detected?(text_a, text_b, threshold: DEFAULT_THRESHOLD)
      unless (0.0..1.0).cover?(threshold)
        raise ArgumentError, "threshold must be in [0.0, 1.0], got #{threshold}"
      end

      similarity(text_a, text_b) >= threshold
    end

    # Compute cosine similarity between two texts using stemmed term frequencies.
    #
    # Uses +String#word_hash+ (provided by the classifier gem) to build
    # stemmed, stopword-filtered term-frequency vectors, then computes
    # L2-normalized cosine similarity. Term frequencies (no IDF) are used
    # because IDF on a 2-document corpus collapses shared terms to zero,
    # which would incorrectly penalize texts that agree on the same topic.
    #
    # Returns 0.0 when either text is blank or shorter than +MIN_TEXT_LENGTH+.
    #
    # @param text_a [String]
    # @param text_b [String]
    # @return [Float] in [0.0, 1.0]
    # @raise [DependencyError] if the 'classifier' gem is not installed
    def self.similarity(text_a, text_b)
      a = text_a.to_s.strip
      b = text_b.to_s.strip

      return 0.0 if a.length < MIN_TEXT_LENGTH || b.length < MIN_TEXT_LENGTH

      TextAnalysis.tf_cosine_similarity(a, b)
    end
  end
end
