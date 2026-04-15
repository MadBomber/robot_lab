# frozen_string_literal: true

module RobotLab
  # Carrier for work crossing a Ractor boundary.
  #
  # All fields must be Ractor-shareable (frozen Data, frozen String,
  # frozen Hash, or a RactorQueue). Build with RactorBoundary.freeze_deep
  # on the payload before constructing.
  #
  # @example
  #   job = RactorJob.new(
  #     id:          SecureRandom.uuid.freeze,
  #     type:        :tool,
  #     payload:     RactorBoundary.freeze_deep({ tool_class: "MyTool", args: { x: 1 } }),
  #     reply_queue: RactorQueue.new(capacity: 1)
  #   )
  RactorJob = Data.define(:id, :type, :payload, :reply_queue)

  # Frozen error representation for exceptions raised inside a Ractor worker.
  # Serialized at the Ractor boundary and re-raised on the thread side.
  #
  # @example
  #   err = RactorJobError.new(message: e.message.freeze, backtrace: e.backtrace.freeze)
  RactorJobError = Data.define(:message, :backtrace)

  # Carries everything needed to reconstruct a Robot inside a Ractor.
  # All fields must be frozen strings, symbols, or hashes.
  #
  # @example
  #   spec = RobotSpec.new(
  #     name:          "analyst",
  #     template:      :analyst,
  #     system_prompt: nil,
  #     config_hash:   { model: "claude-sonnet-4" }.freeze
  #   )
  RobotSpec = Data.define(:name, :template, :system_prompt, :config_hash)
end
