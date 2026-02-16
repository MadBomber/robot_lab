#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 13: Spawning Robots — Dynamic Specialist Creation
#
# A dispatcher robot receives a question, decides what kind of
# specialist is needed, spawns one on the fly, and hands off
# the work. The spawned robot replies via the shared message bus.
#
# This demonstrates Werner's "objects that create new objects to
# deal with problems nobody anticipated."
#
# Usage:
#   bundle exec ruby examples/13_spawn.rb

ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

RubyLLM.configure { |c| c.logger = Logger.new(File::NULL) }

QUESTIONS = [
  "Why did the Roman Empire fall?",
  "Write a haiku about recursion.",
  "What is the square root of 144?",
].freeze

class Dispatcher < RobotLab::Robot
  attr_reader :spawned

  def initialize(bus: nil)
    super(name: "dispatcher", template: :dispatcher, bus: bus)
    @spawned = {}
    @pending = {}

    on_message do |message|
      puts "  Dispatcher  <- :#{message.from} replied"
      puts "               | #{message.content.to_s.lines.first&.strip}"
      @pending.delete(message.from)
    end
  end

  def dispatch(question)
    # Ask the LLM which specialist to spawn
    plan = run(question).reply.strip
    role, instruction = plan.split("\n", 2)
    role = role.strip.downcase.gsub(/\s+/, "_")
    instruction = instruction&.strip || "You are a helpful #{role}."

    puts "  Dispatcher  -> spawn :#{role}"
    puts "               | #{instruction}"

    # Spawn the specialist (reuse if already spawned)
    specialist = @spawned[role] ||= spawn(
      name: role,
      system_prompt: instruction
    )

    # Record what we're waiting for
    @pending[role] = question

    # Ask the specialist to work on the question
    specialist.send_message(to: :dispatcher, content:
      specialist.run(question).reply.strip
    )
  end

  def done?
    @pending.empty?
  end
end

# ── main ──────────────────────────────────────────────────────

dispatcher = Dispatcher.new

puts "=" * 60
puts "Example 13: Spawning Specialist Robots"
puts "=" * 60

QUESTIONS.each_with_index do |question, i|
  puts
  puts "Question #{i + 1}: #{question}"
  dispatcher.dispatch(question)
end

puts
puts "-" * 60
puts "Specialists spawned: #{dispatcher.spawned.keys.join(', ')}"
puts "Total robots on bus: #{dispatcher.spawned.size + 1}"
