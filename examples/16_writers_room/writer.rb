# frozen_string_literal: true

# ── The Writer ─────────────────────────────────────────────────
#
# All writers in the room are instances of this same class with
# the same template and the same tools. There is no hierarchy,
# no designated leader, no pre-assigned roles. The group
# self-organizes through bus communication and shared memory.
#
# Each writer:
#   - Subscribes to :room for broadcast discussion
#   - Listens on a personal channel for direct messages
#   - Has tools to read/write shared memory, broadcast, DM,
#     spawn new writers, and mark the book complete
#   - Decides via LLM when to speak, when to write, when to
#     listen, and when to spawn
#
# == Chat Reset Strategy
#
# In a bus-based SOG, writers receive many messages and each
# triggers a run() call. When the LLM responds with only tool
# calls (no text), RubyLLM appends an empty text content block
# to the chat history. The Anthropic API rejects this on the
# next call, permanently killing the writer.
#
# Fix: reset the chat before each message. The writer doesn't
# need persistent chat history — shared memory is the single
# source of truth. Each message is processed with a fresh chat
# that has the system prompt, tools, and current memory context.
#
class Writer < RobotLab::Robot
  attr_accessor :shared_memory, :display, :room
  attr_reader :messages_processed

  def initialize(name:, bus:, shared_memory:, display:, room:, config: nil)
    @shared_memory = shared_memory
    @display = display
    @room = room
    @messages_processed = 0

    super(
      name:        name,
      template:    room.mode[:template],
      context:     { writer_name: name },
      bus:         bus,
      config:      config,
      local_tools: build_tools
    )

    setup_room_subscription
    setup_message_handler
  end

  private

  def log
    @room&.logger
  end

  def build_tools
    [
      BroadcastTool.new(robot: self),
      DirectMessageTool.new(robot: self),
      ReadMemoryTool.new(robot: self),
      WriteMemoryTool.new(robot: self),
      ListMemoryTool.new(robot: self),
      SpawnWriterTool.new(robot: self),
      MarkCompleteTool.new(robot: self),
    ]
  end

  def setup_room_subscription
    @bus.subscribe(:room) do |delivery|
      handle_incoming_delivery(delivery)
    end
  end

  # Reset the chat to a clean state with system prompt and tools.
  # Prevents history corruption from tool-only LLM responses
  # (empty text content blocks that Anthropic rejects).
  def fresh_chat!
    resolved_model = @config&.model || RobotLab.config.ruby_llm.model
    @chat = RubyLLM.chat(model: resolved_model)
    apply_template_to_chat(@build_context) if @template
    @chat.with_instructions(@system_prompt) if @system_prompt
    @chat.with_temperature(@config.temperature) if @config&.temperature

    filtered = filtered_tools([])
    @chat.with_tools(*filtered) if filtered.any?
  end

  def setup_message_handler
    on_message do |message|
      # Don't respond to your own messages
      next if message.from == name

      @messages_processed += 1
      log&.info("#{name} <- [#{message.from}] msg ##{@messages_processed} (#{message.content.to_s[0..80]}...)")
      @display&.incoming(name, message.from, message.content)

      # Fresh chat for each message — shared memory is our persistence
      fresh_chat!

      # Build prompt with current memory context
      memory_keys = shared_memory.keys
      prompt = "[#{message.from}]: #{message.content}"
      prompt += "\n\n[Memory keys: #{memory_keys.join(', ')}]" if memory_keys.any?

      log&.info("#{name} -> run() starting (prompt: #{prompt.length} chars)")

      begin
        result = run(prompt)
        reply_text = result.respond_to?(:reply) ? result.reply.to_s[0..120] : result.to_s[0..120]
        log&.info("#{name} <- run() finished (reply: #{reply_text}...)")
      rescue => e
        log&.error("#{name} !! run() raised #{e.class}: #{e.message}")
        log&.error("  #{e.backtrace&.first(5)&.join("\n  ")}")
      end
    end
  end
end
