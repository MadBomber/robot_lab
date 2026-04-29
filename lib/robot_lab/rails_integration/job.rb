# frozen_string_literal: true

module RobotLab
  module RailsIntegration
    # Base class for RobotLab background jobs.
    #
    # Encapsulates the full robot-run lifecycle: robot class resolution,
    # Turbo Stream callback wiring, thread-record persistence, and
    # completion/error broadcasting. Suitable for fiber-safe execution
    # under Solid Queue's fiber mode (see issue #20 for SQ version details).
    #
    # @example Minimal subclass using the robot_class DSL
    #   class SupportRobotJob < RobotLab::Job
    #     queue_as :default
    #     robot_class SupportRobot
    #   end
    #
    #   # Enqueue (no robot_class: needed — taken from DSL):
    #   SupportRobotJob.perform_later(message: "Hello", thread_id: session_id)
    #
    # @example Generic job accepting robot_class at enqueue time
    #   class RobotRunJob < RobotLab::Job
    #     queue_as :default
    #   end
    #
    #   RobotRunJob.perform_later(
    #     robot_class: "SupportRobot",
    #     message:     params[:message],
    #     thread_id:   session_id
    #   )
    #
    class Job < ActiveJob::Base
      # Set or get the default robot class for this job subclass.
      #
      # @overload robot_class
      #   @return [Class, nil] the configured robot class
      # @overload robot_class(klass)
      #   @param klass [Class] the robot class (must respond to .build)
      #   @return [Class]
      def self.robot_class(klass = nil)
        klass ? @robot_class = klass : @robot_class
      end

      retry_on StandardError, wait: 5.seconds, attempts: 3
      discard_on ActiveJob::DeserializationError

      # Run a robot as a background job.
      #
      # When +thread_id+ is provided the job:
      # - Finds or creates a +RobotLabThread+ record and updates its last-message fields
      # - Wires +TurboStreamCallbacks+ onto the robot (when turbo-rails is present)
      # - Persists the +RobotResult+ to +RobotLabResult+
      # - Broadcasts a completion or error event via Turbo Streams
      #
      # When +thread_id+ is omitted the robot runs in a fire-and-forget mode —
      # no persistence, no broadcasting, result returned directly.
      #
      # @param message [String] the user message forwarded to robot.run
      # @param robot_class [String, Class, nil] override; falls back to the class-level DSL
      # @param thread_id [String, nil] session key for persistence and Turbo broadcasting
      # @param context [Hash] additional keyword args forwarded to robot.run
      # @return [RobotResult]
      def perform(message:, robot_class: nil, thread_id: nil, **context)
        klass  = resolve_robot_class(robot_class)
        thread = setup_thread(thread_id, message)
        robot  = build_robot(klass, thread_id)
        result = robot.run(message, **context)

        if thread
          persist_result(thread, result)
          broadcast_completion(thread_id)
        end

        result
      rescue StandardError => e
        broadcast_error(thread_id, e) if thread_id
        raise
      end

      private

      # Resolve the robot class from the runtime arg or the class-level DSL.
      def resolve_robot_class(runtime_class)
        klass = runtime_class || self.class.robot_class
        raise ArgumentError,
              "No robot class specified. Pass robot_class: to perform or set robot_class on the job class." \
          unless klass

        return klass if klass.is_a?(Class)

        klass.to_s.constantize
      end

      # Find or create the thread record and stamp the incoming message.
      # Returns nil when thread_id is absent (fire-and-forget mode).
      def setup_thread(thread_id, message)
        return nil unless thread_id

        thread = "RobotLabThread".constantize.find_or_create_by_session_id(thread_id)
        thread.update!(last_user_message: message, last_user_message_at: Time.current)
        thread
      end

      # Build the robot, wiring Turbo callbacks when thread_id + turbo-rails are present.
      def build_robot(klass, thread_id)
        if thread_id && turbo_available?
          stream_name  = "robot_lab_thread_#{thread_id}"
          on_content   = TurboStreamCallbacks.build_content_callback(stream_name: stream_name)
          on_tool_call = TurboStreamCallbacks.build_tool_call_callback(stream_name: stream_name)
          klass.build(on_content: on_content, on_tool_call: on_tool_call)
        else
          klass.build
        end
      end

      # Append a RobotLabResult record to the thread.
      def persist_result(thread, result)
        sequence = thread.results.maximum(:sequence_number).to_i + 1
        exported = result.export

        thread.results.create!(
          robot_name:      result.robot_name,
          sequence_number: sequence,
          output_data:     exported[:output],
          tool_calls_data: exported[:tool_calls],
          stop_reason:     result.stop_reason,
          checksum:        result.checksum
        )
      end

      # Broadcast a "Complete" badge to the Turbo Stream.
      def broadcast_completion(thread_id)
        return unless turbo_available?

        Turbo::StreamsChannel.broadcast_replace_to(
          "robot_lab_thread_#{thread_id}",
          target: "robot_status",
          html: "<div id=\"robot_status\"><span class=\"complete\">Complete</span></div>"
        )
      end

      # Broadcast an HTML-escaped error message to the Turbo Stream.
      def broadcast_error(thread_id, error)
        return unless turbo_available?

        Turbo::StreamsChannel.broadcast_append_to(
          "robot_lab_thread_#{thread_id}",
          target: "robot_errors",
          html: "<div class=\"error\">#{ERB::Util.html_escape(error.message)}</div>"
        )
      end

      def turbo_available?
        defined?(Turbo::StreamsChannel)
      end
    end
  end
end
