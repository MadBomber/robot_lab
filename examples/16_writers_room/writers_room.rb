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
# Modes:
#   Book mode (default) — write an original 10-chapter novella
#   Screenplay mode     — adapt a finished book into a 4-act TV movie pilot
#
# Usage:
#   bundle exec ruby examples/16_writers_room/writers_room.rb
#   bundle exec ruby examples/16_writers_room/writers_room.rb --premise "a detective story set on Mars"
#   bundle exec ruby examples/16_writers_room/writers_room.rb --writers 4 --timeout 300
#   bundle exec ruby examples/16_writers_room/writers_room.rb --log session.log
#   bundle exec ruby examples/16_writers_room/writers_room.rb --screenplay-from output/memory.json
#   bundle exec ruby examples/16_writers_room/writers_room.rb -h

ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "prompts")

require "json"
require_relative "../common"
require_relative "display"
require_relative "tools"
require_relative "room"
require_relative "writer"

# ── Mode Descriptors ────────────────────────────────────────

BOOK_MODE = {
  name:            :book,
  template:        :writer,
  unit_name:       "chapter",
  unit_range:      1..10,
  completion_key:  :book_complete,
  bible_key:       :story_bible,
  outline_key:     :outline,
  output_filename: "book.md"
}.freeze

SCREENPLAY_MODE = {
  name:            :screenplay,
  template:        :screenplay_writer,
  unit_name:       "scene",
  unit_range:      :dynamic,
  registry_key:    :scene_registry,
  completion_key:  :screenplay_complete,
  bible_key:       :screenplay_bible,
  outline_key:     :scene_outline,
  output_filename: "screenplay.md"
}.freeze

# ── Parse CLI args ───────────────────────────────────────────

if ARGV.include?("-h") || ARGV.include?("--help")
  puts <<~HELP
    Usage: #{$0} [options]

    Options:
      --premise TEXT              Story premise (default: generation ship AI consciousness)
      --writers N                 Initial number of writers, minimum 2 (default: 3)
      --log FILE                 Also write display output to FILE
      --timeout N                Seconds to wait for completion (default: 600)
      --screenplay-from PATH     Adapt a finished book into a screenplay using
                                 memory dumped from a previous book-mode run
      -h, --help                 Show this help
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

screenplay_source = nil
if (idx = ARGV.index("--screenplay-from"))
  screenplay_source = ARGV[idx + 1]
  abort "Missing value for --screenplay-from" unless screenplay_source
  abort "File not found: #{screenplay_source}" unless File.exist?(screenplay_source)
end

mode = screenplay_source ? SCREENPLAY_MODE : BOOK_MODE

# ── Build the room ───────────────────────────────────────────

OUTPUT_DIR = File.join(__dir__, "output")
require "fileutils"
FileUtils.mkdir_p(OUTPUT_DIR)

display = Display.new(log_path: log_path)

# RunConfig has no `provider` field, so the writers get provider+model via
# **llm_opts and inherit the rest of their operational defaults from here.
shared_config = RobotLab::RunConfig.new(
  model: LLM[:default].model,
  temperature: 0.7
)

room = Room.new(display: display, mode: mode, config: shared_config)

# Load source material into memory for screenplay mode
if screenplay_source
  source_data = JSON.parse(File.read(screenplay_source))
  source_data.each { |key, value| room.memory.set(key.to_sym, value) }
  display.info("Loaded #{source_data.size} memory keys from #{screenplay_source}")
end

# Create identical writers
initial_writers.times do |i|
  room.add_writer("writer_#{i + 1}")
end

# Monitor shared memory changes
room.memory.subscribe_pattern("#{mode[:unit_name]}_*") do |change|
  display.info("[memory] #{change.writer} wrote :#{change.key}")
end

subscribe_keys = [mode[:bible_key], mode[:outline_key], :claims, mode[:completion_key]]
subscribe_keys << mode[:registry_key] if mode[:registry_key]
room.memory.subscribe(*subscribe_keys) do |change|
  display.info("[memory] #{change.writer} updated :#{change.key}")
end

# ── Go ───────────────────────────────────────────────────────

goal_label = mode[:name] == :book ? "10 chapters of fiction" : "4-act TV movie screenplay (dynamic scenes)"

display.banner(<<~BANNER)
  ============================================================
    THE WRITERS' ROOM — Self-Organizing Group
  ============================================================

    Mode:    #{mode[:name]}
    Premise: #{premise}
    Writers: #{room.writers.keys.join(', ')}
    Goal:    #{goal_label}
    Method:  Self-organization via bus + shared memory
BANNER

display.separator

if mode[:name] == :screenplay
  assignment = <<~ASSIGNMENT
    ASSIGNMENT: Adapt the source material into a 4-act made-for-TV movie screenplay
    (pilot for a potential series). Work at the SCENE level — each writer claims
    and writes individual scenes.

    The source material is already loaded into shared memory. Read the story_bible,
    outline, and chapter_1 through chapter_10 to understand the original book.

    You are one of #{initial_writers} writers in this room. Coordinate among
    yourselves to produce the screenplay:
    1. Read the source material
    2. Build a screenplay_bible (adaptation choices)
    3. Create a scene_outline with numbered scenes grouped into 4 acts
    4. Write the scene_registry (comma-separated scene numbers, e.g. "1,2,3,4,5,6,7,8,9,10,11,12")
    5. Claim and write individual scenes (scene_1, scene_2, etc.)
    6. Spawn more writers when unclaimed scenes exceed active writers
    7. Mark complete when all registered scenes are written

    Scenes may be dropped or reordered as the story takes shape — update the
    scene_registry when that happens.

    Start by reading the source material and discussing how to adapt it for screen.
  ASSIGNMENT
else
  assignment = <<~ASSIGNMENT
    ASSIGNMENT: Write a 10-chapter science fiction novella about #{premise}.

    You are one of #{initial_writers} writers in this room. Coordinate among
    yourselves to produce the book. Discuss the premise, build a story bible,
    create an outline, claim chapters, and write them. If you need more writers,
    spawn them. When all 10 chapters are done, mark complete.

    Start by discussing what this story should be about.
  ASSIGNMENT
end

room.seed(assignment)

completed = room.wait_for_completion(timeout: timeout)

# ── Assemble and save ────────────────────────────────────────

display.separator

output_text = room.assemble_output
output_path = File.join(OUTPUT_DIR, mode[:output_filename])
File.write(output_path, output_text)

# Dump memory for book mode (enables later screenplay adaptation)
if mode[:name] == :book
  memory_path = File.join(OUTPUT_DIR, "memory.json")
  custom = room.memory.keys.each_with_object({}) do |k, h|
    next if %i[results messages].include?(k)
    h[k] = room.memory.get(k)
  end
  File.write(memory_path, JSON.pretty_generate(custom))
  display.info("Memory dumped to #{memory_path}")
end

# Count units actually written
unit_name     = mode[:unit_name]
expected      = room.expected_units
units_written = expected.count { |n| room.memory.key?(:"#{unit_name}_#{n}") }

display.stats(<<~STATS)
  ────────────────────────────────────────────────────────────
    Writers' Room Stats:
      Mode:                 #{mode[:name]}
      #{unit_name.capitalize}s written:#{' ' * (10 - unit_name.length)}#{units_written}/#{expected.size}
      Completed:            #{completed}
      Total writers:        #{room.writers.size} (#{room.writers.size - initial_writers} spawned)
      Writers:              #{room.writers.keys.join(', ')}
      Memory keys:          #{room.memory.keys.join(', ')}

    Output: #{output_path}
STATS

display.close
