# frozen_string_literal: true

module RobotLab
  module Streaming
    # Monotonic sequence counter for event ordering
    #
    # Provides globally unique, strictly increasing sequence numbers
    # for event ordering across streaming contexts.
    #
    # Thread-safe via Mutex.
    #
    class SequenceCounter
      def initialize(start: 0)
        @value = start
        @mutex = Mutex.new
      end

      # Get the next sequence number
      #
      # @return [Integer]
      #
      def next
        @mutex.synchronize do
          @value += 1
        end
      end

      # Get the current value without incrementing
      #
      # @return [Integer]
      #
      def current
        @mutex.synchronize { @value }
      end

      # Reset to a specific value
      #
      # @param value [Integer]
      #
      def reset(value = 0)
        @mutex.synchronize { @value = value }
      end
    end
  end
end
