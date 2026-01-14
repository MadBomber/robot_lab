# frozen_string_literal: true

module RobotLab
  # Stores the result of a single robot execution
  #
  # RobotResult captures the LLM output, tool call results, and metadata
  # from running an robot. Results are stored in State for conversation
  # history and can be serialized for persistence.
  #
  # @example
  #   result = RobotResult.new(
  #     robot_name: "helper",
  #     output: [TextMessage.new(role: :assistant, content: "Hello!")],
  #     tool_calls: []
  #   )
  #   result.checksum  # => "a1b2c3d4..."
  #
  class RobotResult
    attr_reader :robot_name, :output, :tool_calls, :created_at, :id, :stop_reason
    attr_accessor :prompt, :history, :raw

    def initialize(
      robot_name:,
      output:,
      tool_calls: [],
      created_at: nil,
      id: nil,
      prompt: nil,
      history: nil,
      raw: nil,
      stop_reason: nil
    )
      @robot_name = robot_name
      @output = normalize_messages(output)
      @tool_calls = normalize_tool_results(tool_calls)
      @created_at = created_at || Time.now
      @id = id || SecureRandom.uuid
      @prompt = prompt
      @history = history
      @raw = raw
      @stop_reason = stop_reason
    end

    # Generate a checksum for deduplication
    #
    # Uses SHA256 hash of output + tool_calls + timestamp
    # Useful for detecting duplicate results in persistence
    #
    # @return [String] Hex digest of the result content
    #
    def checksum
      content = {
        output: output.map(&:to_h),
        tool_calls: tool_calls.map(&:to_h),
        created_at: created_at.to_i
      }
      Digest::SHA256.hexdigest(content.to_json)
    end

    # Export result for serialization/persistence
    #
    # Excludes debug fields (prompt, history, raw) by default
    #
    # @return [Hash] Serializable result data
    #
    def export
      {
        robot_name: robot_name,
        output: output.map(&:to_h),
        tool_calls: tool_calls.map(&:to_h),
        created_at: created_at.iso8601,
        id: id,
        checksum: checksum,
        stop_reason: stop_reason
      }.compact
    end

    def to_h
      export.merge(
        prompt: prompt&.map(&:to_h),
        history: history&.map(&:to_h),
        raw: raw
      ).compact
    end

    def to_json(*args)
      export.to_json(*args)
    end

    # Get the last text content from output
    #
    # @return [String, nil] The content of the last text message
    #
    def last_text_content
      output.reverse.find(&:text?)&.content
    end

    # Check if result contains tool calls
    #
    # @return [Boolean]
    #
    def has_tool_calls?
      output.any?(&:tool_call?) || tool_calls.any?
    end

    # Check if execution stopped naturally (not due to tool call)
    #
    # @return [Boolean]
    #
    def stopped?
      last_output = output.last
      last_output&.stopped? || (!has_tool_calls? && last_output&.stop_reason.nil?)
    end

    # Reconstruct result from hash (e.g., from persistence)
    #
    # @param hash [Hash] Serialized result data
    # @return [RobotResult]
    #
    def self.from_hash(hash)
      hash = hash.transform_keys(&:to_sym)

      new(
        robot_name: hash[:robot_name],
        output: (hash[:output] || []).map { |m| Message.from_hash(m) },
        tool_calls: (hash[:tool_calls] || []).map { |m| Message.from_hash(m) },
        created_at: hash[:created_at] ? Time.parse(hash[:created_at].to_s) : nil,
        id: hash[:id],
        prompt: hash[:prompt]&.map { |m| Message.from_hash(m) },
        history: hash[:history]&.map { |m| Message.from_hash(m) },
        raw: hash[:raw],
        stop_reason: hash[:stop_reason]
      )
    end

    private

    def normalize_messages(messages)
      Array(messages).map do |msg|
        case msg
        when Message
          msg
        when Hash
          Message.from_hash(msg)
        else
          raise ArgumentError, "Invalid message: must be Message or Hash"
        end
      end
    end

    def normalize_tool_results(results)
      Array(results).map do |result|
        case result
        when ToolResultMessage
          result
        when Hash
          result[:type] == "tool_result" ? ToolResultMessage.new(**result.slice(:tool, :content, :stop_reason)) : Message.from_hash(result)
        else
          raise ArgumentError, "Invalid tool result: must be ToolResultMessage or Hash"
        end
      end
    end
  end
end
