# frozen_string_literal: true

# Generic background job for executing any robot asynchronously.
#
# Inherits from RobotLab::RailsIntegration::Job — Turbo Stream wiring, thread
# persistence, and completion/error broadcasting are all handled by the base
# class. (Note the full namespace: robot_lab-rails defines the class as
# RobotLab::RailsIntegration::Job and registers no RobotLab::Job alias.)
#
# Pass robot_class: at enqueue time to select which robot to run. Any extra
# keywords are forwarded straight to robot.run — which is how `tools:` gets
# through, since run defaults to :none and would otherwise send the model an
# empty tool list.
#
# @example Enqueue from a controller
#   RobotRunJob.perform_later(
#     robot_class: "ChatRobot",
#     message:     params[:message],
#     thread_id:   session_id,
#     tools:       :inherit
#   )
#
class RobotRunJob < RobotLab::RailsIntegration::Job
  queue_as :default
end
