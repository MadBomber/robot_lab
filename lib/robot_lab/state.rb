# frozen_string_literal: true

module RobotLab
  # Shared state container for robot and network execution
  #
  # State holds typed data, conversation history (results), pre-loaded
  # messages, and shared memory. It's shared across robots in a network
  # and provides history formatting for prompts.
  #
  # @example Basic usage
  #   state = State.new(data: { category: nil, resolved: false })
  #   state.data[:category] = "billing"
  #   state.data.category  # => "billing"
  #
  # @example With results
  #   state.append_result(robot_result)
  #   state.format_history  # => [Message, Message, ...]
  #
  # @example With shared memory
  #   state.memory.remember(:user_name, "Alice")
  #   state.memory.recall(:user_name)  # => "Alice"
  #
  class State
    # @!attribute [r] thread_id
    #   @return [String, nil] the thread identifier for persistence
    # @!attribute [r] memory
    #   @return [Memory] the shared memory store
    attr_reader :thread_id, :memory

    # Creates a new State instance.
    #
    # @param data [Hash] initial state data accessible via the data proxy
    # @param results [Array<RobotResult>] pre-loaded robot results
    # @param messages [Array<Message, Hash>] pre-loaded messages for conversation history
    # @param thread_id [String, nil] thread identifier for persistence
    # @param memory [Memory, nil] shared memory store (creates new if nil)
    #
    # @example Basic state
    #   State.new(data: { category: nil, resolved: false })
    #
    # @example State with pre-loaded history
    #   State.new(messages: [{ role: "user", content: "Hello" }])
    def initialize(data: {}, results: [], messages: [], thread_id: nil, memory: nil)
      @_data = data.is_a?(Hash) ? data.transform_keys(&:to_sym) : data
      @_results = Array(results)
      @_messages = Array(messages).map { |m| normalize_message(m) }
      @thread_id = thread_id
      @memory = memory || Memory.new
      @data_proxy = nil
    end

    # Access state data through proxy
    #
    # @return [StateProxy]
    #
    def data
      @data_proxy ||= StateProxy.new(@_data)
    end

    # Get copy of results (immutable access)
    #
    # @return [Array<RobotResult>]
    #
    def results
      @_results.dup
    end

    # Get copy of messages (immutable access)
    #
    # @return [Array<Message>]
    #
    def messages
      @_messages.dup
    end

    # Append an robot result to history
    #
    # @param result [RobotResult]
    # @return [self]
    #
    def append_result(result)
      @_results << result
      self
    end

    # Set results (used when loading from persistence)
    #
    # @param results [Array<RobotResult>]
    # @return [self]
    #
    def set_results(results)
      @_results = Array(results)
      self
    end

    # Get results from a specific index (for incremental save)
    #
    # @param start_index [Integer]
    # @return [Array<RobotResult>]
    #
    def results_from(start_index)
      @_results[start_index..] || []
    end

    # Set thread ID
    #
    # @param id [String]
    # @return [self]
    #
    def thread_id=(id)
      @thread_id = id
      self
    end

    # Format history for robot prompts
    #
    # Combines pre-loaded messages with formatted results.
    #
    # @param formatter [Proc, nil] Custom result formatter
    # @return [Array<Message>]
    #
    def format_history(formatter: nil)
      formatter ||= default_formatter
      @_messages + @_results.flat_map { |r| formatter.call(r) }
    end

    # Clone state for isolated execution
    #
    # Memory is shared by default across clones to allow robots
    # in a network to communicate. Pass share_memory: false to
    # create an isolated memory.
    #
    # @param share_memory [Boolean] Whether to share memory (default: true)
    # @return [State]
    #
    def clone(share_memory: true)
      State.new(
        data: deep_dup(@data_proxy&.to_h || @_data),
        results: @_results.dup,
        messages: @_messages.dup,
        thread_id: @thread_id,
        memory: share_memory ? @memory : nil
      )
    end
    # @!method dup(share_memory: true)
    #   Alias for {#clone}.
    #   @param share_memory [Boolean] whether to share memory
    #   @return [State]
    alias dup clone

    # Converts the state to a hash representation.
    #
    # @return [Hash] a hash containing all state data
    def to_h
      {
        data: data.to_h,
        results: results.map(&:export),
        messages: messages.map(&:to_h),
        thread_id: thread_id,
        memory: @memory.to_h
      }.compact
    end

    # Converts the state to JSON.
    #
    # @param args [Array] arguments passed to to_json
    # @return [String] JSON representation of the state
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Reconstruct state from hash
    #
    # @param hash [Hash]
    # @return [State]
    #
    def self.from_hash(hash)
      hash = hash.transform_keys(&:to_sym)
      new(
        data: hash[:data] || {},
        results: (hash[:results] || []).map { |r| RobotResult.from_hash(r) },
        messages: (hash[:messages] || []).map { |m| Message.from_hash(m) },
        thread_id: hash[:thread_id],
        memory: hash[:memory] ? Memory.from_hash(hash[:memory]) : nil
      )
    end

    private

    def default_formatter
      ->(result) { result.output + result.tool_calls }
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
