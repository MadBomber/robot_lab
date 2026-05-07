# frozen_string_literal: true

module RobotLab
  # Detects and interrupts tool-call doom loops inside the LLM agent loop.
  #
  # A doom loop occurs when the LLM repeatedly calls the same tool(s) in a
  # cycle — either identical consecutive calls (A, A, A) or a repeating
  # multi-step pattern (A, B, C, A, B, C, A, B, C).
  #
  # When a doom loop is detected the warning is embedded in the tool result
  # so the LLM sees it in its next context window and can self-correct.
  #
  # @example Basic usage
  #   detector = DoomLoopDetector.new(threshold: 3)
  #   detector.track("search")
  #   detector.track("search")
  #   detector.track("search")
  #   detector.doom_loop?  # => true
  #   detector.warning_message
  #   # => "Tool 'search' has been called 3 times consecutively..."
  class DoomLoopDetector
    DEFAULT_THRESHOLD = 3
    MAX_PERIOD = 10

    attr_reader :sequence

    def initialize(threshold: DEFAULT_THRESHOLD)
      @threshold = threshold
      @sequence  = []
    end

    def track(tool_name)
      @sequence << tool_name.to_s
    end

    def doom_loop?
      seq = @sequence
      return false if seq.length < @threshold

      # Consecutive identical calls: A, A, A
      tail = seq.last(@threshold)
      return true if tail.uniq.length == 1

      # Cyclic multi-step patterns: A,B,C, A,B,C, A,B,C
      max_period = [MAX_PERIOD, seq.length / @threshold].min
      (2..max_period).each do |period|
        window = @threshold * period
        next if seq.length < window

        chunk = seq.last(window)
        pattern = chunk.first(period)
        return true if chunk == pattern * @threshold
      end

      false
    end

    def reset
      @sequence = []
    end

    def warning_message
      seq = @sequence
      return "" if seq.empty?

      period = detect_period(seq)
      if period == 1
        tool = seq.last
        "Tool '#{tool}' has been called #{@threshold}+ times consecutively with " \
          "no progress. You appear to be stuck in a loop. Try a fundamentally " \
          "different approach, use a different tool, or ask for clarification."
      else
        pattern = seq.last(period).join(" → ")
        "Tool call pattern [#{pattern}] has repeated #{@threshold}+ times. " \
          "You appear to be stuck in a loop. Try a fundamentally different " \
          "approach, use a different tool, or ask for clarification."
      end
    end

    private

    def detect_period(seq)
      return 1 if seq.last(@threshold).uniq.length == 1

      max_period = [MAX_PERIOD, seq.length / @threshold].min
      (2..max_period).each do |period|
        window = @threshold * period
        next if seq.length < window

        chunk = seq.last(window)
        pattern = chunk.first(period)
        return period if chunk == pattern * @threshold
      end

      1
    end
  end
end
