# frozen_string_literal: true

module RobotLab
  # Thread-safe waiter for blocking get operations on Memory
  #
  # Waiter provides a condition variable wrapper that allows one thread
  # to wait for a value that will be provided by another thread.
  #
  # @example Basic usage
  #   waiter = Waiter.new
  #
  #   # In thread A (waiting)
  #   value = waiter.wait(timeout: 30)
  #
  #   # In thread B (signaling)
  #   waiter.signal("the value")
  #
  # @api private
  class Waiter
    # Creates a new Waiter instance.
    def initialize
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @value = nil
      @signaled = false
    end

    # Wait for a value to be signaled.
    #
    # @param timeout [Numeric, nil] maximum seconds to wait (nil = indefinite)
    # @return [Object, :timeout] the signaled value, or :timeout if timed out
    #
    def wait(timeout: nil)
      @mutex.synchronize do
        return @value if @signaled

        if timeout
          deadline = Time.now + timeout
          until @signaled
            remaining = deadline - Time.now
            return :timeout if remaining <= 0
            @condition.wait(@mutex, remaining)
          end
          @value
        else
          @condition.wait(@mutex) until @signaled
          @value
        end
      end
    end

    # Signal a value to waiting threads.
    #
    # @param value [Object] the value to signal
    # @return [void]
    #
    def signal(value)
      @mutex.synchronize do
        @value = value
        @signaled = true
        @condition.broadcast
      end
    end

    # Check if this waiter has been signaled.
    #
    # @return [Boolean]
    #
    def signaled?
      @mutex.synchronize { @signaled }
    end
  end
end
