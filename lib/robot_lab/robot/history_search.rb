# frozen_string_literal: true

module RobotLab
  class Robot
    # Semantic search over a robot's conversation history.
    #
    # Owns:    nothing (read-only mixin)
    # Reads:   @chat (specifically @chat.messages)
    # Contract: no initialization required; safe to call any time after initialize
    #
    # Scores each message in @chat.messages against the query using stemmed
    # term-frequency cosine similarity (via the +classifier+ gem).  Returns the
    # top-N messages ranked by relevance.
    #
    # Requires the optional 'classifier' gem (~> 2.3).
    #
    # @example
    #   results = robot.search_history("quarterly revenue", limit: 3)
    #   results.each do |r|
    #     puts "[#{r.role}] (score #{r.score.round(3)}) #{r.text}"
    #   end
    module HistorySearch
      # Minimum text length (characters) for a message to be considered.
      MIN_SCORE_LENGTH = 20

      # Value object returned by {#search_history}.
      HistoryResult = Data.define(:text, :role, :score, :index)

      # Search the robot's conversation history for messages relevant to +query+.
      #
      # @param query [String] natural-language search query
      # @param limit [Integer] maximum number of results to return (default 5)
      # @return [Array<HistoryResult>] results sorted by score descending
      # @raise [RobotLab::DependencyError] if the 'classifier' gem is not installed
      # :reek:TooManyStatements -- linear vectorize/score/collect scan over the chat history.
      # :reek:FeatureEnvy -- scoring each message's extracted text against the query is the search itself.
      def search_history(query, limit: 5)
        TextAnalysis.require_classifier!

        query_vec = TextAnalysis.l2_normalize(query.word_hash)
        return [] if query_vec.empty?

        results = []

        @chat.messages.each_with_index do |msg, idx|
          text = extract_history_text(msg)
          next if text.nil? || text.strip.length < MIN_SCORE_LENGTH

          vec   = TextAnalysis.l2_normalize(text.word_hash)
          score = TextAnalysis.cosine_similarity(query_vec, vec)
          next if score.zero?

          results << HistoryResult.new(text: text, role: msg.role, score: score, index: idx)
        end

        results.sort_by { |r| -r.score }.first(limit)
      end

      private

      # Extract plain text from a message's content field.
      #
      # @param msg [Object] a RubyLLM message-like object
      # @return [String, nil]
      def extract_history_text(msg)
        content = msg.content
        case content
        when String then content
        when Array  then content.filter_map { |p| p[:text] || p["text"] }.join(" ")
        end
      end
    end
  end
end
