# frozen_string_literal: true

module RobotLab
  # Unified memory system for Robot and Network execution
  #
  # Memory is a key-value store backed by Redis (if available) or an internal
  # Hash object. It provides persistent storage for runtime data, conversation
  # history, and arbitrary user-defined values.
  #
  # Reserved keys with special accessors:
  # - :data      - runtime data (StateProxy for method-style access)
  # - :results   - accumulated robot results
  # - :messages  - conversation history
  # - :thread_id - conversation thread identifier
  # - :cache     - semantic cache instance (when ruby_llm-semantic_cache is available)
  #
  # @example Basic usage
  #   memory = Memory.new
  #   memory[:user_id] = 123
  #   memory[:user_id]  # => 123
  #
  # @example Using reserved keys
  #   memory.data[:category] = "billing"
  #   memory.data.category  # => "billing"
  #   memory.results  # => []
  #
  # @example Runtime injection
  #   memory.merge!(magic_word: "xyzzy", session_id: "abc123")
  #
  class Memory
    # Reserved keys that have special behavior
    RESERVED_KEYS = %i[data results messages thread_id cache].freeze

    # Creates a new Memory instance.
    #
    # @param data [Hash] initial runtime data
    # @param results [Array<RobotResult>] pre-loaded robot results
    # @param messages [Array<Message, Hash>] pre-loaded conversation messages
    # @param thread_id [String, nil] conversation thread identifier
    # @param backend [Symbol] storage backend (:auto, :redis, :hash)
    #
    # @example Basic memory
    #   Memory.new(data: { category: nil, resolved: false })
    #
    # @example Memory with pre-loaded history
    #   Memory.new(messages: [{ role: "user", content: "Hello" }])
    def initialize(data: {}, results: [], messages: [], thread_id: nil, backend: :auto)
      @backend = select_backend(backend)
      @mutex = Mutex.new

      # Initialize reserved keys
      set_internal(:data, data.is_a?(Hash) ? data.transform_keys(&:to_sym) : data)
      set_internal(:results, Array(results))
      set_internal(:messages, Array(messages).map { |m| normalize_message(m) })
      set_internal(:thread_id, thread_id)
      set_internal(:cache, nil)

      # Data proxy for method-style access
      @data_proxy = nil
    end

    # Get value by key
    #
    # @param key [Symbol, String] the key to retrieve
    # @return [Object] the stored value
    #
    def [](key)
      key = key.to_sym
      return send(key) if RESERVED_KEYS.include?(key) && key != :cache

      get_internal(key)
    end

    # Set value by key
    #
    # @param key [Symbol, String] the key to set
    # @param value [Object] the value to store
    # @return [Object] the stored value
    #
    def []=(key, value)
      key = key.to_sym

      # Reserved keys have special handling
      case key
      when :data
        @data_proxy = nil  # Reset proxy
        set_internal(:data, value.is_a?(Hash) ? value.transform_keys(&:to_sym) : value)
      when :results
        set_internal(:results, Array(value))
      when :messages
        set_internal(:messages, Array(value).map { |m| normalize_message(m) })
      when :thread_id
        set_internal(:thread_id, value)
      when :cache
        set_internal(:cache, value)
      else
        set_internal(key, value)
      end

      value
    end

    # Access runtime data through StateProxy
    #
    # @return [StateProxy] proxy for method-style data access
    #
    def data
      @data_proxy ||= StateProxy.new(get_internal(:data) || {})
    end

    # Get copy of results (immutable access)
    #
    # @return [Array<RobotResult>]
    #
    def results
      (get_internal(:results) || []).dup
    end

    # Get copy of messages (immutable access)
    #
    # @return [Array<Message>]
    #
    def messages
      (get_internal(:messages) || []).dup
    end

    # Get thread identifier
    #
    # @return [String, nil]
    #
    def thread_id
      get_internal(:thread_id)
    end

    # Set thread identifier
    #
    # @param id [String, nil]
    # @return [self]
    #
    def thread_id=(id)
      set_internal(:thread_id, id)
      self
    end

    # Get semantic cache instance
    #
    # @return [Object, nil] semantic cache or nil if not configured
    #
    def cache
      get_internal(:cache)
    end

    # Append a robot result to history
    #
    # @param result [RobotResult]
    # @return [self]
    #
    def append_result(result)
      @mutex.synchronize do
        results_array = @backend[:results] || []
        results_array << result
        @backend[:results] = results_array
      end
      self
    end

    # Set results (used when loading from persistence)
    #
    # @param results [Array<RobotResult>]
    # @return [self]
    #
    def set_results(results)
      set_internal(:results, Array(results))
      self
    end

    # Get results from a specific index (for incremental save)
    #
    # @param start_index [Integer]
    # @return [Array<RobotResult>]
    #
    def results_from(start_index)
      (get_internal(:results) || [])[start_index..] || []
    end

    # Merge additional values into memory
    #
    # @param values [Hash] key-value pairs to merge
    # @return [self]
    #
    def merge!(values)
      values.each { |k, v| self[k] = v }
      self
    end

    # Check if key exists
    #
    # @param key [Symbol, String]
    # @return [Boolean]
    #
    def key?(key)
      key = key.to_sym
      return true if RESERVED_KEYS.include?(key)

      @mutex.synchronize do
        @backend.key?(key)
      end
    end
    alias has_key? key?
    alias include? key?

    # Get all keys (excluding reserved keys)
    #
    # @return [Array<Symbol>]
    #
    def keys
      @mutex.synchronize do
        @backend.keys.map(&:to_sym) - RESERVED_KEYS
      end
    end

    # Get all keys including reserved
    #
    # @return [Array<Symbol>]
    #
    def all_keys
      @mutex.synchronize do
        @backend.keys.map(&:to_sym)
      end
    end

    # Delete a key
    #
    # @param key [Symbol, String]
    # @return [Object] the deleted value
    #
    def delete(key)
      key = key.to_sym
      raise ArgumentError, "Cannot delete reserved key: #{key}" if RESERVED_KEYS.include?(key)

      @mutex.synchronize do
        @backend.delete(key)
      end
    end

    # Clear all non-reserved keys
    #
    # @return [self]
    #
    def clear
      @mutex.synchronize do
        keys_to_delete = @backend.keys.map(&:to_sym) - RESERVED_KEYS
        keys_to_delete.each { |k| @backend.delete(k) }
      end
      self
    end

    # Reset memory to initial state
    #
    # @return [self]
    #
    def reset
      @mutex.synchronize do
        @backend.clear
        @backend[:data] = {}
        @backend[:results] = []
        @backend[:messages] = []
        @backend[:thread_id] = nil
        # Preserve cache configuration
      end
      @data_proxy = nil
      self
    end

    # Format history for robot prompts
    #
    # Combines pre-loaded messages with formatted results.
    #
    # @param formatter [Proc, nil] custom result formatter
    # @return [Array<Message>]
    #
    def format_history(formatter: nil)
      formatter ||= default_formatter
      messages + results.flat_map { |r| formatter.call(r) }
    end

    # Clone memory for isolated execution
    #
    # @param share_cache [Boolean] whether to share the cache instance
    # @return [Memory]
    #
    def clone(share_cache: true)
      Memory.new(
        data: deep_dup(data.to_h),
        results: results.dup,
        messages: messages.dup,
        thread_id: thread_id,
        backend: @backend.is_a?(Hash) ? :hash : :auto
      ).tap do |mem|
        # Copy non-reserved keys
        keys.each { |k| mem[k] = deep_dup(self[k]) }
        # Optionally share cache
        mem[:cache] = cache if share_cache && cache
      end
    end
    alias dup clone

    # Export memory to hash for serialization
    #
    # @return [Hash]
    #
    def to_h
      {
        data: data.to_h,
        results: results.map(&:export),
        messages: messages.map(&:to_h),
        thread_id: thread_id,
        custom: keys.each_with_object({}) { |k, h| h[k] = self[k] }
      }.compact
    end

    # Convert to JSON
    #
    # @param args [Array] arguments passed to to_json
    # @return [String]
    #
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Reconstruct memory from hash
    #
    # @param hash [Hash]
    # @return [Memory]
    #
    def self.from_hash(hash)
      hash = hash.transform_keys(&:to_sym)
      memory = new(
        data: hash[:data] || {},
        results: (hash[:results] || []).map { |r| RobotResult.from_hash(r) },
        messages: (hash[:messages] || []).map { |m| Message.from_hash(m) },
        thread_id: hash[:thread_id]
      )

      # Restore custom keys
      (hash[:custom] || {}).each { |k, v| memory[k] = v }

      memory
    end

    # Check if using Redis backend
    #
    # @return [Boolean]
    #
    def redis?
      @backend.is_a?(RedisBackend)
    end

    private

    def select_backend(preference)
      case preference
      when :redis
        create_redis_backend || create_hash_backend
      when :hash
        create_hash_backend
      else # :auto
        create_redis_backend || create_hash_backend
      end
    end

    def create_redis_backend
      return nil unless redis_available?

      RedisBackend.new
    rescue StandardError
      nil
    end

    def create_hash_backend
      {}
    end

    def redis_available?
      return false unless defined?(Redis)

      # Check if Redis is configured in RobotLab
      redis_config = RobotLab.configuration.respond_to?(:redis) ? RobotLab.configuration.redis : nil
      redis_config || ENV["REDIS_URL"]
    end

    def get_internal(key)
      @mutex.synchronize do
        @backend[key.to_sym]
      end
    end

    def set_internal(key, value)
      @mutex.synchronize do
        @backend[key.to_sym] = value
      end
    end

    def normalize_message(msg)
      case msg
      when Message
        msg
      when Hash
        Message.from_hash(msg)
      else
        raise ArgumentError, "Invalid message: must be Message or Hash"
      end
    end

    def default_formatter
      ->(result) { result.output + result.tool_calls }
    end

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

  # Redis backend for Memory (optional, loaded when Redis is available)
  #
  # @api private
  class RedisBackend
    def initialize
      @redis = create_redis_connection
      @namespace = "robot_lab:memory:#{SecureRandom.uuid}"
    end

    def [](key)
      value = @redis.get("#{@namespace}:#{key}")
      value ? JSON.parse(value, symbolize_names: true) : nil
    rescue JSON::ParserError
      value
    end

    def []=(key, value)
      serialized = value.is_a?(String) ? value : value.to_json
      @redis.set("#{@namespace}:#{key}", serialized)
      value
    end

    def key?(key)
      @redis.exists?("#{@namespace}:#{key}")
    end

    def keys
      @redis.keys("#{@namespace}:*").map { |k| k.sub("#{@namespace}:", "").to_sym }
    end

    def delete(key)
      value = self[key]
      @redis.del("#{@namespace}:#{key}")
      value
    end

    def clear
      keys.each { |k| delete(k) }
    end

    private

    def create_redis_connection
      redis_config = RobotLab.configuration.respond_to?(:redis) ? RobotLab.configuration.redis : nil

      if redis_config.is_a?(Hash)
        Redis.new(**redis_config)
      elsif ENV["REDIS_URL"]
        Redis.new(url: ENV["REDIS_URL"])
      else
        Redis.new
      end
    end
  end
end
