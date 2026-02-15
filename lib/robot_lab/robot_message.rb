# frozen_string_literal: true

module RobotLab
  # Typed message envelope for bus-based robot communication.
  #
  # RobotMessage is a Data class (immutable value object) that wraps
  # content sent between robots via a TypedBus channel.
  #
  # @example Creating a new message
  #   msg = RobotMessage.build(id: 1, from: "alice", content: "Hello")
  #   msg.key       #=> "alice:1"
  #   msg.reply?    #=> false
  #
  # @example Creating a reply
  #   reply = RobotMessage.build(
  #     id: 2, from: "bob",
  #     content: "Hi back",
  #     in_reply_to: "alice:1"
  #   )
  #   reply.reply?  #=> true
  #
  RobotMessage = Data.define(:id, :from, :content, :in_reply_to) do
    # Build a RobotMessage with in_reply_to defaulting to nil.
    #
    # @param id [Integer] per-robot message counter
    # @param from [String] sender's robot name (= channel name)
    # @param content [String, Hash] message payload
    # @param in_reply_to [String, nil] composite key of the message being replied to
    # @return [RobotMessage]
    def self.build(id:, from:, content:, in_reply_to: nil)
      new(id: id, from: from, content: content, in_reply_to: in_reply_to)
    end

    # Composite identity key: "from:id"
    #
    # @return [String]
    def key = "#{from}:#{id}"

    # Whether this message is a reply to another message.
    #
    # @return [Boolean]
    def reply? = !in_reply_to.nil?
  end
end
