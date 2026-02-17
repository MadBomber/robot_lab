# frozen_string_literal: true

module RobotLab
  # Shared utility methods used across multiple classes.
  #
  # Include this module to get `dispatch_async` and `deep_dup`
  # as private instance methods.
  module Utils
    private

    # Dispatch a block asynchronously using Async fibers.
    #
    # When already inside an Async reactor, creates a child task.
    # Otherwise, creates a temporary reactor that runs the block
    # and cleans up automatically.
    def dispatch_async(&block)
      Async { block.call }
    end

    # Deep-duplicate a nested Hash/Array structure.
    #
    # @param obj [Object] the object to duplicate
    # @return [Object] the deep copy
    def deep_dup(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_dup(v) }
      when Array
        obj.map { |v| deep_dup(v) }
      else
        obj.dup rescue obj
      end
    end
  end
end
