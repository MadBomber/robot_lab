# frozen_string_literal: true

module RobotLab
  # Shared utility methods used across multiple classes.
  #
  # Include this module to get `dispatch_async` and `deep_dup`
  # as private instance methods.
  module Utils
    private

    # Dispatch a block asynchronously using Async fibers or threads.
    #
    # Prefers Async if already inside an Async reactor; falls back
    # to a plain Thread otherwise.
    def dispatch_async(&block)
      if defined?(Async) && Async::Task.current?
        Async { block.call }
      else
        Thread.new do
          block.call
        rescue StandardError => e
          warn "RobotLab async dispatch error: #{e.message}"
        end
      end
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
