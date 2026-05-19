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
#   - Memory persistence: learnings survive rebuilding with the same Memory
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/21_learning_loop.rb

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
  model: LLM[:default].model,
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
robot2 = RobotLab.build(name: "reviewer2", system_prompt: "You review code.")

robot2.learn("avoid using puts")
robot2.learn("avoid using puts and p in production code")  # covers the first

puts "Learnings after adding broader statement (should be 1, not 2):"
robot2.learnings.each_with_index { |l, i| puts "  #{i + 1}. #{l}" }
puts

# ---------------------------------------------------------------
# Demonstrate persistence: learnings survive a robot rebuild using
# the same Memory object
# ---------------------------------------------------------------
section "Persistence Across Rebuild"

shared_memory = robot.instance_variable_get(:@memory)
rebuilt = RobotLab.build(
  model: LLM[:default].model,
  name: "code_reviewer",
  system_prompt: "You review code."
)
rebuilt.instance_variable_set(:@memory, shared_memory)

# Trigger the memory restore path
persisted = shared_memory.get(:learnings)
rebuilt.instance_variable_set(:@learnings, Array(persisted))

puts "Learnings on rebuilt robot (#{rebuilt.learnings.size}):"
rebuilt.learnings.each_with_index { |l, i| puts "  #{i + 1}. #{l}" }
puts

hr
puts "Learning loop demo complete."
