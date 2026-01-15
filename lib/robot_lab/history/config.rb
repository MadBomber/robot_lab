# frozen_string_literal: true

module RobotLab
  module History
    # Configuration for conversation history persistence
    #
    # Defines callbacks for creating threads, retrieving history,
    # and appending messages/results.
    #
    # @example
    #   config = History::Config.new(
    #     create_thread: ->(state:, input:, **) {
    #       { thread_id: SecureRandom.uuid }
    #     },
    #     get: ->(thread_id:, **) {
    #       database.find_results(thread_id)
    #     },
    #     append_results: ->(thread_id:, new_results:, **) {
    #       database.insert_results(thread_id, new_results)
    #     }
    #   )
    #
    class Config
      # @!attribute [rw] create_thread
      #   @return [Proc, nil] callback to create a new conversation thread
      # @!attribute [rw] get
      #   @return [Proc, nil] callback to retrieve history for a thread
      # @!attribute [rw] append_user_message
      #   @return [Proc, nil] callback to append user messages
      # @!attribute [rw] append_results
      #   @return [Proc, nil] callback to append robot results
      attr_accessor :create_thread, :get, :append_user_message, :append_results

      # Initialize history configuration
      #
      # @param create_thread [Proc] Callback to create a new thread
      # @param get [Proc] Callback to retrieve history for a thread
      # @param append_user_message [Proc] Callback to append user messages
      # @param append_results [Proc] Callback to append robot results
      #
      def initialize(create_thread: nil, get: nil, append_user_message: nil, append_results: nil)
        @create_thread = create_thread
        @get = get
        @append_user_message = append_user_message
        @append_results = append_results
      end

      # Check if history persistence is configured
      #
      # @return [Boolean]
      #
      def configured?
        @create_thread && @get
      end

      # Create a new conversation thread
      #
      # @param state [State] Current state
      # @param input [String, UserMessage] Initial input
      # @param kwargs [Hash] Additional arguments
      # @return [Hash] Must include :thread_id
      #
      def create_thread!(state:, input:, **kwargs)
        raise HistoryError, "create_thread callback not configured" unless @create_thread

        result = @create_thread.call(state: state, input: input, **kwargs)

        unless result.is_a?(Hash) && result[:thread_id]
          raise HistoryError, "create_thread must return a hash with :thread_id"
        end

        result
      end

      # Retrieve history for a thread
      #
      # @param thread_id [String] Thread identifier
      # @param kwargs [Hash] Additional arguments
      # @return [Array<RobotResult>] History of results
      #
      def get!(thread_id:, **kwargs)
        raise HistoryError, "get callback not configured" unless @get

        @get.call(thread_id: thread_id, **kwargs)
      end

      # Append a user message to the thread
      #
      # @param thread_id [String] Thread identifier
      # @param message [UserMessage] Message to append
      # @param kwargs [Hash] Additional arguments
      #
      def append_user_message!(thread_id:, message:, **kwargs)
        return unless @append_user_message

        @append_user_message.call(thread_id: thread_id, message: message, **kwargs)
      end

      # Append robot results to the thread
      #
      # @param thread_id [String] Thread identifier
      # @param new_results [Array<RobotResult>] Results to append
      # @param kwargs [Hash] Additional arguments
      #
      def append_results!(thread_id:, new_results:, **kwargs)
        return unless @append_results

        @append_results.call(thread_id: thread_id, new_results: new_results, **kwargs)
      end
    end

    # Error raised when history operations fail
    class HistoryError < RobotLab::Error; end
  end
end
