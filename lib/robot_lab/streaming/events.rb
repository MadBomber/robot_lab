# frozen_string_literal: true

module RobotLab
  module Streaming
    # Event type definitions for streaming
    #
    # Defines the structure and types of events emitted during
    # robot and network execution.
    #
    module Events
      # Run lifecycle events
      RUN_STARTED = "run.started"
      RUN_COMPLETED = "run.completed"
      RUN_FAILED = "run.failed"
      RUN_INTERRUPTED = "run.interrupted"

      # Step events (for durable execution)
      STEP_STARTED = "step.started"
      STEP_COMPLETED = "step.completed"
      STEP_FAILED = "step.failed"

      # Part events (message composition)
      PART_CREATED = "part.created"
      PART_COMPLETED = "part.completed"
      PART_FAILED = "part.failed"

      # Content delta events (token streaming)
      TEXT_DELTA = "text.delta"
      TOOL_CALL_ARGUMENTS_DELTA = "tool_call.arguments.delta"
      TOOL_CALL_OUTPUT_DELTA = "tool_call.output.delta"
      REASONING_DELTA = "reasoning.delta"
      DATA_DELTA = "data.delta"

      # Human-in-the-loop events
      HITL_REQUESTED = "hitl.requested"
      HITL_RESOLVED = "hitl.resolved"

      # Metadata events
      USAGE_UPDATED = "usage.updated"
      METADATA_UPDATED = "metadata.updated"

      # Terminal event
      STREAM_ENDED = "stream.ended"

      # All event types
      ALL_EVENTS = [
        RUN_STARTED, RUN_COMPLETED, RUN_FAILED, RUN_INTERRUPTED,
        STEP_STARTED, STEP_COMPLETED, STEP_FAILED,
        PART_CREATED, PART_COMPLETED, PART_FAILED,
        TEXT_DELTA, TOOL_CALL_ARGUMENTS_DELTA, TOOL_CALL_OUTPUT_DELTA,
        REASONING_DELTA, DATA_DELTA,
        HITL_REQUESTED, HITL_RESOLVED,
        USAGE_UPDATED, METADATA_UPDATED,
        STREAM_ENDED
      ].freeze

      # Lifecycle events
      LIFECYCLE_EVENTS = [
        RUN_STARTED, RUN_COMPLETED, RUN_FAILED, RUN_INTERRUPTED
      ].freeze

      # Delta events (content streaming)
      DELTA_EVENTS = [
        TEXT_DELTA, TOOL_CALL_ARGUMENTS_DELTA, TOOL_CALL_OUTPUT_DELTA,
        REASONING_DELTA, DATA_DELTA
      ].freeze

      class << self
        def lifecycle?(event)
          LIFECYCLE_EVENTS.include?(event)
        end

        def delta?(event)
          DELTA_EVENTS.include?(event)
        end

        def valid?(event)
          ALL_EVENTS.include?(event)
        end
      end
    end
  end
end
