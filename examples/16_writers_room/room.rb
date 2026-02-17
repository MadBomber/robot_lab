# frozen_string_literal: true

require "logger"

# ── The Room ─────────────────────────────────────────────────
#
# Holds the bus, shared memory, and writer roster. Provides
# spawn_writer so any writer's SpawnWriterTool can add new
# members at runtime. That's the only "management" — the rest
# is up to the group.
#
class Room
  attr_reader :bus, :memory, :writers, :display, :config, :logger

  def initialize(display:, config: nil, log_path: nil)
    @bus     = TypedBus::MessageBus.new
    @memory  = RobotLab::Memory.new(enable_cache: false)
    @display = display
    @config  = config
    @writers = {}

    # Structured logger — always writes to output/room.log
    log_file = log_path || File.join(__dir__, "output", "room.log")
    @logger = Logger.new(log_file, progname: "room")
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%H:%M:%S.%L')} [#{severity}] #{msg}\n"
    end
    @logger.info("Room initialized")

    # Shared broadcast channel
    @bus.add_channel(:room, type: RobotLab::RobotMessage)
    @logger.info("Bus channel :room created")
  end

  # Add an initial writer to the room
  def add_writer(name)
    @logger.info("Adding writer '#{name}'")
    writer = Writer.new(
      name:          name,
      bus:           @bus,
      shared_memory: @memory,
      display:       @display,
      room:          self,
      config:        @config
    )
    @writers[name] = writer
    @logger.info("Writer '#{name}' ready (tools: #{writer.local_tools.map(&:name).join(', ')})")
    writer
  end

  # Called by SpawnWriterTool — any writer can recruit
  def spawn_writer(name)
    raise "Writer '#{name}' already exists" if @writers.key?(name)

    @logger.info("Spawning writer '#{name}' (requested at runtime)")
    add_writer(name)
  end

  # Seed the room with the assignment
  def seed(assignment)
    first = @writers.values.first
    @logger.info("Seeding room via '#{first.name}' (#{assignment.length} chars)")
    first.send_message(to: :room, content: assignment)
    @logger.info("Seed message published to :room")
  end

  # Wait for the book to be marked complete.
  # Sends periodic heartbeat messages to :room so the feedback loop
  # doesn't starve — writers only act when messages arrive.
  def wait_for_completion(timeout: 600, poll_interval: 3, heartbeat_interval: 45)
    deadline = Time.now + timeout
    last_heartbeat = Time.now
    @logger.info("Waiting for completion (timeout: #{timeout}s, heartbeat: #{heartbeat_interval}s)")

    loop do
      if @memory.key?(:book_complete)
        @logger.info("Book marked complete!")
        return true
      end

      if Time.now > deadline
        @logger.warn("Timeout reached (#{timeout}s) — book not completed")
        chapters = (1..10).select { |n| @memory.key?(:"chapter_#{n}") }
        @logger.warn("Chapters in memory: #{chapters.join(', ')}")
        @logger.warn("Memory keys: #{@memory.keys.join(', ')}")
        @display.info("Timeout reached (#{timeout}s) — book not completed.")
        return false
      end

      # Heartbeat: nudge the room with a progress summary
      if Time.now - last_heartbeat >= heartbeat_interval
        send_heartbeat
        last_heartbeat = Time.now
      end

      sleep poll_interval
    end
  end

  # Assemble the finished book from memory
  def assemble_book
    @logger.info("Assembling book from memory")
    chapters = (1..10).map do |n|
      key = :"chapter_#{n}"
      content = @memory.get(key)
      if content
        @logger.info("  chapter_#{n}: #{content.to_s.length} chars")
        "## Chapter #{n}\n\n#{content}"
      else
        @logger.warn("  chapter_#{n}: MISSING")
        "## Chapter #{n}\n\n[Not written]"
      end
    end

    outline = @memory.get(:outline)
    bible   = @memory.get(:story_bible)

    parts = []
    parts << "# Story Bible\n\n#{bible}\n" if bible
    parts << "# Outline\n\n#{outline}\n"   if outline
    parts << "---\n"
    parts.concat(chapters)

    parts.join("\n\n")
  end

  private

  # Build and send a progress status message to :room
  def send_heartbeat
    written   = (1..10).select { |n| @memory.key?(:"chapter_#{n}") }
    missing   = (1..10).reject { |n| @memory.key?(:"chapter_#{n}") }
    has_bible = @memory.key?(:story_bible)
    has_outline = @memory.key?(:outline)

    status = "[ROOM STATUS] Progress: #{written.size}/10 chapters written."
    status += " Written: #{written.join(', ')}." if written.any?
    status += " Still needed: #{missing.join(', ')}." if missing.any?
    status += " Story bible: #{has_bible ? 'yes' : 'NOT YET'}."
    status += " Outline: #{has_outline ? 'yes' : 'NOT YET'}."
    status += " Check shared memory, claim an unclaimed chapter, and write it."

    @logger.info("Heartbeat -> :room (#{written.size}/10 chapters)")
    @display.info(status)

    # Pick a random writer to deliver the heartbeat through
    sender = @writers.values.sample
    sender.send_message(to: :room, content: status)
  end
end
