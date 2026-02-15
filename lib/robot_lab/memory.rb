# frozen_string_literal: true

require "ruby_llm/semantic_cache"

module RobotLab
  # Raised when a blocking get times out
  class AwaitTimeout < Error; end

  # Unified memory system for Robot and Network execution
  #
  # Memory is a reactive key-value store backed by Redis (if available) or an
  # internal Hash object. It provides persistent storage for runtime data,
  # conversation history, and arbitrary user-defined values.
  #
  # == Reactive Features
  #
  # Memory supports pub/sub semantics where robots can subscribe to key changes
  # and optionally block until values become available:
  #
  # - `set(key, value)` - Write a value and notify subscribers asynchronously
  # - `get(key, wait: true)` - Read a value, blocking until it exists if needed
  # - `subscribe(*keys)` - Register a callback for key changes
  #
  # Reserved keys with special accessors:
  # - :data       - runtime data (StateProxy for method-style access)
  # - :results    - accumulated robot results
  # - :messages   - conversation history
  # - :session_id - conversation session identifier for history persistence
  # - :cache      - semantic cache instance (RubyLLM::SemanticCache)
  #
  # @example Basic usage
  #   memory = Memory.new
  #   memory.set(:user_id, 123)
  #   memory.get(:user_id)  # => 123
  #
  # @example Blocking read
  #   # In robot A (writer)
  #   memory.set(:sentiment, { score: 0.8 })
  #
  #   # In robot B (reader, may run concurrently)
  #   result = memory.get(:sentiment, wait: true)   # Blocks until available
  #   result = memory.get(:sentiment, wait: 30)     # Blocks up to 30 seconds
  #
  # @example Multiple keys
  #   results = memory.get(:sentiment, :entities, :keywords, wait: 60)
  #   # => { sentiment: {...}, entities: [...], keywords: [...] }
  #
  # @example Subscriptions (async callbacks)
  #   memory.subscribe(:raw_data) do |change|
  #     puts "#{change.key} changed by #{change.writer}"
  #     enriched = enrich(change.value)
  #     memory.set(:enriched, enriched)
  #   end
  #
  # @example Using reserved keys
  #   memory.data[:category] = "billing"
  #   memory.data.category  # => "billing"
  #   memory.results  # => []
  #   memory.cache  # => RubyLLM::SemanticCache instance
  #
  class Memory
    # Reserved keys that have special behavior
    RESERVED_KEYS = %i[data results messages session_id cache].freeze

    # @!attribute [r] network_name
    #   @return [String, nil] the network this memory belongs to
    # @!attribute [rw] current_writer
    #   @return [String, nil] the name of the robot currently writing
    attr_reader :network_name
    attr_accessor :current_writer

    # Creates a new Memory instance.
    #
    # @param data [Hash] initial runtime data
    # @param results [Array<RobotResult>] pre-loaded robot results
    # @param messages [Array<Message, Hash>] pre-loaded conversation messages
    # @param session_id [String, nil] conversation session identifier
    # @param backend [Symbol] storage backend (:auto, :redis, :hash)
    # @param enable_cache [Boolean] whether to enable semantic caching (default: true)
    # @param network_name [String, nil] the network this memory belongs to
    #
    # @example Basic memory with caching enabled
    #   Memory.new(data: { category: nil, resolved: false })
    #
    # @example Memory with caching disabled
    #   Memory.new(enable_cache: false)
    #
    # @example Network-owned memory
    #   Memory.new(network_name: "support_pipeline")
    def initialize(data: {}, results: [], messages: [], session_id: nil, backend: :auto, enable_cache: true, network_name: nil)
      @backend = select_backend(backend)
      @mutex = Mutex.new
      @enable_cache = enable_cache
      @network_name = network_name
      @current_writer = nil

      # Initialize reserved keys
      set_internal(:data, data.is_a?(Hash) ? data.transform_keys(&:to_sym) : data)
      set_internal(:results, Array(results))
      set_internal(:messages, Array(messages).map { |m| normalize_message(m) })
      set_internal(:session_id, session_id)
      set_internal(:cache, @enable_cache ? RubyLLM::SemanticCache : nil)

      # Data proxy for method-style access
      @data_proxy = nil

      # Reactive infrastructure
      @subscriptions = Hash.new { |h, k| h[k] = [] }
      @pattern_subscriptions = []
      @waiters = Hash.new { |h, k| h[k] = [] }
      @subscription_mutex = Mutex.new
      @waiter_mutex = Mutex.new
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
    # For non-reserved keys, this delegates to {#set} which provides
    # reactive notifications. For reserved keys, it bypasses notifications.
    #
    # @param key [Symbol, String] the key to set
    # @param value [Object] the value to store
    # @return [Object] the stored value
    #
    # @see #set
    #
    def []=(key, value)
      key = key.to_sym

      # Reserved keys have special handling (no notifications)
      case key
      when :data
        @data_proxy = nil  # Reset proxy
        set_internal(:data, value.is_a?(Hash) ? value.transform_keys(&:to_sym) : value)
      when :results
        set_internal(:results, Array(value))
      when :messages
        set_internal(:messages, Array(value).map { |m| normalize_message(m) })
      when :session_id
        set_internal(:session_id, value)
      when :cache
        # Cache is read-only after initialization
        raise ArgumentError, "Cannot reassign cache - it is initialized automatically"
      else
        # Non-reserved keys use reactive set
        set(key, value)
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

    # Get session identifier
    #
    # @return [String, nil]
    #
    def session_id
      get_internal(:session_id)
    end

    # Set session identifier
    #
    # @param id [String, nil]
    # @return [self]
    #
    def session_id=(id)
      set_internal(:session_id, id)
      self
    end

    # Get the semantic cache module
    #
    # The cache is always active and provides semantic similarity matching
    # for LLM responses, reducing costs and latency by returning cached
    # responses for semantically equivalent queries.
    #
    # @example Using the cache with fetch
    #   response = memory.cache.fetch("What is Ruby?") do
    #     RubyLLM.chat.ask("What is Ruby?")
    #   end
    #
    # @example Wrapping a chat instance
    #   chat = memory.cache.wrap(RubyLLM.chat(model: "gpt-4"))
    #   chat.ask("What is Ruby?")  # Cached on semantic similarity
    #
    # @return [RubyLLM::SemanticCache] the semantic cache module
    #
    def cache
      get_internal(:cache)
    end

    # =========================================================================
    # Reactive Memory API
    # =========================================================================

    # Set a value and notify subscribers asynchronously.
    #
    # This is the primary write method for reactive memory. It stores the value,
    # wakes any threads waiting for this key, and asynchronously notifies
    # subscribers.
    #
    # @param key [Symbol, String] the key to set
    # @param value [Object] the value to store
    # @return [Object] the stored value
    #
    # @example Basic set
    #   memory.set(:sentiment, { score: 0.8, confidence: 0.95 })
    #
    # @example Set triggers notifications
    #   memory.subscribe(:status) { |change| puts "Status: #{change.value}" }
    #   memory.set(:status, "complete")  # Subscriber callback fires async
    #
    def set(key, value)
      key = key.to_sym
      old_value = nil

      # Store the value
      @mutex.synchronize do
        old_value = @backend[key]
        @backend[key] = value
      end

      # Wake any threads waiting for this key (synchronous - they need the value)
      wake_waiters(key, value)

      # Notify subscribers asynchronously
      notify_subscribers_async(key, value, old_value)

      value
    end

    # Get one or more values, optionally waiting until they exist.
    #
    # @param keys [Array<Symbol, String>] one or more keys to retrieve
    # @param wait [Boolean, Numeric] wait behavior:
    #   - `false` (default): return immediately, nil if missing
    #   - `true`: block indefinitely until value(s) exist
    #   - `Numeric`: block up to that many seconds, raise AwaitTimeout if exceeded
    # @return [Object, Hash] single value for one key, hash for multiple keys
    # @raise [AwaitTimeout] if timeout expires before value is available
    #
    # @example Immediate read
    #   memory.get(:sentiment)  # => value or nil
    #
    # @example Blocking read
    #   memory.get(:sentiment, wait: true)  # Blocks until available
    #
    # @example Blocking with timeout
    #   memory.get(:sentiment, wait: 30)  # Blocks up to 30 seconds
    #
    # @example Multiple keys
    #   memory.get(:sentiment, :entities, :keywords, wait: 60)
    #   # => { sentiment: {...}, entities: [...], keywords: [...] }
    #
    def get(*keys, wait: false)
      keys = keys.flatten.map(&:to_sym)

      if keys.one?
        get_single(keys.first, wait: wait)
      else
        get_multiple(keys, wait: wait)
      end
    end

    # Subscribe to changes on one or more keys.
    #
    # The callback is invoked asynchronously whenever a subscribed key changes.
    # The callback receives a MemoryChange object with details about the change.
    #
    # @param keys [Array<Symbol, String>] keys to subscribe to
    # @yield [MemoryChange] callback invoked when a subscribed key changes
    # @return [Object] subscription identifier (for unsubscribe)
    #
    # @example Subscribe to a single key
    #   memory.subscribe(:raw_data) do |change|
    #     puts "#{change.key} changed from #{change.previous} to #{change.value}"
    #     puts "Written by: #{change.writer}"
    #   end
    #
    # @example Subscribe to multiple keys
    #   memory.subscribe(:sentiment, :entities) do |change|
    #     update_dashboard(change.key, change.value)
    #   end
    #
    def subscribe(*keys, &block)
      raise ArgumentError, "Block required for subscribe" unless block_given?

      keys = keys.flatten.map(&:to_sym)
      subscription_id = generate_subscription_id

      @subscription_mutex.synchronize do
        keys.each do |key|
          @subscriptions[key] << { id: subscription_id, callback: block }
        end
      end

      subscription_id
    end

    # Subscribe to keys matching a pattern.
    #
    # Pattern uses glob-style matching:
    # - `*` matches any characters
    # - `?` matches a single character
    #
    # @param pattern [String] glob pattern to match keys
    # @yield [MemoryChange] callback invoked when a matching key changes
    # @return [Object] subscription identifier (for unsubscribe)
    #
    # @example Subscribe to namespace
    #   memory.subscribe_pattern("analysis:*") do |change|
    #     puts "Analysis key #{change.key} updated"
    #   end
    #
    def subscribe_pattern(pattern, &block)
      raise ArgumentError, "Block required for subscribe_pattern" unless block_given?

      subscription_id = generate_subscription_id
      regex = pattern_to_regex(pattern)

      @subscription_mutex.synchronize do
        @pattern_subscriptions << { id: subscription_id, pattern: regex, callback: block }
      end

      subscription_id
    end

    # Remove a subscription.
    #
    # @param subscription_id [Object] the subscription identifier from subscribe
    # @return [Boolean] true if subscription was found and removed
    #
    def unsubscribe(subscription_id)
      removed = false

      @subscription_mutex.synchronize do
        @subscriptions.each_value do |subs|
          removed = true if subs.reject! { |s| s[:id] == subscription_id }
        end

        removed = true if @pattern_subscriptions.reject! { |s| s[:id] == subscription_id }
      end

      removed
    end

    # Remove all subscriptions for specific keys.
    #
    # @param keys [Array<Symbol, String>] keys to unsubscribe from
    # @return [self]
    #
    def unsubscribe_keys(*keys)
      keys = keys.flatten.map(&:to_sym)

      @subscription_mutex.synchronize do
        keys.each { |key| @subscriptions.delete(key) }
      end

      self
    end

    # Check if there are any subscribers for a key.
    #
    # @param key [Symbol, String] the key to check
    # @return [Boolean]
    #
    def subscribed?(key)
      key = key.to_sym

      @subscription_mutex.synchronize do
        return true if @subscriptions[key].any?

        @pattern_subscriptions.any? { |s| s[:pattern].match?(key.to_s) }
      end
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
      cached = get_internal(:cache)  # Preserve cache instance
      @mutex.synchronize do
        @backend.clear
        @backend[:data] = {}
        @backend[:results] = []
        @backend[:messages] = []
        @backend[:session_id] = nil
        @backend[:cache] = cached  # Restore cache instance
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
    # The semantic cache setting and network name are preserved in clones.
    # Subscriptions are NOT cloned - the new memory starts with fresh subscriptions.
    #
    # @return [Memory]
    #
    def clone
      cloned = Memory.new(
        data: deep_dup(data.to_h),
        results: results.dup,
        messages: messages.dup,
        session_id: session_id,
        backend: @backend.is_a?(Hash) ? :hash : :auto,
        enable_cache: @enable_cache,
        network_name: @network_name
      )
      # Copy non-reserved keys (without triggering notifications)
      keys.each { |k| cloned.send(:set_internal, k, deep_dup(get_internal(k))) }
      cloned
    end
    alias dup clone

    # Export memory to hash for serialization
    #
    # Note: The cache is not serialized as it is recreated on initialization.
    #
    # @return [Hash]
    #
    def to_h
      {
        data: data.to_h,
        results: results.map(&:export),
        messages: messages.map(&:to_h),
        session_id: session_id,
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
    # A new semantic cache instance is created automatically.
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
        session_id: hash[:session_id]
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

    def create_semantic_cache
      RubyLLM::SemanticCache
    end

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
      redis_config = RobotLab.config.respond_to?(:redis) ? RobotLab.config.redis : nil
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

    # =========================================================================
    # Reactive Memory Helpers
    # =========================================================================

    def get_single(key, wait:)
      # Try immediate read
      value = @mutex.synchronize { @backend[key] }
      return value unless value.nil? && wait

      # Need to wait
      timeout = wait == true ? nil : wait
      wait_for_key(key, timeout: timeout)
    end

    def get_multiple(keys, wait:)
      results = {}
      missing = []

      @mutex.synchronize do
        keys.each do |key|
          if @backend.key?(key)
            results[key] = @backend[key]
          else
            missing << key
          end
        end
      end

      return results if missing.empty? || !wait

      # Wait for missing keys
      timeout = wait == true ? nil : wait
      missing.each do |key|
        results[key] = wait_for_key(key, timeout: timeout)
      end

      results
    end

    def wait_for_key(key, timeout:)
      waiter = Waiter.new

      @waiter_mutex.synchronize do
        # Double-check - value might have arrived while setting up
        value = @mutex.synchronize { @backend[key] }
        return value unless value.nil?

        @waiters[key] << waiter
      end

      result = waiter.wait(timeout: timeout)

      if result == :timeout
        # Clean up the waiter
        @waiter_mutex.synchronize { @waiters[key].delete(waiter) }
        raise AwaitTimeout, "Timeout waiting for :#{key} after #{timeout} seconds"
      end

      result
    end

    def wake_waiters(key, value)
      waiters = @waiter_mutex.synchronize { @waiters.delete(key) || [] }
      waiters.each { |w| w.signal(value) }
    end

    def notify_subscribers_async(key, value, old_value)
      # Collect all matching subscribers
      callbacks = []

      @subscription_mutex.synchronize do
        # Exact key matches
        callbacks.concat(@subscriptions[key].map { |s| s[:callback] })

        # Pattern matches
        key_str = key.to_s
        @pattern_subscriptions.each do |sub|
          callbacks << sub[:callback] if sub[:pattern].match?(key_str)
        end
      end

      return if callbacks.empty?

      # Build the change object
      change = MemoryChange.new(
        key: key,
        value: value,
        previous: old_value,
        writer: @current_writer,
        network_name: @network_name,
        timestamp: Time.now
      )

      # Dispatch callbacks asynchronously
      callbacks.each do |callback|
        dispatch_async { callback.call(change) }
      end
    end

    def dispatch_async(&block)
      # Use Async if available (preferred for fiber-based concurrency)
      if defined?(Async) && Async::Task.current?
        Async { block.call }
      else
        # Fall back to Thread for basic async dispatch
        Thread.new do
          block.call
        rescue StandardError => e
          # Log but don't crash the notification system
          warn "Memory subscription callback error: #{e.message}"
        end
      end
    end

    def generate_subscription_id
      SecureRandom.uuid
    end

    def pattern_to_regex(pattern)
      # Convert glob pattern to regex
      regex_str = pattern
        .gsub(".", "\\.")
        .gsub("*", ".*")
        .gsub("?", ".")

      Regexp.new("\\A#{regex_str}\\z")
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
      redis_config = RobotLab.config.respond_to?(:redis) ? RobotLab.config.redis : nil

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
