# frozen_string_literal: true

module RobotLab
  # A promise-like object returned by robot.delegate(async: true).
  #
  # The delegated task runs in a background thread. The caller can check
  # whether the result is ready with +resolved?+ and block until it arrives
  # with +value+ (or its alias +wait+).
  #
  # @example Fan-out to two specialists in parallel
  #   f1 = manager.delegate(to: summarizer, task: "summarize ...", async: true)
  #   f2 = manager.delegate(to: analyst,    task: "analyze ...",   async: true)
  #
  #   # Other work here while both run in parallel
  #
  #   summary  = f1.value           # blocks if not yet done
  #   analysis = f2.value
  #
  # @example With a timeout
  #   result = future.value(timeout: 10)   # raises DelegationTimeout if too slow
  #
  class DelegationFuture
    # Raised when +value(timeout: N)+ expires before the result arrives.
    class DelegationTimeout < Error; end

    # @return [String] name of the robot that was delegated to
    attr_reader :robot_name

    # @return [String] name of the robot that created this future
    attr_reader :delegated_by

    # @param robot_name [String]
    # @param delegated_by [String]
    def initialize(robot_name:, delegated_by:)
      @robot_name   = robot_name
      @delegated_by = delegated_by
      @mutex        = Mutex.new
      @cv           = ConditionVariable.new
      @result       = nil
      @error        = nil
      @resolved     = false
    end

    # True once the delegated task has completed (successfully or with an error).
    #
    # @return [Boolean]
    def resolved?
      @mutex.synchronize { @resolved }
    end

    # Block until the result is available and return it.
    #
    # @param timeout [Numeric, nil] maximum seconds to wait; nil means wait forever
    # @return [RobotResult]
    # @raise [DelegationTimeout] if +timeout+ is given and expires
    # @raise [StandardError] re-raises any error thrown by the delegated task
    def value(timeout: nil)
      @mutex.synchronize do
        unless @resolved
          @cv.wait(@mutex, timeout)
        end

        unless @resolved
          raise DelegationTimeout,
                "Delegation to '#{@robot_name}' timed out after #{timeout}s"
        end

        raise @error if @error

        @result
      end
    end
    alias_method :wait, :value

    # @api private — called by Robot#delegate from the worker thread
    def resolve!(result)
      @mutex.synchronize do
        @result   = result
        @resolved = true
        @cv.broadcast
      end
    end

    # @api private — called by Robot#delegate from the worker thread on error
    def reject!(error)
      @mutex.synchronize do
        @error    = error
        @resolved = true
        @cv.broadcast
      end
    end
  end
end
