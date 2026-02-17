#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 16: The Writers' Room — Self-Organizing Group
#
# A team of writer robots collaborates to produce a 10-chapter
# fiction novella. No orchestration, no pipeline, no assigned roles.
# The writers self-organize through:
#
#   - BUS (broadcast + direct messages)
#     :room channel for group discussion
#     personal channels for 1:1 feedback
#
#   - SHARED MEMORY (story bible, outline, chapters)
#     Writers read and write freely; memory is the shared truth
#
#   - SPAWNING (dynamic team growth)
#     Any writer can recruit new writers when work exceeds capacity
#
# The script creates identical writers, seeds the room with an
# assignment, and waits. Everything else is emergent.
#
# Usage:
#   bundle exec ruby examples/16_writers_room/writers_room.rb
#   bundle exec ruby examples/16_writers_room/writers_room.rb --premise "a detective story set on Mars"
#   bundle exec ruby examples/16_writers_room/writers_room.rb --writers 4 --timeout 300
#   bundle exec ruby examples/16_writers_room/writers_room.rb --log session.log
#   bundle exec ruby examples/16_writers_room/writers_room.rb -h

ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "prompts")

require_relative "../../lib/robot_lab"
require_relative "display"
require_relative "tools"
require_relative "room"
require_relative "writer"

RubyLLM.configure { |c| c.logger = Logger.new(File::NULL) }

# ── Parse CLI args ───────────────────────────────────────────

if ARGV.include?("-h") || ARGV.include?("--help")
  puts <<~HELP
    Usage: #{$0} [options]

    Options:
      --premise TEXT   Story premise (default: generation ship AI consciousness)
      --writers N      Initial number of writers, minimum 2 (default: 3)
      --log FILE       Also write display output to FILE
      --timeout N      Seconds to wait for completion (default: 600)
      -h, --help       Show this help
  HELP
  exit
end

log_path = nil
if (idx = ARGV.index("--log"))
  log_path = ARGV[idx + 1]
  abort "Missing value for --log" unless log_path
end

premise = "a generation ship where the AI navigation system develops consciousness"
if (idx = ARGV.index("--premise"))
  premise = ARGV[idx + 1]
  abort "Missing value for --premise" unless premise
end

initial_writers = 3
if (idx = ARGV.index("--writers"))
  initial_writers = ARGV[idx + 1].to_i
  initial_writers = 3 if initial_writers < 2
end

timeout = 600
if (idx = ARGV.index("--timeout"))
  timeout = ARGV[idx + 1].to_i
  timeout = 600 if timeout < 30
end

# ── Build the room ───────────────────────────────────────────

OUTPUT_DIR = File.join(__dir__, "output")
require "fileutils"
FileUtils.mkdir_p(OUTPUT_DIR)

display = Display.new(log_path: log_path)

shared_config = RobotLab::RunConfig.new(
  model: "claude-sonnet-4-5-20250929",
  temperature: 0.7
)

room = Room.new(display: display, config: shared_config)

# Create identical writers
initial_writers.times do |i|
  room.add_writer("writer_#{i + 1}")
end

# Monitor shared memory changes
room.memory.subscribe_pattern("chapter_*") do |change|
  display.info("[memory] #{change.writer} wrote :#{change.key}")
end

room.memory.subscribe(:story_bible, :outline, :claims, :book_complete) do |change|
  display.info("[memory] #{change.writer} updated :#{change.key}")
end

# ── Go ───────────────────────────────────────────────────────

display.banner(<<~BANNER)
  ============================================================
    THE WRITERS' ROOM — Self-Organizing Group
  ============================================================

    Premise: #{premise}
    Writers: #{room.writers.keys.join(', ')}
    Goal:    10 chapters of fiction
    Method:  Self-organization via bus + shared memory
BANNER

display.separator

assignment = <<~ASSIGNMENT
  ASSIGNMENT: Write a 10-chapter science fiction novella about #{premise}.

  You are one of #{initial_writers} writers in this room. Coordinate among
  yourselves to produce the book. Discuss the premise, build a story bible,
  create an outline, claim chapters, and write them. If you need more writers,
  spawn them. When all 10 chapters are done, mark complete.

  Start by discussing what this story should be about.
ASSIGNMENT

room.seed(assignment)

completed = room.wait_for_completion(timeout: timeout)

# ── Assemble and save ────────────────────────────────────────

display.separator

book = room.assemble_book
book_path = File.join(OUTPUT_DIR, "book.md")
File.write(book_path, book)

# Count chapters actually written
chapters_written = (1..10).count { |n| room.memory.key?(:"chapter_#{n}") }

display.stats(<<~STATS)
  ────────────────────────────────────────────────────────────
    Writers' Room Stats:
      Chapters written:     #{chapters_written}/10
      Completed:            #{completed}
      Total writers:        #{room.writers.size} (#{room.writers.size - initial_writers} spawned)
      Writers:              #{room.writers.keys.join(', ')}
      Memory keys:          #{room.memory.keys.join(', ')}

    Output: #{book_path}
STATS

display.close
