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
    VALID_TYPES = %w[text tool_call tool_result].freeze
    VALID_ROLES = %w[system user assistant tool_result].freeze
    VALID_STOP_REASONS = %w[tool stop].freeze

    attr_reader :type, :role, :content, :stop_reason

    def initialize(type:, role:, content:, stop_reason: nil)
      validate_type!(type)
      validate_role!(role)
      validate_stop_reason!(stop_reason) if stop_reason

      @type = type.to_s
      @role = role.to_s
      @content = content
      @stop_reason = stop_reason&.to_s
    end

    def text? = type == "text"
    def tool_call? = type == "tool_call"
    def tool_result? = type == "tool_result"

    def system? = role == "system"
    def user? = role == "user"
    def assistant? = role == "assistant"

    def stopped? = stop_reason == "stop"
    def tool_stop? = stop_reason == "tool"

    def to_h
      {
        type: type,
        role: role,
        content: content,
        stop_reason: stop_reason
      }.compact
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

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
    attr_reader :id, :name, :input

    def initialize(id:, name:, input:)
      @id = id
      @name = name
      @input = input || {}
    end

    def to_h
      {
        type: "tool",
        id: id,
        name: name,
        input: input
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

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
    attr_reader :tools

    def initialize(role:, tools:, stop_reason: nil)
      @tools = normalize_tools(tools)
      super(type: "tool_call", role: role, content: nil, stop_reason: stop_reason || "tool")
    end

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
    attr_reader :tool

    def initialize(tool:, content:, stop_reason: nil)
      @tool = normalize_tool(tool)
      super(type: "tool_result", role: "tool_result", content: content, stop_reason: stop_reason || "tool")
    end

    def success?
      content.is_a?(Hash) && content.key?(:data)
    end

    def error?
      content.is_a?(Hash) && content.key?(:error)
    end

    def data
      content[:data] if success?
    end

    def error
      content[:error] if error?
    end

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
