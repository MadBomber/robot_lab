#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 9: Robot Chaining & Reconfiguration
#
# Demonstrates the Robot API surface for runtime configuration without
# making any LLM calls. Covers:
#   - with_* method chaining
#   - update() for reconfiguration
#   - to_h introspection (via amazing_print)
#   - Config diffs between steps (via hashdiff)
#   - Template front matter config keys
#   - Constructor params overriding front matter
#   - Config hierarchy in action
#   - AskUser tool for gathering template parameters interactively
#
# Usage:
#   bundle exec ruby examples/09_chaining.rb

require_relative "common"
require "amazing_print"
require "hashdiff"
require "stringio"

# Show a config snapshot and the diff from the previous snapshot.
# Returns the current hash for use as the next "previous" snapshot.
def show_config(robot, previous_config = nil)
  current = robot.to_h
  ap current

  if previous_config
    diff = Hashdiff.diff(previous_config, current)
    if diff.empty?
      puts "  (no changes to to_h)"
    else
      puts
      puts "  Diff from previous:"
      diff.each do |change|
        op, path, *values = change
        case op
        when "+"
          puts "    + #{path}: #{values.first.inspect}"
        when "-"
          puts "    - #{path}: #{values.first.inspect}"
        when "~"
          puts "    ~ #{path}: #{values.first.inspect} -> #{values.last.inspect}"
        end
      end
    end
  end

  current
end

banner "Robot Chaining & Reconfiguration"

# =============================================================================
# Section 1: Template front matter config
# =============================================================================

section "Section 1: Template Front Matter Config"

# The 'configurable' template sets temperature: 0.3 and max_tokens: 200
# via YAML front matter. These are applied automatically.
robot = RobotLab.build(
  **llm_opts,
  name: "chameleon",
  template: :configurable,
  context: { task_type: "analysis" }
)

puts "Robot created with :configurable template"
prev = show_config(robot)
puts

# =============================================================================
# Section 2: with_* method chaining
# =============================================================================

section "Section 2: with_* Method Chaining"

# with_* methods return self, enabling fluent chaining.
# These override whatever the template set.
robot.with_temperature(0.9)

puts "After chaining with_temperature(0.9):"
prev = show_config(robot, prev)
puts

# =============================================================================
# Section 3: update() for reconfiguration
# =============================================================================

section "Section 3: update() for Reconfiguration"

# update() can swap the template, model, temperature, and other settings.
robot.update(template: :assistant, temperature: 0.5)

puts "After update(template: :assistant, temperature: 0.5):"
prev = show_config(robot, prev)
puts

# Swap back with context
robot.update(template: :configurable, context: { task_type: "creative" })

puts "After update(template: :configurable, context: { task_type: 'creative' }):"
prev = show_config(robot, prev)
puts

# =============================================================================
# Section 4: Constructor params override front matter
# =============================================================================

section "Section 4: Constructor Params Override Front Matter"

# The configurable template sets temperature: 0.3 in front matter.
# Passing temperature: 0.9 to the constructor overrides it.
robot2 = RobotLab.build(
  **llm_opts,
  name: "override_demo",
  template: :configurable,
  context: { task_type: "creative" },
  temperature: 0.9
)

puts "Template sets temperature: 0.3, constructor passes temperature: 0.9"
prev2 = show_config(robot2)
puts

# =============================================================================
# Section 5: RunConfig as alternative to individual kwargs
# =============================================================================

section "Section 5: RunConfig as Alternative to Individual kwargs"

# Instead of passing model:, temperature:, etc. individually,
# use a RunConfig to express shared defaults.
shared = RobotLab::RunConfig.new(model: LLM[:default].model, temperature: 0.5)

puts "RunConfig: #{shared.to_h.inspect}"
puts

# Robot inherits from RunConfig; constructor kwargs still override
robot3 = RobotLab.build(
  **llm_opts,
  name: "runconfig_demo",
  template: :configurable,
  context: { task_type: "analysis" },
  config: shared,
  temperature: 0.8  # overrides RunConfig's 0.5
)

puts "Robot with config: shared, temperature: 0.8"
puts "(RunConfig sets 0.5, constructor overrides to 0.8)"
prev3 = show_config(robot3)
puts

# RunConfig merge semantics
creative = RobotLab::RunConfig.new(temperature: 0.9, max_tokens: 2000)
merged = shared.merge(creative)

puts "Merge: shared.merge(creative)"
puts "  shared:   #{shared.to_h.inspect}"
puts "  creative: #{creative.to_h.inspect}"
puts "  merged:   #{merged.to_h.inspect}"
puts "  (model inherited, temperature overridden, max_tokens added)"
puts

# =============================================================================
# Section 6: Bare robot with chaining
# =============================================================================

section "Section 6: Bare Robot with Chaining"

# A bare robot has no template. Configure entirely via chaining.
bare = RobotLab.build(name: "bare")

puts "Bare robot before chaining:"
prev_bare = show_config(bare)
puts

bare
  .with_instructions("You are a helpful assistant.")
  .with_temperature(0.5)

puts "After with_instructions(...).with_temperature(0.5):"
prev_bare = show_config(bare, prev_bare)
puts

# =============================================================================
# Section 7: with_template() on an existing robot
# =============================================================================

section "Section 7: with_template() on Existing Robot"

# You can apply a template to a robot after creation.
bare.with_template(:helper)

puts "After bare.with_template(:helper):"
show_config(bare, prev_bare)
puts

# =============================================================================
# Section 8: AskUser tool for gathering template parameters
# =============================================================================

section "Section 8: AskUser for Template Parameters"
puts "The :configurable template declares `task_type: general` in its front"
puts "matter. That default is offered to the user — they can accept it by"
puts "pressing Enter or type something else. Parameters with null values"
puts "have no default and require user input."
puts

# Build a robot with AskUser — the template's task_type default ("general")
# is offered to the user, who can accept or override it.
interactive = RobotLab.build(
  **llm_opts,
  name: "interactive_demo",
  template: :configurable,
  local_tools: [RobotLab::AskUser]
)

puts "Robot 'interactive_demo' has AskUser in its tools."
puts "The template renders with the default: task_type = \"general\""
puts "When run, the robot can call ask_user to let the user confirm"
puts "or change the value."
puts

# Simulate what the user would see (no LLM call needed)
output = StringIO.new
demo_tool = RobotLab::AskUser.new(robot: interactive)
interactive.output = output
interactive.input  = StringIO.new("2\n")

result = demo_tool.call(
  "question" => "What type of task should I optimize for?",
  "choices"  => %w[general analysis creative coding research],
  "default"  => "general"
)

puts output.string
puts "User selected: #{result}"
puts
puts "The robot would re-render the template with task_type: \"#{result}\""
puts "producing: \"You are a precise assistant optimized for #{result} tasks.\""
puts
puts "If the user had pressed Enter, the default \"general\" would be kept."
puts

hr
puts "All sections completed without any LLM calls."
