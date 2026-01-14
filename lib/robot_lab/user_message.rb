# frozen_string_literal: true

module RobotLab
  # Enhanced user message with metadata and system prompt augmentation
  #
  # UserMessage wraps the user's input with additional context like
  # thread ID, system prompt additions, and other metadata that can
  # influence robot behavior.
  #
  # @example Basic usage
  #   message = UserMessage.new("What is the weather?")
  #   message.content  # => "What is the weather?"
  #
  # @example With metadata
  #   message = UserMessage.new(
  #     "What is the weather?",
  #     thread_id: "thread_123",
  #     system_prompt: "Respond in Spanish",
  #     metadata: { user_id: "user_456" }
  #   )
  #
  class UserMessage
    attr_reader :content, :thread_id, :system_prompt, :metadata, :id, :created_at

    def initialize(content, thread_id: nil, system_prompt: nil, metadata: nil, id: nil)
      @content = content.to_s
      @thread_id = thread_id
      @system_prompt = system_prompt
      @metadata = metadata || {}
      @id = id || SecureRandom.uuid
      @created_at = Time.now
    end

    # Convert to a simple text message for the conversation
    #
    # @return [TextMessage]
    #
    def to_message
      RobotLab::TextMessage.new(role: "user", content: content)
    end

    # Get the string content (for compatibility with String inputs)
    #
    # @return [String]
    #
    def to_s
      content
    end

    def to_h
      {
        content: content,
        thread_id: thread_id,
        system_prompt: system_prompt,
        metadata: metadata,
        id: id,
        created_at: created_at.iso8601
      }.compact
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    # Create from string or hash
    #
    # @param input [String, Hash, UserMessage] Input to normalize
    # @return [UserMessage]
    #
    def self.from(input)
      case input
      when UserMessage
        input
      when String
        new(input)
      when Hash
        input = input.transform_keys(&:to_sym)
        new(
          input[:content],
          thread_id: input[:thread_id],
          system_prompt: input[:system_prompt],
          metadata: input[:metadata],
          id: input[:id]
        )
      when TextMessage
        new(input.content)
      else
        new(input.to_s)
      end
    end
  end
end
