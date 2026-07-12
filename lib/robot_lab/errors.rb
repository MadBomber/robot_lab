# frozen_string_literal: true

module RobotLab
  # Classification surface for "should this error be retried?" — so hosts
  # (ActiveJob retry_on lists, robot_lab-to's takeover loop, custom retry
  # wrappers) don't reimplement the same case statement against RobotLab's
  # error hierarchy.
  #
  # - +InferenceError+ (transient LLM/API failures) is always retryable,
  #   except its more specific subclass +ToolLoopError+ (a circuit breaker
  #   tripped by a repeating tool-call pattern — retrying immediately would
  #   just re-trigger the same loop).
  # - +MCPError+ and +ToolError+ are opt-in: retryable only when raised
  #   with +retryable: true+, since some instances are transient (a
  #   connection drop, a timeout) and some are not (an explicit rejection
  #   from the server or tool).
  # - Everything else (+ConfigurationError+, +ToolNotFoundError+,
  #   +DependencyError+, +RactorBoundaryError+, +BusError+, and any
  #   non-RobotLab error) is never retryable.
  module Errors
    # @param error [Exception, nil]
    # @return [Boolean] true when the host should retry the operation that raised +error+
    def self.retryable?(error)
      return false if error.nil? || error.is_a?(RobotLab::ToolLoopError)

      case error
      when RobotLab::MCPError, RobotLab::ToolError
        error.respond_to?(:retryable) && error.retryable == true
      when RobotLab::InferenceError
        true
      else
        false
      end
    end

    # Always-retryable error classes, for explicit ActiveJob-style
    # +retry_on+ allow-lists. Excludes +MCPError+/+ToolError+ because
    # their retryability is per-raise (via +retryable:+), not per-class.
    #
    # @return [Array<Class>]
    def self.retryable_classes
      [RobotLab::InferenceError].freeze
    end
  end
end
