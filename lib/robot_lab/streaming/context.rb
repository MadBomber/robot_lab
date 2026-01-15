# frozen_string_literal: true

module RobotLab
  module Streaming
    # Context for managing streaming events during execution
    #
    # StreamingContext provides methods for publishing events with
    # automatic sequencing, timestamping, and ID generation.
    #
    # @example
    #   context = Context.new(
    #     run_id: "run_123",
    #     message_id: "msg_456",
    #     scope: "network",
    #     publish: ->(event) { broadcast(event) }
    #   )
    #
    #   context.publish_event(event: "text.delta", data: { delta: "Hello" })
    #
    class Context
      # @!attribute [r] run_id
      #   @return [String] the unique run identifier
      # @!attribute [r] parent_run_id
      #   @return [String, nil] the parent run identifier for nested contexts
      # @!attribute [r] message_id
      #   @return [String] the current message identifier
      # @!attribute [r] scope
      #   @return [String] the context scope (network, robot, etc.)
      attr_reader :run_id, :parent_run_id, :message_id, :scope

      # Creates a new streaming Context.
      #
      # @param run_id [String] unique run identifier
      # @param message_id [String] current message identifier
      # @param scope [String, Symbol] context scope
      # @param publish [Proc] callback for publishing events
      # @param parent_run_id [String, nil] parent run identifier
      # @param sequence_counter [SequenceCounter, nil] shared sequence counter
      def initialize(run_id:, message_id:, scope:, publish:, parent_run_id: nil, sequence_counter: nil)
        @run_id = run_id
        @parent_run_id = parent_run_id
        @message_id = message_id
        @scope = scope.to_s
        @publish = publish
        @sequence = sequence_counter || SequenceCounter.new
      end

      # Publish an event
      #
      # @param event [String] Event type
      # @param data [Hash] Event data
      #
      def publish_event(event:, data: {})
        chunk = build_chunk(event, data)

        begin
          @publish.call(chunk)
        rescue StandardError => e
          RobotLab.configuration.logger.warn("Streaming error: #{e.message}")
        end

        chunk
      end

      # Create a child context for nested robot runs
      #
      # @param robot_run_id [String]
      # @return [Context]
      #
      def create_child_context(robot_run_id)
        Context.new(
          run_id: robot_run_id,
          parent_run_id: @run_id,
          message_id: generate_message_id,
          scope: "robot",
          publish: @publish,
          sequence_counter: @sequence  # Share sequence counter
        )
      end

      # Create context with shared sequence counter
      #
      # @param run_id [String]
      # @param message_id [String]
      # @param scope [String]
      # @return [Context]
      #
      def create_context_with_shared_sequence(run_id:, message_id:, scope:)
        Context.new(
          run_id: run_id,
          message_id: message_id,
          scope: scope,
          publish: @publish,
          sequence_counter: @sequence
        )
      end

      # Generate a part ID (OpenAI-compatible, max 40 chars)
      #
      # @return [String]
      #
      def generate_part_id
        short_msg_id = @message_id[0, 8]
        timestamp = (Time.now.to_f * 1000).to_i.to_s[-6..]
        random = SecureRandom.hex(4)
        "part_#{short_msg_id}_#{timestamp}_#{random}"
      end

      # Generate a step ID for Inngest compatibility
      #
      # @param base_name [String]
      # @return [String]
      #
      def generate_step_id(base_name)
        "publish-#{@sequence.current}:#{base_name}"
      end

      # Generate a new message ID
      #
      # @return [String]
      #
      def generate_message_id
        SecureRandom.uuid
      end

      private

      def build_chunk(event, data)
        seq = @sequence.next
        {
          event: event,
          data: data.merge(
            run_id: @run_id,
            message_id: @message_id,
            scope: @scope
          ),
          timestamp: (Time.now.to_f * 1000).to_i,
          sequence_number: seq,
          id: "publish-#{seq}:#{event}"
        }
      end
    end
  end
end
