# frozen_string_literal: true

module RobotLab
  module History
    # ActiveRecord-based history persistence adapter
    #
    # Provides thread and result storage using ActiveRecord models.
    # Requires Rails or standalone ActiveRecord setup.
    #
    # @example
    #   adapter = ActiveRecordAdapter.new(
    #     thread_model: RobotLabThread,
    #     result_model: RobotLabResult
    #   )
    #
    #   config = adapter.to_config
    #   network = RobotLab.create_network(history: config)
    #
    class ActiveRecordAdapter
      # @!attribute [r] thread_model
      #   @return [Class] ActiveRecord model class for threads
      # @!attribute [r] result_model
      #   @return [Class] ActiveRecord model class for results
      attr_reader :thread_model, :result_model

      # Initialize adapter with ActiveRecord models
      #
      # @param thread_model [Class] ActiveRecord model for threads
      # @param result_model [Class] ActiveRecord model for results
      #
      def initialize(thread_model:, result_model:)
        @thread_model = thread_model
        @result_model = result_model
      end

      # Create a new thread
      #
      # @param state [State] Current state
      # @param input [String, UserMessage] Initial input
      # @return [Hash] Thread ID and metadata
      #
      def create_thread(state:, input:, **)
        input_content = input.is_a?(UserMessage) ? input.content : input.to_s
        input_metadata = input.is_a?(UserMessage) ? input.metadata : {}

        thread = @thread_model.create!(
          thread_id: SecureRandom.uuid,
          initial_input: input_content,
          input_metadata: input_metadata,
          state_data: state.data.to_h
        )

        { thread_id: thread.thread_id, created_at: thread.created_at }
      end

      # Retrieve results for a thread
      #
      # @param thread_id [String] Thread identifier
      # @return [Array<RobotResult>] History of results
      #
      def get(thread_id:, **)
        @result_model
          .where(thread_id: thread_id)
          .order(:sequence_number, :created_at)
          .map { |record| deserialize_result(record) }
      end

      # Append user message to thread
      #
      # @param thread_id [String] Thread identifier
      # @param message [UserMessage] Message to append
      #
      def append_user_message(thread_id:, message:, **)
        @thread_model.where(thread_id: thread_id).update_all(
          last_user_message: message.content,
          last_user_message_at: Time.current
        )
      end

      # Append results to thread
      #
      # @param thread_id [String] Thread identifier
      # @param new_results [Array<RobotResult>] Results to append
      #
      def append_results(thread_id:, new_results:, **)
        base_sequence = @result_model.where(thread_id: thread_id).maximum(:sequence_number) || 0

        new_results.each_with_index do |result, index|
          @result_model.create!(
            thread_id: thread_id,
            robot_name: result.robot_name,
            sequence_number: base_sequence + index + 1,
            output_data: serialize_messages(result.output),
            tool_calls_data: serialize_messages(result.tool_calls),
            stop_reason: result.stop_reason,
            checksum: result.checksum
          )
        end

        # Update thread timestamp
        @thread_model.where(thread_id: thread_id).update_all(
          updated_at: Time.current
        )
      end

      # Convert adapter to Config object
      #
      # @return [Config] History configuration
      #
      def to_config
        Config.new(
          create_thread: method(:create_thread),
          get: method(:get),
          append_user_message: method(:append_user_message),
          append_results: method(:append_results)
        )
      end

      private

      def serialize_messages(messages)
        messages.map(&:to_h)
      end

      def deserialize_result(record)
        output = deserialize_messages(record.output_data)
        tool_calls = deserialize_messages(record.tool_calls_data)

        RobotResult.new(
          robot_name: record.robot_name,
          output: output,
          tool_calls: tool_calls,
          stop_reason: record.stop_reason
        )
      end

      def deserialize_messages(data)
        return [] unless data

        data.map do |msg_hash|
          Message.from_hash(msg_hash.symbolize_keys)
        end
      end
    end
  end
end
