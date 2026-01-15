# frozen_string_literal: true

module RobotLab
  module History
    # Manages conversation thread lifecycle
    #
    # Handles thread creation, history retrieval, and result persistence
    # using the configured history adapter.
    #
    # @example
    #   manager = ThreadManager.new(config)
    #   thread_id = manager.create_thread(state: state, input: "Hello")
    #   history = manager.get_history(thread_id)
    #
    class ThreadManager
      # @!attribute [r] config
      #   @return [Config] the history configuration
      attr_reader :config

      # Initialize thread manager
      #
      # @param config [Config] History configuration
      #
      def initialize(config)
        @config = config
      end

      # Create a new conversation thread
      #
      # @param state [State] Current state
      # @param input [String, UserMessage] Initial input
      # @return [String] Thread ID
      #
      def create_thread(state:, input:)
        result = @config.create_thread!(state: state, input: input)
        result[:thread_id]
      end

      # Get history for a thread
      #
      # @param thread_id [String] Thread identifier
      # @return [Array<RobotResult>] History of results
      #
      def get_history(thread_id)
        @config.get!(thread_id: thread_id)
      end

      # Append user message to thread
      #
      # @param thread_id [String] Thread identifier
      # @param message [UserMessage] Message to append
      #
      def append_user_message(thread_id:, message:)
        @config.append_user_message!(thread_id: thread_id, message: message)
      end

      # Append results to thread
      #
      # @param thread_id [String] Thread identifier
      # @param results [Array<RobotResult>] Results to append
      #
      def append_results(thread_id:, results:)
        @config.append_results!(thread_id: thread_id, new_results: results)
      end

      # Load state from thread history
      #
      # @param thread_id [String] Thread identifier
      # @param state [State, Memory] State/Memory to populate
      # @return [State, Memory] State/Memory with loaded history
      #
      def load_state(thread_id:, state:)
        results = get_history(thread_id)

        state.thread_id = thread_id
        results.each { |r| state.append_result(r) }

        state
      end

      # Save state results to thread
      #
      # @param thread_id [String] Thread identifier
      # @param state [State] State with results to save
      # @param since_index [Integer] Save results from this index
      #
      def save_state(thread_id:, state:, since_index: 0)
        new_results = state.results[since_index..]
        append_results(thread_id: thread_id, results: new_results) if new_results.any?
      end
    end
  end
end
