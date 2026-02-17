# frozen_string_literal: true

# ── Writers' Room Tools ──────────────────────────────────────
#
# General-purpose tools that give each writer agency over
# communication, shared memory, and team composition.
# No workflow logic — the LLMs decide when and how to use them.

# Helper to access the room logger from any tool
module ToolLogging
  private

  def log
    robot.room&.logger
  end
end


class BroadcastTool < RobotLab::Tool
  include ToolLogging

  description "Send a message to all writers in the room. " \
              "Use for discussion, proposals, questions, or announcements. " \
              "Don't broadcast trivially — only when you have something substantive."

  param :message, type: "string",
        desc: "What to say to the room", required: true

  def execute(message:)
    log&.info("#{robot.name} TOOL broadcast (#{message.length} chars)")
    robot.send_message(to: :room, content: message)
    robot.display&.broadcast(robot.name, message)
    "Broadcast sent."
  end
end


class DirectMessageTool < RobotLab::Tool
  include ToolLogging

  description "Send a private message to one specific writer. " \
              "Use for feedback on their chapter, coordination on handoffs, " \
              "or questions that don't concern the whole room."

  param :to, type: "string",
        desc: "Name of the writer to message", required: true
  param :message, type: "string",
        desc: "What to say", required: true

  def execute(to:, message:)
    log&.info("#{robot.name} TOOL direct_message -> #{to} (#{message.length} chars)")
    robot.send_message(to: to.to_sym, content: message)
    robot.display&.direct_message(robot.name, to, message)
    "Message sent to #{to}."
  end
end


class ReadMemoryTool < RobotLab::Tool
  include ToolLogging

  description "Read a value from shared memory. " \
              "Use to check the story bible, outline, chapter claims, " \
              "or read another writer's chapter draft."

  param :key, type: "string",
        desc: "Memory key to read (e.g. story_bible, outline, claims, chapter_3)", required: true

  def execute(key:)
    value = robot.shared_memory.get(key.to_sym)
    if value.nil?
      log&.info("#{robot.name} TOOL read_memory :#{key} -> nil")
      "Key '#{key}' is not set yet."
    else
      log&.info("#{robot.name} TOOL read_memory :#{key} -> #{value.to_s.length} chars")
      value.to_s
    end
  end
end


class WriteMemoryTool < RobotLab::Tool
  include ToolLogging

  description "Write a value to shared memory for all writers to see. " \
              "Use to store the story bible, outline, claim a chapter, " \
              "or submit a finished chapter draft."

  param :key, type: "string",
        desc: "Memory key (e.g. story_bible, outline, claims, chapter_1)", required: true
  param :value, type: "string",
        desc: "Content to store", required: true

  def execute(key:, value:)
    log&.info("#{robot.name} TOOL write_memory :#{key} (#{value.length} chars)")
    robot.shared_memory.set(key.to_sym, value)
    robot.display&.memory_write(robot.name, key)
    "Stored '#{key}' in shared memory."
  end
end


class ListMemoryTool < RobotLab::Tool
  include ToolLogging

  description "List all keys currently in shared memory. " \
              "Use to get situational awareness of what's been done."

  def execute
    keys = robot.shared_memory.keys
    log&.info("#{robot.name} TOOL list_memory -> #{keys.join(', ')}")
    if keys.empty?
      "Shared memory is empty."
    else
      "Keys in shared memory: #{keys.join(', ')}"
    end
  end
end


class SpawnWriterTool < RobotLab::Tool
  include ToolLogging

  description "Bring a new writer into the room to help with the workload. " \
              "Use when there are more unclaimed chapters than active writers."

  param :name, type: "string",
        desc: "Name for the new writer (e.g. writer_4)", required: true

  def execute(name:)
    log&.info("#{robot.name} TOOL spawn_writer '#{name}'")
    new_writer = robot.room.spawn_writer(name)
    robot.display&.spawn(robot.name, name)
    "#{name} has joined the writers' room."
  rescue => e
    log&.error("#{robot.name} TOOL spawn_writer '#{name}' FAILED: #{e.message}")
    "Failed to spawn #{name}: #{e.message}"
  end
end


class MarkCompleteTool < RobotLab::Tool
  include ToolLogging

  description "Signal that the book is finished — all 10 chapters are written. " \
              "Only use this when you have verified all chapters exist in shared memory."

  def execute
    # Verify all chapters exist
    missing = (1..10).reject { |n| robot.shared_memory.key?(:"chapter_#{n}") }

    if missing.any?
      log&.warn("#{robot.name} TOOL mark_complete REJECTED — missing chapters: #{missing.join(', ')}")
      "Cannot mark complete. Missing chapters: #{missing.join(', ')}"
    else
      log&.info("#{robot.name} TOOL mark_complete SUCCESS")
      robot.shared_memory.set(:book_complete, true)
      robot.display&.complete(robot.name)
      "Book marked as complete!"
    end
  end
end
