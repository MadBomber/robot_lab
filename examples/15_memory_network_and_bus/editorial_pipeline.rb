#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 15: OS Research Editorial Pipeline — Network + Memory + Bus + Spawn
#
# Three writers advocate for different operating systems (macOS, Windows,
# Linux/BSD) for home AI research labs. The Linux writer spawns distro
# specialists. An editor synthesizes. An editor-in-chief gives final approval.
#
# This showcases all three coordination mechanisms working together:
#
#   NETWORK (parallel pipeline + shared memory)
#   ┌──────────────────────────────────────────────────────┐
#   │  mac_writer    ──┐                                   │
#   │  win_writer    ──┼── editor ──→ combined article     │
#   │  linux_writer  ──┘                                   │
#   │    └── spawns distro specialists via spawn()         │
#   │                                                      │
#   │  MEMORY carries drafts between stages                │
#   │    :mac_draft, :windows_draft, :linux_draft          │
#   └──────────────────────────────────────────────────────┘
#                         │
#                    BUS (review loop)
#                         │
#                   ┌─────┴──────┐
#                   │   chief    │
#                   └────────────┘
#
# - NETWORK orchestrates 3 parallel writers → editor synthesis
# - MEMORY passes advocacy drafts between pipeline stages
# - BUS enables editor ↔ chief revision loop after pipeline
# - SPAWN creates distro specialists dynamically within pipeline
#
# Usage:
#   bundle exec ruby examples/15_memory_network_and_bus/editorial_pipeline.rb

ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "prompts")

require_relative "../../lib/robot_lab"
require "fileutils"

RubyLLM.configure { |c| c.logger = Logger.new(File::NULL) }

MAX_REVISIONS = 3
OUTPUT_DIR    = File.join(__dir__, "output")

FileUtils.mkdir_p(OUTPUT_DIR)

# ── Load robot classes ────────────────────────────────────

require_relative "os_writer"
require_relative "linux_writer"
require_relative "os_editor"
require_relative "editor_in_chief"

# ── Build Everything ──────────────────────────────────────

bus = TypedBus::MessageBus.new

mac_writer = OsWriter.new(
  name: "mac_writer",
  template: :os_advocate,
  local_tools: [RobotLab::AskUser],
  context: {
    os_name: "macOS",
    strengths: "Apple Silicon (M-series) performance, Metal GPU framework, Unix foundation, CoreML integration, energy efficiency"
  },
  memory_key: :mac_draft
)

win_writer = OsWriter.new(
  name: "win_writer",
  template: :os_advocate,
  local_tools: [RobotLab::AskUser],
  context: {
    os_name: "Windows",
    strengths: "NVIDIA CUDA first-class support, WSL2 Linux compatibility, DirectML, widest hardware selection, enterprise tool integration"
  },
  memory_key: :windows_draft
)

linux_writer = LinuxWriter.new(
  name: "linux_writer",
  template: :os_advocate,
  local_tools: [RobotLab::AskUser],
  context: {
    os_name: "Linux/BSD",
    strengths: "Full GPU stack control, Docker-native, free and open source, server parity, massive community packages"
  },
  memory_key: :linux_draft,
  bus: bus
)

editor = OsEditor.new(
  name: "editor",
  template: :os_editor,
  bus: bus
)

# Editor handles revision requests from the chief via bus
revision_count = 0
editor.on_message do |message|
  revised = editor.run(message.content).reply.strip
  editor.instance_variable_set(:@article, revised)

  revision_count += 1
  path = File.join(OUTPUT_DIR, "revision_#{revision_count}.md")
  File.write(path, "# Revision #{revision_count}\n\n#{revised}\n")
  puts "  Editor  [revised]: #{revised[0..120]}..."
  puts "  [editor] Revision written to #{path}"

  editor.reply(message, revised)
end

chief = EditorInChief.new(
  name: "chief",
  template: :os_chief,
  bus: bus
)

# Network orchestrates the writing pipeline
network = RobotLab.create_network(name: "os_editorial") do
  task :mac_writer,   mac_writer,   depends_on: :none
  task :win_writer,   win_writer,   depends_on: :none
  task :linux_writer, linux_writer, depends_on: :none
  task :editor,       editor,       depends_on: [:mac_writer, :win_writer, :linux_writer]
end

# Give each pipeline robot a direct reference to shared memory.
# extract_run_context's delete() pattern mutates the shared run_params
# hash, so parallel steps lose network_memory after the first one runs.
shared_memory = network.memory
[mac_writer, win_writer, linux_writer, editor].each do |robot|
  robot.shared_memory = shared_memory
end

# Monitor shared memory changes during the pipeline
network.memory.subscribe(
  :mac_draft, :windows_draft, :linux_draft,
  :ubuntu_specialist, :fedora_specialist, :freebsd_specialist
) do |change|
  puts "  [memory] :#{change.key} updated by #{change.writer}"
end

# ── Run ──────────────────────────────────────────────────────

puts "=" * 60
puts "Example 15: OS Research Editorial Pipeline"
puts "  Network + Memory + Bus + Spawn"
puts "=" * 60
puts
puts network.visualize
puts

# ── Phase 1: Writing Pipeline (Network + Memory + Spawn) ──

puts "Phase 1: Writing Pipeline (Network + Memory + Spawn)"
puts "-" * 40

# Gather the research focus from the user via AskUser
ask = RobotLab::AskUser.new
focus = ask.call(
  "question" => "What AI research focus areas for the home lab article?",
  "default"  => "LLM fine-tuning, image generation, and local inference"
)

topic = "Write about your operating system's advantages for building a home AI research lab focused on #{focus}."

result = network.run(message: topic)
article = editor.article

puts
puts "  Article excerpt: #{article[0..200]}..." if article
puts
puts "  Memory keys: #{network.memory.keys.join(', ')}"
puts "  Specialists spawned: #{linux_writer.specialists.size}"

# ── Phase 2: Editorial Review (Bus) ──────────────────────

puts
puts "Phase 2: Editorial Review (Bus)"
puts "-" * 40

# Chief reviews the article via bus — may trigger revision loop
chief.send_message(to: :editor, content: article)

final_article = editor.article
final_path = File.join(OUTPUT_DIR, "final_article.md")
status = chief.accepted ? "APPROVED" : "NOT APPROVED (max revisions reached)"
File.write(final_path, "# Final Article — #{status}\n\n#{final_article}\n")

puts
puts "-" * 60
puts "Revisions: #{chief.rounds} | Accepted: #{chief.accepted}"
puts "Specialists spawned: #{linux_writer.specialists.size}"
puts "Output directory: #{OUTPUT_DIR}"
puts "=" * 60

puts

require "json"

memory_path = File.join(OUTPUT_DIR, "memory.json")
File.write(memory_path, JSON.pretty_generate(shared_memory.to_h))
puts
puts "Memory written to #{memory_path}"
