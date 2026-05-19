# frozen_string_literal: true

module RobotLab
  # Compresses a robot's conversation history using TF-IDF relevance scoring.
  #
  # Old conversation turns are tiered against the most recent context:
  # - High relevance (score >= keep_threshold)  → kept verbatim
  # - Medium relevance (drop_threshold..keep_threshold) → summarized or dropped
  # - Low relevance (score < drop_threshold)    → dropped
  #
  # System messages and tool call/result messages are always preserved.
  # The most recent +recent_turns+ user+assistant pairs are also always kept.
  #
  # Requires the optional 'classifier' gem (~> 2.3).
  #
  # @example Basic usage from Robot
  #   robot.compress_history(recent_turns: 3, keep_threshold: 0.6, drop_threshold: 0.2)
  #
  # @example With LLM summarizer (separate robot)
  #   summarizer_robot = RobotLab.build(name: "summarizer", system_prompt: "Summarize concisely.")
  #   robot.compress_history(
  #     summarizer: ->(text) { summarizer_robot.run("One sentence: #{text}").reply }
  #   )
  class HistoryCompressor
    # Minimum text length (characters) to score; shorter messages are kept as-is.
    MIN_SCORE_LENGTH = 20

    # Minimal duck-type for a summary replacement message compatible with
    # RubyLLM::Chat's message array. Preserves the original message role so
    # user/assistant turn ordering is maintained after compression.
    SUMMARY_STRUCT = Struct.new(:role, :content, :tool_calls, :stop_reason) do
      def text?      = true
      def tool_use?  = false
      def system?    = role == :system
      def user?      = role == :user
      def assistant? = role == :assistant
    end

    # @param messages [Array] full @chat.messages array
    # @param recent_turns [Integer] number of user+assistant turn pairs to protect
    # @param keep_threshold [Float] score >= this → keep verbatim
    # @param drop_threshold [Float] score < this → drop
    # @param summarizer [#call, nil] callable(text) -> String for medium-tier;
    #                                nil means drop medium-tier
    # @raise [ArgumentError] if keep_threshold <= drop_threshold
    def initialize(messages:, recent_turns:, keep_threshold:, drop_threshold:, summarizer:)
      if keep_threshold <= drop_threshold
        raise ArgumentError,
              "keep_threshold (#{keep_threshold}) must be greater than drop_threshold (#{drop_threshold})"
      end

      @messages        = messages
      @recent_turns    = recent_turns
      @keep_threshold  = keep_threshold
      @drop_threshold  = drop_threshold
      @summarizer      = summarizer
    end

    # Execute compression and return the new message array.
    #
    # @return [Array] compressed message array
    def call
      return @messages if @messages.empty?

      # Classify each message index as pinned (always keep) or scorable
      pinned_indices   = []
      scorable_indices = []

      @messages.each_with_index do |msg, idx|
        if pinned_message?(msg)
          pinned_indices << idx
        else
          scorable_indices << idx
        end
      end

      # Nothing scorable, or everything fits inside the recent window: return as-is
      return @messages if scorable_indices.empty?
      return @messages if scorable_indices.size <= @recent_turns * 2

      recent_count        = @recent_turns * 2
      compressible        = scorable_indices[0..-(recent_count + 1)]
      recent              = scorable_indices[-recent_count..]

      return @messages if compressible.nil? || compressible.empty?

      # Build reference vector from the recent window using stemmed term frequencies.
      # Term frequencies (no IDF) are used because IDF on a topic-focused corpus
      # would suppress the very terms that indicate relevance to that topic.
      recent_texts = recent.filter_map { |i| extract_text(@messages[i]) }
                           .reject { |t| t.strip.length < MIN_SCORE_LENGTH }

      # No meaningful recent text → cannot score; return unchanged
      return @messages if recent_texts.empty?

      TextAnalysis.require_classifier!

      recent_vectors = recent_texts.map { |t| TextAnalysis.l2_normalize(t.word_hash) }
      reference      = mean_vector(recent_vectors)

      # Decide action for each compressible message
      actions = {}
      compressible.each do |idx|
        actions[idx] = score_action(reference, @messages[idx])
      end

      # Reconstruct the message array in original order
      build_result(actions)
    end

    private

    # Determine the action for one compressible message.
    #
    # @return [Symbol, String] :keep, :drop, or a summary String
    def score_action(reference, msg)
      text = extract_text(msg)

      # Too short to score reliably → keep
      return :keep if text.nil? || text.strip.length < MIN_SCORE_LENGTH

      vec   = TextAnalysis.l2_normalize(text.word_hash)
      score = TextAnalysis.cosine_similarity(vec, reference)

      if score >= @keep_threshold
        :keep
      elsif score < @drop_threshold || !@summarizer
        :drop
      else
        summary = @summarizer.call(text).to_s.strip
        summary.empty? ? :drop : summary
      end
    end

    # Build the final message array from the decided actions.
    def build_result(actions)
      result = []

      @messages.each_with_index do |msg, idx|
        action = actions[idx]

        if action.nil? || action == :keep
          result << msg
        elsif action == :drop
          # Omit entirely
        else
          # action is a summary String; preserve original role to keep turn ordering
          result << SUMMARY_STRUCT.new(msg.role, action, nil, :stop)
        end
      end

      result
    end

    # True if a message should never be scored or removed.
    #
    # System messages and tool-related messages are always pinned.
    # Assistant messages with no text content (tool call dispatchers)
    # are also pinned to avoid breaking tool_use/tool_result pairing.
    def pinned_message?(msg)
      role = msg.role

      return true if role == :system
      return true if %i[tool tool_result].include?(role)

      # Assistant tool-call dispatcher: content is nil or blank
      if role == :assistant
        text = extract_text(msg)
        return true if text.nil? || text.strip.empty?
      end

      false
    end

    # Extract plain text from a message's content field.
    #
    # @return [String, nil]
    def extract_text(msg)
      content = msg.content
      case content
      when String then content
      when Array  then content.filter_map { |p| p[:text] || p["text"] }.join(" ")
      end
    end

    # Element-wise mean of a list of sparse vectors.
    #
    # @param vectors [Array<Hash{Symbol => Float}>]
    # @return [Hash{Symbol => Float}]
    def mean_vector(vectors)
      return {} if vectors.empty?

      sum = Hash.new(0.0)
      vectors.each { |v| v.each { |k, val| sum[k] += val } }
      n = vectors.size.to_f
      sum.transform_values { |v| v / n }
    end
  end
end
