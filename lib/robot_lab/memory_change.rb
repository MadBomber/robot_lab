# frozen_string_literal: true

module RobotLab
  # Represents a change to a Memory key
  #
  # MemoryChange is passed to subscription callbacks when a key's value changes.
  # It provides context about what changed, who changed it, and when.
  #
  # @example Subscription callback
  #   memory.subscribe(:sentiment) do |change|
  #     puts "Key #{change.key} changed from #{change.previous} to #{change.value}"
  #     puts "Written by: #{change.writer} at #{change.timestamp}"
  #   end
  #
  # @note This class is designed to be compatible with SmartMessage::Base.
  #   When smart_message is added as a dependency, this class can inherit
  #   from SmartMessage::Base for distributed pub/sub support.
  #
  class MemoryChange
    # @!attribute [r] key
    #   @return [Symbol] the memory key that changed
    # @!attribute [r] value
    #   @return [Object] the new value
    # @!attribute [r] previous
    #   @return [Object, nil] the previous value (nil if key was created)
    # @!attribute [r] writer
    #   @return [String, nil] name of the robot that wrote the value
    # @!attribute [r] network_name
    #   @return [String, nil] name of the network
    # @!attribute [r] timestamp
    #   @return [Time] when the change occurred
    # @!attribute [r] correlation_id
    #   @return [String, nil] optional correlation ID for tracing
    attr_reader :key, :value, :previous, :writer, :network_name, :timestamp, :correlation_id

    # Creates a new MemoryChange instance.
    #
    # @param key [Symbol, String] the memory key that changed
    # @param value [Object] the new value
    # @param previous [Object, nil] the previous value
    # @param writer [String, nil] name of the robot that wrote the value
    # @param network_name [String, nil] name of the network
    # @param timestamp [Time] when the change occurred (defaults to now)
    # @param correlation_id [String, nil] optional correlation ID
    #
    def initialize(key:, value:, previous: nil, writer: nil, network_name: nil, timestamp: nil, correlation_id: nil)
      @key = key.to_sym
      @value = value
      @previous = previous
      @writer = writer
      @network_name = network_name
      @timestamp = timestamp || Time.now
      @correlation_id = correlation_id
    end

    # Check if this is a new key (no previous value).
    #
    # @return [Boolean]
    #
    def created?
      @previous.nil? && !@value.nil?
    end

    # Check if this is an update to an existing key.
    #
    # @return [Boolean]
    #
    def updated?
      !@previous.nil? && !@value.nil?
    end

    # Check if the key was deleted.
    #
    # @return [Boolean]
    #
    def deleted?
      @value.nil? && !@previous.nil?
    end

    # Convert to hash representation.
    #
    # @return [Hash]
    #
    def to_h
      {
        key: @key,
        value: @value,
        previous: @previous,
        writer: @writer,
        network_name: @network_name,
        timestamp: @timestamp.iso8601,
        correlation_id: @correlation_id
      }.compact
    end

    # Convert to JSON.
    #
    # @param args [Array] arguments passed to to_json
    # @return [String]
    #
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Reconstruct from hash.
    #
    # @param hash [Hash] the hash representation
    # @return [MemoryChange]
    #
    def self.from_hash(hash)
      hash = hash.transform_keys(&:to_sym)
      new(
        key: hash[:key],
        value: hash[:value],
        previous: hash[:previous],
        writer: hash[:writer],
        network_name: hash[:network_name],
        timestamp: hash[:timestamp] ? Time.parse(hash[:timestamp]) : nil,
        correlation_id: hash[:correlation_id]
      )
    end
  end
end
