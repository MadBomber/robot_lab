# frozen_string_literal: true

module RobotLab
  # Thread-safe waiter for blocking get operations on Memory.
  #
  # Uses an IO.pipe pair instead of ConditionVariable so that
  # IO.select integrates with the Async fiber scheduler hook.
  # ConditionVariable#wait can block the event loop in Async
  # contexts; IO.select yields to the scheduler correctly.
  #
  # Multiple threads may wait on the same Waiter instance.
  # signal() writes one byte per waiting thread so every
  # blocked IO.select wakes exactly once.
  #
  # @api private
  class Waiter
    # Creates a new Waiter instance.
    def initialize
      @read_io, @write_io = IO.pipe
      @mutex        = Mutex.new
      @value        = nil
      @signaled     = false
      @waiter_count = 0
    end

    # Wait for a value to be signaled.
    #
    # @param timeout [Numeric, nil] maximum seconds to wait (nil = indefinite)
    # @return [Object, :timeout] the signaled value, or :timeout if timed out
    #
    def wait(timeout: nil)
      @mutex.synchronize do
        return @value if @signaled

        @waiter_count += 1
      end

      begin
        ready = @read_io.wait_readable(timeout)

        @mutex.synchronize do
          @waiter_count -= 1
          return :timeout unless ready

          @read_io.read_nonblock(1) rescue nil  # drain one wake byte
          @value
        end
      rescue IOError
        @mutex.synchronize { @waiter_count -= 1 }
        :timeout
      end
    end

    # Signal a value to all waiting threads.
    #
    # @param value [Object] the value to signal
    # @return [void]
    #
    def signal(value)
      count = @mutex.synchronize do
        @value    = value
        @signaled = true
        @waiter_count
      end

      # Write one byte per waiting thread (min 1 to handle the race
      # where a thread passed the @signaled check but hasn't entered
      # IO.select yet — its IO.select will return immediately).
      bytes = [count, 1].max
      @write_io.write_nonblock("." * bytes) rescue nil
    rescue IOError
      # pipe already closed — signal is a no-op
    end

    # Check if this waiter has been signaled.
    #
    # @return [Boolean]
    #
    def signaled?
      @mutex.synchronize { @signaled }
    end

    # Release the pipe file descriptors.
    # Should be called after wait returns.
    #
    # @return [void]
    #
    def close
      @read_io.close  rescue nil
      @write_io.close rescue nil
    end
  end
end
