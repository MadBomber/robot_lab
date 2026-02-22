# frozen_string_literal: true

class RobotRunJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 5.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(robot_class:, message:, thread_id:, **context)
    thread = RobotLabThread.find_or_create_by_session_id(thread_id)
    thread.update!(last_user_message: message, last_user_message_at: Time.current)

    robot  = resolve_robot(robot_class, thread_id)
    result = robot.run(message, **context)

    persist_result(thread, result)
    broadcast_completion(thread_id)
  rescue StandardError => e
    broadcast_error(thread_id, e)
    raise
  end

  private

  def resolve_robot(robot_class, thread_id)
    klass       = robot_class.to_s.constantize
    stream_name = "robot_lab_thread_#{thread_id}"

    if turbo_available?
      on_content = RobotLab::RailsIntegration::TurboStreamCallbacks.build_content_callback(
        stream_name: stream_name
      )
      on_tool_call = RobotLab::RailsIntegration::TurboStreamCallbacks.build_tool_call_callback(
        stream_name: stream_name
      )
      klass.build(on_content: on_content, on_tool_call: on_tool_call)
    else
      klass.build
    end
  end

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

  def broadcast_completion(thread_id)
    return unless turbo_available?

    Turbo::StreamsChannel.broadcast_replace_to(
      "robot_lab_thread_#{thread_id}",
      target: "robot_status",
      html: "<div id=\"robot_status\"><span class=\"complete\">Complete</span></div>"
    )
  end

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
