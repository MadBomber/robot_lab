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
#   ANTHROPIC_API_KEY=your_key ruby examples/34_agentskills.rb

ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

require "logger"
log_file = File.join(__dir__, "34.log")
RobotLab.config.logger = Logger.new(log_file)
RubyLLM.configure { |c| c.logger = Logger.new(log_file) }

puts "=" * 60
puts "RobotLab — AgentSkills.io Integration Demo"
puts "=" * 60
puts

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
  name: "assistant",
  system_prompt: "You are a helpful Ruby programming assistant.",
  skills: [:code_reviewer]
)

puts "Pending AgentSkills: #{robot.instance_variable_get(:@pending_agent_skills).map(&:name).inspect}"
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
puts "=" * 60

# Message unrelated to code review — skill should NOT activate
puts "Query: general question (skill should NOT activate)"
result = robot.run("What is the capital of France?")
puts result.reply
puts
