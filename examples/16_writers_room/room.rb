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
  attr_reader :bus, :memory, :writers, :display, :config, :logger, :mode

  def initialize(display:, mode:, config: nil, log_path: nil)
    @bus     = TypedBus::MessageBus.new
    @memory  = RobotLab::Memory.new(enable_cache: false)
    @display = display
    @mode    = mode
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

  # Ordered list of expected unit numbers for the current mode.
  # Fixed modes return unit_range.to_a; dynamic modes parse the
  # registry key from memory (comma-separated integers).
  def expected_units
    if @mode[:unit_range] == :dynamic
      registry = @memory.get(@mode[:registry_key])
      return [] unless registry

      registry.to_s.split(",").map { |s| s.strip.to_i }.sort
    else
      @mode[:unit_range].to_a
    end
  end

  # Wait for the work to be marked complete.
  # Sends periodic heartbeat messages to :room so the feedback loop
  # doesn't starve — writers only act when messages arrive.
  def wait_for_completion(timeout: 600, poll_interval: 3, heartbeat_interval: 45)
    deadline = Time.now + timeout
    last_heartbeat = Time.now
    done_key  = @mode[:completion_key]
    unit_name = @mode[:unit_name]
    @logger.info("Waiting for completion (timeout: #{timeout}s, heartbeat: #{heartbeat_interval}s)")

    loop do
      if @memory.key?(done_key)
        @logger.info("Work marked complete!")
        return true
      end

      if Time.now > deadline
        @logger.warn("Timeout reached (#{timeout}s) — work not completed")
        units   = expected_units
        written = units.select { |n| @memory.key?(:"#{unit_name}_#{n}") }
        @logger.warn("#{unit_name.capitalize}s in memory: #{written.join(', ')}")
        @logger.warn("Memory keys: #{@memory.keys.join(', ')}")
        @display.info("Timeout reached (#{timeout}s) — work not completed.")
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

  # Assemble the finished output from memory
  def assemble_output
    unit_name   = @mode[:unit_name]
    bible_key   = @mode[:bible_key]
    outline_key = @mode[:outline_key]
    units_list  = expected_units

    @logger.info("Assembling #{@mode[:name]} from memory (#{units_list.size} #{unit_name}s)")
    units = units_list.map do |n|
      key = :"#{unit_name}_#{n}"
      content = @memory.get(key)
      if content
        @logger.info("  #{unit_name}_#{n}: #{content.to_s.length} chars")
        "## #{unit_name.capitalize} #{n}\n\n#{content}"
      else
        @logger.warn("  #{unit_name}_#{n}: MISSING")
        "## #{unit_name.capitalize} #{n}\n\n[Not written]"
      end
    end

    outline = @memory.get(outline_key)
    bible   = @memory.get(bible_key)

    parts = []
    parts << "# #{bible_key.to_s.tr('_', ' ').split.map(&:capitalize).join(' ')}\n\n#{bible}\n" if bible
    parts << "# #{outline_key.to_s.tr('_', ' ').split.map(&:capitalize).join(' ')}\n\n#{outline}\n" if outline
    parts << "---\n"
    parts.concat(units)

    parts.join("\n\n")
  end

  private

  # Build and send a progress status message to :room
  def send_heartbeat
    unit_name   = @mode[:unit_name]
    bible_key   = @mode[:bible_key]
    outline_key = @mode[:outline_key]
    units_list  = expected_units
    total       = units_list.size

    written     = units_list.select { |n| @memory.key?(:"#{unit_name}_#{n}") }
    missing     = units_list.reject { |n| @memory.key?(:"#{unit_name}_#{n}") }
    has_bible   = @memory.key?(bible_key)
    has_outline = @memory.key?(outline_key)

    if total.zero?
      status = "[ROOM STATUS] No #{unit_name}s registered yet."
      status += " Establish a #{@mode[:registry_key]} first." if @mode[:unit_range] == :dynamic
    else
      status = "[ROOM STATUS] Progress: #{written.size}/#{total} #{unit_name}s written."
      status += " Written: #{written.join(', ')}." if written.any?
      status += " Still needed: #{missing.join(', ')}." if missing.any?
      unclaimed = missing.size
      status += " Spawn more writers if #{unclaimed} unclaimed #{unit_name}s exceed active writers." if unclaimed > @writers.size
    end
    status += " #{bible_key.to_s.tr('_', ' ').capitalize}: #{has_bible ? 'yes' : 'NOT YET'}."
    status += " #{outline_key.to_s.tr('_', ' ').capitalize}: #{has_outline ? 'yes' : 'NOT YET'}."
    status += " Check shared memory, claim an unclaimed #{unit_name}, and write it."

    @logger.info("Heartbeat -> :room (#{written.size}/#{total} #{unit_name}s)")
    @display.info(status)

    # Pick a random writer to deliver the heartbeat through
    sender = @writers.values.sample
    sender.send_message(to: :room, content: status)
  end
end
