# frozen_string_literal: true

class ChatController < ApplicationController
  def index
    @thread_id = session[:thread_id] ||= SecureRandom.uuid
    thread = RobotLabThread.find_by(session_id: @thread_id)
    @results = thread&.results&.to_a || []
  end

  def create
    thread_id = session[:thread_id] ||= SecureRandom.uuid
    message = params[:message].to_s.strip
    return redirect_to root_path if message.empty?

    RobotRunJob.perform_later(
      robot_class: "ChatRobot",
      message:     message,
      thread_id:   thread_id
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append("messages", partial: "chat/user_message", locals: { message: message }),
          turbo_stream.replace("robot_status", "<div id=\"robot_status\"><span class=\"thinking\">Thinking...</span></div>"),
          turbo_stream.update("robot_response", ""),
          turbo_stream.update("robot_tools", ""),
          turbo_stream.update("robot_errors", "")
        ]
      end
      format.html { redirect_to root_path }
    end
  end
end
