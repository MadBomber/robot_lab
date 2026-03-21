# frozen_string_literal: true

module RobotLab
  # Shared TF-IDF text analysis utilities.
  #
  # Wraps +Classifier::TFIDF+ from the optional 'classifier' gem (~> 2.3).
  # Call +require_classifier!+ before any analysis method to get a descriptive
  # error if the gem is missing rather than a bare NameError.
  #
  # Vectors returned by +transform+ are L2-normalized, so cosine similarity
  # equals the dot product of two vectors — no magnitude division needed.
  module TextAnalysis
    # Attempt to load the classifier gem.
    #
    # @raise [DependencyError] if the gem is not installed
    def self.require_classifier!
      load_classifier_gem
    rescue LoadError
      raise DependencyError,
            "The 'classifier' gem is required for text analysis features. " \
            "Add it to your Gemfile: gem 'classifier', '~> 2.3'"
    end

    # Load the classifier gem. Extracted for testability.
    #
    # @api private
    def self.load_classifier_gem
      require "classifier"
    end

    # Fit a TF-IDF model on a corpus of strings.
    #
    # @param corpus [Array<String>] non-empty array of document strings
    # @return [Classifier::TFIDF] fitted model
    def self.fit(corpus)
      model = Classifier::TFIDF.new(min_df: 1)
      model.fit(corpus)
      model
    end

    # Transform a string into an L2-normalized TF-IDF term vector.
    #
    # @param model [Classifier::TFIDF] a fitted model
    # @param text [String]
    # @return [Hash{Symbol => Float}] sparse term vector; empty if no known terms
    def self.transform(model, text)
      model.transform(text.to_s) || {}
    end

    # Cosine similarity between two L2-normalized sparse vectors.
    #
    # Since +Classifier::TFIDF+ returns L2-normalized vectors, this is just
    # a dot product. Result is clamped to [0.0, 1.0] to absorb float noise.
    #
    # @param vec_a [Hash{Symbol => Float}]
    # @param vec_b [Hash{Symbol => Float}]
    # @return [Float] in [0.0, 1.0]
    def self.cosine_similarity(vec_a, vec_b)
      return 0.0 if vec_a.empty? || vec_b.empty?

      [dot(vec_a, vec_b), 1.0].min
    end

    # Dot product of two sparse vectors (shared keys only).
    #
    # @param vec_a [Hash{Symbol => Float}]
    # @param vec_b [Hash{Symbol => Float}]
    # @return [Float]
    def self.dot(vec_a, vec_b)
      (vec_a.keys & vec_b.keys).sum { |k| vec_a[k] * vec_b[k] }.to_f
    end

    # L2-normalize a sparse vector.
    #
    # @param vec [Hash{Symbol => Numeric}]
    # @return [Hash{Symbol => Float}] normalized vector; {} if magnitude is zero
    def self.l2_normalize(vec)
      magnitude = Math.sqrt(vec.values.sum { |v| v * v }.to_f)
      return {} if magnitude.zero?

      vec.transform_values { |v| v.to_f / magnitude }
    end

    # Cosine similarity between two texts using stemmed term-frequency vectors.
    #
    # Uses +String#word_hash+ from the classifier gem (stems, removes stopwords)
    # and L2-normalized term frequencies. Unlike TF-IDF, this does not require
    # a reference corpus, making it reliable for direct 2-text comparison.
    # Returns 0.0 when either text is too short to produce a term vector.
    #
    # @param text_a [String]
    # @param text_b [String]
    # @return [Float] in [0.0, 1.0]
    def self.tf_cosine_similarity(text_a, text_b)
      require_classifier!

      vec_a = l2_normalize(text_a.word_hash)
      vec_b = l2_normalize(text_b.word_hash)

      cosine_similarity(vec_a, vec_b)
    end
  end
end
