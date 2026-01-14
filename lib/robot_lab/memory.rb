# frozen_string_literal: true

module RobotLab
  # Shared memory for robots within a network
  #
  # Memory provides a key-value store that robots can use to share
  # information during network execution. It supports both shared
  # memory (accessible by all robots) and namespaced memory (scoped
  # to individual robots).
  #
  # @example Basic usage
  #   memory = Memory.new
  #   memory.remember(:user_name, "Alice")
  #   memory.recall(:user_name)  # => "Alice"
  #
  # @example Namespaced memory
  #   memory.remember(:finding, "User prefers email", namespace: "classifier")
  #   memory.recall(:finding, namespace: "classifier")  # => "User prefers email"
  #   memory.recall(:finding)  # => nil (not in shared namespace)
  #
  # @example Listing memories
  #   memory.all  # => { user_name: { value: "Alice", ... } }
  #   memory.all(namespace: "classifier")  # => { finding: { value: "...", ... } }
  #
  class Memory
    SHARED_NAMESPACE = :shared

    def initialize
      @store = { SHARED_NAMESPACE => {} }
      @mutex = Mutex.new
    end

    # Store a value in memory
    #
    # @param key [Symbol, String] Memory key
    # @param value [Object] Value to store
    # @param namespace [Symbol, String, nil] Optional namespace (defaults to shared)
    # @param metadata [Hash] Additional metadata to store with the value
    # @return [Object] The stored value
    #
    def remember(key, value, namespace: nil, **metadata)
      ns = normalize_namespace(namespace)
      key = key.to_sym

      @mutex.synchronize do
        @store[ns] ||= {}
        @store[ns][key] = {
          value: value,
          stored_at: Time.now,
          updated_at: Time.now,
          access_count: 0,
          **metadata
        }
      end

      value
    end
    alias []= remember

    # Retrieve a value from memory
    #
    # @param key [Symbol, String] Memory key
    # @param namespace [Symbol, String, nil] Optional namespace (defaults to shared)
    # @param default [Object] Default value if key not found
    # @return [Object, nil] The stored value or default
    #
    def recall(key, namespace: nil, default: nil)
      ns = normalize_namespace(namespace)
      key = key.to_sym

      @mutex.synchronize do
        entry = @store.dig(ns, key)
        return default unless entry

        entry[:access_count] += 1
        entry[:last_accessed_at] = Time.now
        entry[:value]
      end
    end
    alias [] recall

    # Check if a key exists in memory
    #
    # @param key [Symbol, String] Memory key
    # @param namespace [Symbol, String, nil] Optional namespace
    # @return [Boolean]
    #
    def exists?(key, namespace: nil)
      ns = normalize_namespace(namespace)
      key = key.to_sym

      @mutex.synchronize do
        @store.dig(ns, key) != nil
      end
    end
    alias has? exists?

    # Remove a value from memory
    #
    # @param key [Symbol, String] Memory key
    # @param namespace [Symbol, String, nil] Optional namespace
    # @return [Object, nil] The removed value
    #
    def forget(key, namespace: nil)
      ns = normalize_namespace(namespace)
      key = key.to_sym

      @mutex.synchronize do
        entry = @store[ns]&.delete(key)
        entry&.dig(:value)
      end
    end

    # Get all memories in a namespace
    #
    # @param namespace [Symbol, String, nil] Optional namespace (defaults to shared)
    # @return [Hash] All memories in the namespace
    #
    def all(namespace: nil)
      ns = normalize_namespace(namespace)

      @mutex.synchronize do
        (@store[ns] || {}).dup
      end
    end

    # Get all namespaces
    #
    # @return [Array<Symbol>] List of namespace names
    #
    def namespaces
      @mutex.synchronize do
        @store.keys
      end
    end

    # Clear all memories in a namespace
    #
    # @param namespace [Symbol, String, nil] Namespace to clear (nil clears shared)
    # @return [self]
    #
    def clear(namespace: nil)
      ns = normalize_namespace(namespace)

      @mutex.synchronize do
        @store[ns] = {}
      end

      self
    end

    # Clear all memories in all namespaces
    #
    # @return [self]
    #
    def clear_all
      @mutex.synchronize do
        @store = { SHARED_NAMESPACE => {} }
      end

      self
    end

    # Search memories by value pattern
    #
    # @param pattern [Regexp, String] Pattern to match against values
    # @param namespace [Symbol, String, nil] Optional namespace to search
    # @return [Hash] Matching memories with their keys
    #
    def search(pattern, namespace: nil)
      ns = normalize_namespace(namespace)
      pattern = Regexp.new(pattern.to_s, Regexp::IGNORECASE) unless pattern.is_a?(Regexp)

      @mutex.synchronize do
        (@store[ns] || {}).select do |_key, entry|
          value = entry[:value]
          value.to_s.match?(pattern)
        end
      end
    end

    # Get memory statistics
    #
    # @return [Hash] Statistics about memory usage
    #
    def stats
      @mutex.synchronize do
        total_entries = @store.values.sum { |ns| ns.size }
        namespaces_count = @store.size

        {
          total_entries: total_entries,
          namespaces: namespaces_count,
          shared_entries: @store[SHARED_NAMESPACE]&.size || 0,
          by_namespace: @store.transform_values(&:size)
        }
      end
    end

    # Export memory to hash for serialization
    #
    # @return [Hash]
    #
    def to_h
      @mutex.synchronize do
        @store.transform_values do |namespace_data|
          namespace_data.transform_values do |entry|
            {
              value: entry[:value],
              stored_at: entry[:stored_at]&.iso8601,
              updated_at: entry[:updated_at]&.iso8601,
              last_accessed_at: entry[:last_accessed_at]&.iso8601,
              access_count: entry[:access_count]
            }.compact
          end
        end
      end
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    # Import memory from hash
    #
    # @param hash [Hash] Previously exported memory
    # @return [self]
    #
    def self.from_hash(hash)
      memory = new
      hash.each do |namespace, entries|
        entries.each do |key, entry|
          entry = entry.transform_keys(&:to_sym)
          memory.remember(
            key,
            entry[:value],
            namespace: namespace,
            stored_at: entry[:stored_at] ? Time.parse(entry[:stored_at]) : Time.now,
            access_count: entry[:access_count] || 0
          )
        end
      end
      memory
    end

    # Create a scoped memory accessor for a specific namespace
    #
    # @param namespace [Symbol, String] The namespace to scope to
    # @return [ScopedMemory] A scoped accessor
    #
    def scoped(namespace)
      ScopedMemory.new(self, namespace)
    end

    private

    def normalize_namespace(namespace)
      return SHARED_NAMESPACE if namespace.nil?

      namespace.to_sym
    end
  end

  # Scoped memory accessor for a specific namespace
  #
  # Provides convenient access to a specific namespace without
  # having to pass the namespace parameter every time.
  #
  # @example
  #   robot_memory = memory.scoped(:billing_robot)
  #   robot_memory.remember(:customer_id, "12345")
  #   robot_memory.recall(:customer_id)  # => "12345"
  #
  class ScopedMemory
    def initialize(memory, namespace)
      @memory = memory
      @namespace = namespace.to_sym
    end

    def remember(key, value, **metadata)
      @memory.remember(key, value, namespace: @namespace, **metadata)
    end
    alias []= remember

    def recall(key, default: nil)
      @memory.recall(key, namespace: @namespace, default: default)
    end
    alias [] recall

    def exists?(key)
      @memory.exists?(key, namespace: @namespace)
    end
    alias has? exists?

    def forget(key)
      @memory.forget(key, namespace: @namespace)
    end

    def all
      @memory.all(namespace: @namespace)
    end

    def clear
      @memory.clear(namespace: @namespace)
    end

    def search(pattern)
      @memory.search(pattern, namespace: @namespace)
    end

    # Access shared memory from scoped context
    #
    # @return [ScopedMemory] Accessor for shared namespace
    #
    def shared
      @memory.scoped(Memory::SHARED_NAMESPACE)
    end

    def to_h
      all
    end
  end
end
