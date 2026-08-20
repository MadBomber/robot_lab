#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 21: Learning Accumulation Loop
#
# Demonstrates robot.learn() for building up observations between runs.
# A code reviewer robot analyzes Ruby snippets. After each review, the
# caller records a key insight as a learning. On the next run, those
# learnings are automatically prepended to the user message so the robot
# can incorporate prior observations without needing a persistent chat.
#
# Demonstrates:
#   - robot.learn(text) — adds a learning, deduplicates automatically
#   - robot.learnings — read the accumulated list
#   - Learnings injected as "LEARNINGS FROM PREVIOUS RUNS:" prefix
#   - Superset dedup: a broader learning replaces narrower earlier ones
#   - robot.memory[:learnings] — where the list is actually stored
#   - Scope: learnings are per-robot and in-process; see robot_lab-durable
#     (and example 33) for cross-session persistence
#
# Usage:
#   ruby examples/21_learning_loop.rb

require_relative "common"

SNIPPETS = [
  {
    code: <<~RUBY,
      def process(items)
        results = []
        items.each do |item|
          results << item * 2
        end
        results
      end
    RUBY
    insight: "This codebase prefers map/collect over manual array accumulation"
  },
  {
    code: <<~RUBY,
      def find_user(id)
        user = User.find(id)
        if user != nil
          return user
        end
        return nil
      end
    RUBY
    insight: "Explicit nil comparisons and redundant returns appear frequently here"
  },
  {
    code: <<~RUBY,
      def calculate_total(cart)
        total = 0
        cart.items.each do |item|
          if item.discount != nil
            total = total + (item.price - item.discount)
          else
            total = total + item.price
          end
        end
        return total
      end
    RUBY
    insight: "Cart/pricing logic tends to have missing edge cases around nil discounts and zero values"
  }
].freeze

banner "Learning Accumulation Loop"

robot = RobotLab.build(
  **llm_opts,
  name: "code_reviewer",
  system_prompt: <<~PROMPT
    You are a concise Ruby code reviewer. For each snippet:
    1. Identify the main issue (one sentence).
    2. Show the improved version (code block).
    Keep responses under 80 words total.
  PROMPT
)

SNIPPETS.each_with_index do |item, i|
  run_number = i + 1

  # ---------------------------------------------------------------
  # Show what learnings are active going into this run
  # ---------------------------------------------------------------
  section "Run #{run_number}"
  if robot.learnings.empty?
    puts "Learnings:  (none yet)"
  else
    puts "Learnings injected into this prompt:"
    robot.learnings.each { |l| puts "  • #{l}" }
  end
  puts

  # ---------------------------------------------------------------
  # Run the robot — accumulated learnings are prepended automatically
  # ---------------------------------------------------------------
  result = robot.run("Review this Ruby snippet:\n\n#{item[:code]}")

  puts "Review:"
  puts result.reply&.strip&.gsub(/^/, "  ")
  puts

  # ---------------------------------------------------------------
  # Record the insight from this run as a learning
  # ---------------------------------------------------------------
  robot.learn(item[:insight])
  puts "Added learning: #{item[:insight].inspect}"
  puts
end

# ---------------------------------------------------------------
# Show the full accumulated learning list
# ---------------------------------------------------------------
section "Accumulated Learnings (#{robot.learnings.size} total)"
robot.learnings.each_with_index { |l, i| puts "  #{i + 1}. #{l}" }
puts

# ---------------------------------------------------------------
# Demonstrate superset dedup: a broader learning replaces narrower ones
# ---------------------------------------------------------------
section "Deduplication Demo"
robot2 = RobotLab.build(**llm_opts, name: "reviewer2", system_prompt: "You review code.")

robot2.learn("avoid using puts")
robot2.learn("avoid using puts and p in production code")  # covers the first

puts "Learnings after adding broader statement (should be 1, not 2):"
robot2.learnings.each_with_index { |l, i| puts "  #{i + 1}. #{l}" }
puts

# ---------------------------------------------------------------
# Where learnings actually live
#
# learn() writes through to the robot's own Memory under :learnings.
# Memory is exposed by the public `memory` reader, so you can inspect
# (or serialize) the list without touching instance variables.
# ---------------------------------------------------------------
section "Learnings Are Backed by Robot Memory"

puts "robot.memory.get(:learnings):"
Array(robot.memory.get(:learnings)).each_with_index { |l, i| puts "  #{i + 1}. #{l}" }
puts
puts "Same list as robot.learnings? #{robot.memory.get(:learnings) == robot.learnings}"
puts

# ---------------------------------------------------------------
# Scope: learnings do NOT survive a rebuild
#
# Robot#initialize always constructs a fresh Memory and there is no
# `memory:` constructor parameter, so a new robot — even with the same
# name — starts with an empty learning list. learn() is a within-process
# accumulator, not a persistence layer.
# ---------------------------------------------------------------
section "Scope: In-Process Only"

rebuilt = RobotLab.build(
  **llm_opts,
  name: "code_reviewer",
  system_prompt: "You review code."
)

puts "Learnings on a freshly built robot of the same name: #{rebuilt.learnings.size}"
puts "(Robot#initialize builds a new Memory every time — nothing carries over.)"
puts
puts <<~PERSIST
  To carry knowledge across processes, use the robot_lab-durable gem:

    require "robot_lab/durable"
    robot.setup_durable_learning(domain: "ruby code review")
    # ... run the robot ...
    robot.run_reflector   # promotes learnings to ~/.robot_lab/durable/<domain>.yml

  On the next boot setup_durable_learning seeds robot.learnings from that
  YAML store. See examples/33_stock_predictor.rb for a working loop.
PERSIST

hr
puts "Learning loop demo complete."
