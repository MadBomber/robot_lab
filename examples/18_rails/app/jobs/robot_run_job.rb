# frozen_string_literal: true

# Generic background job for executing any robot asynchronously.
#
# Inherits from RobotLab::Job — Turbo Stream wiring, thread persistence,
# and completion/error broadcasting are all handled by the base class.
#
# Pass robot_class: at enqueue time to select which robot to run.
#
# @example Enqueue from a controller
#   RobotRunJob.perform_later(
#     robot_class: "ChatRobot",
#     message:     params[:message],
#     thread_id:   session_id
#   )
#
class RobotRunJob < RobotLab::Job
  queue_as :default
end
