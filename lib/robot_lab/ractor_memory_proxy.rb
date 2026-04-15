# frozen_string_literal: true

require "ractor/wrapper"

module RobotLab
  # Wraps a Memory instance via Ractor::Wrapper so Ractor workers can safely
  # read and write shared state.
  #
  # Only get, set, and keys are proxied across the Ractor boundary.
  # Subscriptions and callbacks are NOT proxied — closures are not
  # Ractor-safe. Use the thread-side Memory directly for reactive subscriptions.
  #
  # Values passed to set() must be Ractor-shareable; RactorBoundary.freeze_deep
  # is applied automatically.
  #
  # The proxy uses use_current_ractor: true so the Memory object stays in the
  # calling Ractor and is not moved. This allows direct access alongside the
  # proxy and works with Memory's mutex-based internals.
  #
  # @example
  #   memory = Memory.new
  #   proxy  = RactorMemoryProxy.new(memory)
  #
  #   # From any Ractor via the stub:
  #   proxy.set(:result, "done")
  #   proxy.get(:result)   #=> "done"
  #
  #   proxy.shutdown  # call when done
  #
  class RactorMemoryProxy
    # @param memory [Memory] the memory instance to wrap
    def initialize(memory)
      @memory  = memory
      @wrapper = Ractor::Wrapper.new(memory, use_current_ractor: true)
      @stub    = @wrapper.stub
    end

    # Returns the Ractor-shareable stub for use inside Ractors.
    #
    # The stub proxies get/set/keys to the wrapped Memory. Pass this to
    # Ractor.new rather than the proxy itself (the proxy is not shareable).
    #
    # @return [Ractor::Wrapper stub]
    def stub
      @stub
    end

    # Read a value from the proxied Memory.
    #
    # @param key [Symbol]
    # @return [Object, nil]
    def get(key)
      @stub.get(key)
    end

    # Write a frozen value to the proxied Memory.
    # The value is deep-frozen before crossing the Ractor boundary.
    #
    # @param key [Symbol]
    # @param value [Object] must be Ractor-shareable after freeze_deep
    # @return [void]
    # @raise [RactorBoundaryError] if value cannot be made shareable
    def set(key, value)
      frozen_value = RactorBoundary.freeze_deep(value)
      @stub.set(key, frozen_value)
    end

    # List all keys currently set in the proxied Memory.
    #
    # @return [Array<Symbol>]
    def keys
      @stub.keys
    end

    # Shut down the ractor-wrapper.
    #
    # @return [void]
    def shutdown
      @wrapper.async_stop
      @wrapper.join
    rescue => e
      RobotLab.config.logger.warn("RactorMemoryProxy shutdown error: #{e.message}")
    end
  end
end
