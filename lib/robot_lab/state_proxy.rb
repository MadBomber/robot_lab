# frozen_string_literal: true

module RobotLab
  # Proxy wrapper for state data that tracks mutations
  #
  # StateProxy wraps a hash and intercepts read/write operations,
  # providing a clean interface for state access while enabling
  # optional change tracking.
  #
  # @example
  #   data = { count: 0, name: "test" }
  #   proxy = StateProxy.new(data)
  #   proxy[:count] = 1
  #   proxy.count       # => 1
  #   proxy[:name]      # => "test"
  #   proxy.to_h        # => { count: 1, name: "test" }
  #
  class StateProxy
    # Creates a new StateProxy.
    #
    # @param data [Hash] the initial data
    # @param on_change [Proc, nil] callback invoked when a value changes
    def initialize(data = {}, on_change: nil)
      @data = data.transform_keys(&:to_sym)
      @on_change = on_change
    end

    # Get value by key
    #
    # @param key [Symbol, String]
    # @return [Object]
    #
    def [](key)
      @data[key.to_sym]
    end

    # Set value by key
    #
    # @param key [Symbol, String]
    # @param value [Object]
    #
    def []=(key, value)
      key = key.to_sym
      old_value = @data[key]
      @data[key] = value
      @on_change&.call(key, old_value, value) if old_value != value
      value
    end

    # Check if key exists
    #
    # @param key [Symbol, String]
    # @return [Boolean]
    #
    def key?(key)
      @data.key?(key.to_sym)
    end
    # @!method has_key?(key)
    #   Alias for {#key?}.
    alias has_key? key?

    # @!method include?(key)
    #   Alias for {#key?}.
    alias include? key?

    # Get all keys
    #
    # @return [Array<Symbol>]
    #
    def keys
      @data.keys
    end

    # Get all values
    #
    # @return [Array]
    #
    def values
      @data.values
    end

    # Iterate over key-value pairs
    #
    # @yield [Symbol, Object]
    #
    def each(&block)
      @data.each(&block)
    end

    # Delete a key
    #
    # @param key [Symbol, String]
    # @return [Object] The deleted value
    #
    def delete(key)
      @data.delete(key.to_sym)
    end

    # Merge in additional data
    #
    # @param other [Hash]
    # @return [self]
    #
    def merge!(other)
      other.each { |k, v| self[k] = v }
      self
    end

    # Convert to plain hash
    #
    # @return [Hash]
    #
    def to_h
      @data.dup
    end
    alias to_hash to_h

    # Deep duplicate
    #
    # @return [StateProxy]
    #
    def dup
      StateProxy.new(deep_dup(@data), on_change: @on_change)
    end

    # Check if empty
    #
    # @return [Boolean]
    #
    def empty?
      @data.empty?
    end

    # Number of keys
    #
    # @return [Integer]
    #
    def size
      @data.size
    end
    alias length size

    # Respond to method calls as hash access
    #
    def respond_to_missing?(method_name, include_private = false)
      key = method_name.to_s.chomp("=").to_sym
      @data.key?(key) || super
    end

    # Allow method-style access to keys
    #
    # @example
    #   proxy.name        # Same as proxy[:name]
    #   proxy.name = "x"  # Same as proxy[:name] = "x"
    #
    def method_missing(method_name, *args, &block)
      method_str = method_name.to_s

      if method_str.end_with?("=")
        # Setter
        key = method_str.chomp("=").to_sym
        self[key] = args.first
      elsif @data.key?(method_name.to_sym)
        # Getter
        self[method_name]
      else
        super
      end
    end

    def inspect
      "#<RobotLab::StateProxy #{@data.inspect}>"
    end

    private

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
