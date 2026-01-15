# frozen_string_literal: true

module RobotLab
  # Base class for all message types in RobotLab
  #
  # Messages represent the communication between users, assistants, and tools
  # in a conversation. This mirrors the TypeScript Message union type.
  #
  # @abstract Subclass and implement specific message types
  #
  class Message
    # Valid message types
    VALID_TYPES = %w[text tool_call tool_result].freeze
    # Valid message roles
    VALID_ROLES = %w[system user assistant tool_result].freeze
    # Valid stop reasons
    VALID_STOP_REASONS = %w[tool stop].freeze

    # @!attribute [r] type
    #   @return [String] the message type (text, tool_call, or tool_result)
    # @!attribute [r] role
    #   @return [String] the message role (system, user, assistant, or tool_result)
    # @!attribute [r] content
    #   @return [String, Hash, nil] the message content
    # @!attribute [r] stop_reason
    #   @return [String, nil] the stop reason (tool or stop)
    attr_reader :type, :role, :content, :stop_reason

    # Creates a new Message instance.
    #
    # @param type [String, Symbol] the message type
    # @param role [String, Symbol] the message role
    # @param content [String, Hash, nil] the message content
    # @param stop_reason [String, Symbol, nil] the stop reason
    # @raise [ArgumentError] if type, role, or stop_reason is invalid
    def initialize(type:, role:, content:, stop_reason: nil)
      validate_type!(type)
      validate_role!(role)
      validate_stop_reason!(stop_reason) if stop_reason

      @type = type.to_s
      @role = role.to_s
      @content = content
      @stop_reason = stop_reason&.to_s
    end

    # @return [Boolean] true if this is a text message
    def text? = type == "text"
    # @return [Boolean] true if this is a tool call message
    def tool_call? = type == "tool_call"
    # @return [Boolean] true if this is a tool result message
    def tool_result? = type == "tool_result"

    # @return [Boolean] true if this is a system message
    def system? = role == "system"
    # @return [Boolean] true if this is a user message
    def user? = role == "user"
    # @return [Boolean] true if this is an assistant message
    def assistant? = role == "assistant"

    # @return [Boolean] true if the conversation stopped naturally
    def stopped? = stop_reason == "stop"
    # @return [Boolean] true if the conversation stopped for a tool call
    def tool_stop? = stop_reason == "tool"

    # Converts the message to a hash representation.
    #
    # @return [Hash] a hash containing the message data
    def to_h
      {
        type: type,
        role: role,
        content: content,
        stop_reason: stop_reason
      }.compact
    end

    # Converts the message to JSON.
    #
    # @param args [Array] arguments passed to to_json
    # @return [String] JSON representation of the message
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Creates a Message instance from a hash.
    #
    # Automatically determines the appropriate subclass based on the type.
    #
    # @param hash [Hash] the hash representation of a message
    # @return [Message] the appropriate Message subclass instance
    def self.from_hash(hash)
      hash = hash.transform_keys(&:to_sym)

      case hash[:type]&.to_s
      when "text"
        TextMessage.new(**hash.slice(:role, :content, :stop_reason))
      when "tool_call"
        ToolCallMessage.new(
          role: hash[:role],
          tools: hash[:tools],
          stop_reason: hash[:stop_reason]
        )
      when "tool_result"
        ToolResultMessage.new(
          tool: hash[:tool],
          content: hash[:content],
          stop_reason: hash[:stop_reason]
        )
      else
        new(**hash)
      end
    end

    private

    def validate_type!(type)
      return if VALID_TYPES.include?(type.to_s)

      raise ArgumentError, "Invalid message type: #{type}. Must be one of: #{VALID_TYPES.join(', ')}"
    end

    def validate_role!(role)
      return if VALID_ROLES.include?(role.to_s)

      raise ArgumentError, "Invalid role: #{role}. Must be one of: #{VALID_ROLES.join(', ')}"
    end

    def validate_stop_reason!(stop_reason)
      return if VALID_STOP_REASONS.include?(stop_reason.to_s)

      raise ArgumentError, "Invalid stop_reason: #{stop_reason}. Must be one of: #{VALID_STOP_REASONS.join(', ')}"
    end
  end

  # Text message from system, user, or assistant
  #
  # @example System message
  #   TextMessage.new(role: :system, content: "You are a helpful assistant")
  #
  # @example User message
  #   TextMessage.new(role: :user, content: "Hello!")
  #
  # @example Assistant response
  #   TextMessage.new(role: :assistant, content: "Hi there!", stop_reason: :stop)
  #
  class TextMessage < Message
    # Creates a new TextMessage instance.
    #
    # @param role [String, Symbol] the message role (system, user, or assistant)
    # @param content [String] the text content
    # @param stop_reason [String, Symbol, nil] the stop reason
    def initialize(role:, content:, stop_reason: nil)
      super(type: "text", role: role, content: content, stop_reason: stop_reason)
    end
  end

  # Represents a tool/function definition for tool calls
  #
  # @example
  #   ToolMessage.new(
  #     id: "call_123",
  #     name: "get_weather",
  #     input: { location: "Berlin" }
  #   )
  #
  class ToolMessage
    # @!attribute [r] id
    #   @return [String] the unique identifier for this tool call
    # @!attribute [r] name
    #   @return [String] the name of the tool being called
    # @!attribute [r] input
    #   @return [Hash] the input arguments for the tool
    attr_reader :id, :name, :input

    # Creates a new ToolMessage instance.
    #
    # @param id [String] the unique identifier for this tool call
    # @param name [String] the name of the tool
    # @param input [Hash, nil] the input arguments
    def initialize(id:, name:, input:)
      @id = id
      @name = name
      @input = input || {}
    end

    # Converts the tool message to a hash representation.
    #
    # @return [Hash] a hash containing the tool call data
    def to_h
      {
        type: "tool",
        id: id,
        name: name,
        input: input
      }
    end

    # Converts the tool message to JSON.
    #
    # @param args [Array] arguments passed to to_json
    # @return [String] JSON representation
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Creates a ToolMessage from a hash.
    #
    # @param hash [Hash] the hash representation
    # @return [ToolMessage]
    def self.from_hash(hash)
      hash = hash.transform_keys(&:to_sym)
      new(
        id: hash[:id],
        name: hash[:name],
        input: hash[:input] || hash[:arguments] || {}
      )
    end
  end

  # Message containing one or more tool calls from the assistant
  #
  # @example
  #   ToolCallMessage.new(
  #     role: :assistant,
  #     tools: [
  #       ToolMessage.new(id: "call_1", name: "get_weather", input: { location: "Berlin" })
  #     ]
  #   )
  #
  class ToolCallMessage < Message
    # @!attribute [r] tools
    #   @return [Array<ToolMessage>] the tool calls in this message
    attr_reader :tools

    # Creates a new ToolCallMessage instance.
    #
    # @param role [String, Symbol] the message role (usually assistant)
    # @param tools [Array<ToolMessage, Hash>] the tool calls
    # @param stop_reason [String, Symbol, nil] the stop reason (defaults to "tool")
    def initialize(role:, tools:, stop_reason: nil)
      @tools = normalize_tools(tools)
      super(type: "tool_call", role: role, content: nil, stop_reason: stop_reason || "tool")
    end

    # Converts the tool call message to a hash representation.
    #
    # @return [Hash] a hash containing the tool call data
    def to_h
      {
        type: type,
        role: role,
        tools: tools.map(&:to_h),
        stop_reason: stop_reason
      }
    end

    private

    def normalize_tools(tools)
      tools.map do |tool|
        case tool
        when ToolMessage
          tool
        when Hash
          ToolMessage.from_hash(tool)
        else
          raise ArgumentError, "Invalid tool: must be ToolMessage or Hash"
        end
      end
    end
  end

  # Result from executing a tool
  #
  # @example Successful result
  #   ToolResultMessage.new(
  #     tool: ToolMessage.new(id: "call_1", name: "get_weather", input: { location: "Berlin" }),
  #     content: { data: { temperature: 15, unit: "celsius" } }
  #   )
  #
  # @example Error result
  #   ToolResultMessage.new(
  #     tool: ToolMessage.new(id: "call_1", name: "get_weather", input: {}),
  #     content: { error: "Location is required" }
  #   )
  #
  class ToolResultMessage < Message
    # @!attribute [r] tool
    #   @return [ToolMessage] the tool call that was executed
    attr_reader :tool

    # Creates a new ToolResultMessage instance.
    #
    # @param tool [ToolMessage, Hash] the tool call that was executed
    # @param content [Hash] the result content (with :data or :error key)
    # @param stop_reason [String, Symbol, nil] the stop reason (defaults to "tool")
    def initialize(tool:, content:, stop_reason: nil)
      @tool = normalize_tool(tool)
      super(type: "tool_result", role: "tool_result", content: content, stop_reason: stop_reason || "tool")
    end

    # Checks if the tool execution was successful.
    #
    # @return [Boolean] true if content contains a :data key
    def success?
      content.is_a?(Hash) && content.key?(:data)
    end

    # Checks if the tool execution resulted in an error.
    #
    # @return [Boolean] true if content contains an :error key
    def error?
      content.is_a?(Hash) && content.key?(:error)
    end

    # Returns the result data if successful.
    #
    # @return [Object, nil] the result data, or nil if not successful
    def data
      content[:data] if success?
    end

    # Returns the error message if there was an error.
    #
    # @return [String, nil] the error message, or nil if no error
    def error
      content[:error] if error?
    end

    # Converts the tool result message to a hash representation.
    #
    # @return [Hash] a hash containing the tool result data
    def to_h
      {
        type: type,
        role: role,
        tool: tool.to_h,
        content: content,
        stop_reason: stop_reason
      }
    end

    private

    def normalize_tool(tool)
      case tool
      when ToolMessage
        tool
      when Hash
        ToolMessage.from_hash(tool)
      else
        raise ArgumentError, "Invalid tool: must be ToolMessage or Hash"
      end
    end
  end
end
