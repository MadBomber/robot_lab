#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 34: AgentSkills.io Integration
#
# Demonstrates the unified skills: param detecting AgentSkills folder format.
# Skills in ~/.prompts/skills/ are matched at runtime via embedding similarity
# before each run() call — only relevant skills are injected.
#
# Usage:
#   mkdir -p ~/.prompts/skills/code_reviewer
#   # (create SKILL.md as shown in the example header)
#   ruby examples/34_agentskills.rb

require_relative "common"
require "robot_lab/document_store"

require "logger"
log_file = File.join(__dir__, "34.log")
RobotLab.config.logger = Logger.new(log_file)
RubyLLM.configure { |c| c.logger = Logger.new(log_file) }

banner "RobotLab — AgentSkills.io Integration Demo"

# Check if the skill is installed
skill_path = File.expand_path("~/.prompts/skills/code_reviewer/SKILL.md")
unless File.exist?(skill_path)
  puts "Demo skill not found at #{skill_path}"
  puts "Create it with:"
  puts "  mkdir -p ~/.prompts/skills/code_reviewer"
  puts "  # Then add SKILL.md with name: code_reviewer"
  exit 1
end

# Build a robot that lists code_reviewer as a candidate skill.
# At runtime, if the user message is semantically similar to
# "Review Ruby code for quality, style, and potential bugs",
# the skill's instructions are injected into the system prompt.
robot = RobotLab.build(
  **llm_opts,
  name: "assistant",
  system_prompt: "You are a helpful Ruby programming assistant.",
  skills: [:code_reviewer]
)

puts "Declared skills: #{robot.skills.inspect}"
puts "(Folder-format skills are matched per-run by embedding similarity, so"
puts " whether one is injected depends on the message — watch the two queries"
puts " below.)"
puts

# Message semantically related to code review — skill should activate
code_question = <<~MSG
  Please review this Ruby method for quality issues:

  def process(data)
    begin
      result = data.map { |item| transform(item) }
      save(result)
    rescue => e
      puts e.message
    end
  end
MSG

puts "Query: code review (skill should activate)"
result = robot.run(code_question)
puts result.reply
puts
hr

# Message unrelated to code review — skill should NOT activate
puts "Query: general question (skill should NOT activate)"
result = robot.run("What is the capital of France?")
puts result.reply
puts
