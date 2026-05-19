#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 10: Advanced Memory Operations
#
# Demonstrates the Memory API without making any LLM calls. Covers:
#   - StateProxy for method-style data access
#   - Key subscriptions with MemoryChange objects
#   - Pattern subscriptions
#   - Unsubscribe
#   - Key enumeration (keys, all_keys, key?)
#   - Serialization (to_h, from_hash, to_json) with amazing_print
#   - Serialization round-trip verification with hashdiff
#   - Clone for isolated copies
#   - Delete with reserved key protection
#   - Clear vs reset
#
# Usage:
#   bundle exec ruby examples/10_memory.rb

require_relative "common"
require "json"
require "amazing_print"
require "hashdiff"

banner "Advanced Memory Operations"

# =============================================================================
# Section 1: StateProxy for method-style access
# =============================================================================

section "Section 1: StateProxy for Method-Style Access"

memory = RobotLab.create_memory(
  data: { category: nil, priority: "low" },
  enable_cache: false
)

puts "Initial data:"
ap memory.data.to_h
puts

# StateProxy allows method-style access to the :data hash
memory.data.category = "billing"

puts "After memory.data.category = 'billing':"
ap memory.data.to_h
puts

# Bracket-style also works
memory.data[:priority] = "high"
puts "After memory.data[:priority] = 'high':"
ap memory.data.to_h
puts

# =============================================================================
# Section 2: Subscriptions and MemoryChange
# =============================================================================

section "Section 2: Subscriptions and MemoryChange"

changes = []

sub_id = memory.subscribe(:status) do |change|
  changes << change
end

puts "Subscribed to :status (sub_id: #{sub_id[0..7]}...)"

# Set current_writer so the MemoryChange knows who wrote
memory.current_writer = "classifier"
memory.set(:status, "processing")

# Give the async callback time to fire
sleep 0.1

if changes.any?
  change = changes.first
  puts "Change received:"
  ap change.to_h
  puts "  created?: #{change.created?}"
  puts "  updated?: #{change.updated?}"
end

# Update the same key to see an 'updated' change
memory.set(:status, "complete")
sleep 0.1

if changes.size > 1
  puts
  puts "Second change (update):"
  ap changes.last.to_h
  puts "  created?: #{changes.last.created?}"
  puts "  updated?: #{changes.last.updated?}"
end
puts

# =============================================================================
# Section 3: Pattern subscriptions
# =============================================================================

section "Section 3: Pattern Subscriptions"

pattern_changes = []

pattern_sub_id = memory.subscribe_pattern("analysis:*") do |change|
  pattern_changes << change
end

puts "Subscribed to pattern 'analysis:*'"

memory.current_writer = "analyst"
memory.set(:"analysis:sentiment", { score: 0.8 })
memory.set(:"analysis:entities", ["Ruby", "LLM"])
memory.set(:unrelated_key, "ignored")

sleep 0.1

puts "Pattern matched #{pattern_changes.size} changes (expected 2):"
pattern_changes.each do |change|
  ap({ change.key => change.value })
end
puts

# =============================================================================
# Section 4: Unsubscribe
# =============================================================================

section "Section 4: Unsubscribe"

count_before = changes.size
memory.unsubscribe(sub_id)
puts "Unsubscribed from :status"

memory.set(:status, "archived")
sleep 0.1

puts "Changes after unsubscribe: #{changes.size} (was #{count_before}, should be same)"
puts

# =============================================================================
# Section 5: Key management
# =============================================================================

section "Section 5: Key Management"

puts "memory.keys (non-reserved):"
ap memory.keys
puts

puts "memory.all_keys (includes reserved: data, results, messages, session_id, cache):"
ap memory.all_keys
puts

puts "memory.key?(:status) = #{memory.key?(:status)}"
puts "memory.key?(:nope)   = #{memory.key?(:nope)}"
puts

# =============================================================================
# Section 6: Serialization round-trip
# =============================================================================

section "Section 6: Serialization Round-Trip"

hash = memory.to_h
puts "memory.to_h:"
ap hash
puts

json_str = memory.to_json
puts "memory.to_json length: #{json_str.length} chars"
puts

# Round-trip via from_hash
restored = RobotLab::Memory.from_hash(hash)

puts "Restored memory from hash:"
ap restored.to_h
puts

# Use hashdiff to verify the round-trip preserved everything
diff = Hashdiff.diff(hash, restored.to_h)
if diff.empty?
  puts "Round-trip verification: PERFECT (no differences)"
else
  puts "Round-trip differences:"
  diff.each do |change|
    op, path, *values = change
    case op
    when "+"
      puts "  + #{path}: #{values.first.inspect}"
    when "-"
      puts "  - #{path}: #{values.first.inspect}"
    when "~"
      puts "  ~ #{path}: #{values.first.inspect} -> #{values.last.inspect}"
    end
  end
end
puts

# =============================================================================
# Section 7: Clone for isolation
# =============================================================================

section "Section 7: Clone for Isolation"

cloned = memory.clone
cloned.set(:isolated_key, "only in clone")

puts "cloned.key?(:isolated_key)  = #{cloned.key?(:isolated_key)}"
puts "memory.key?(:isolated_key)  = #{memory.key?(:isolated_key)}  (isolated!)"
puts

# Show exactly what differs between clone and original
diff = Hashdiff.diff(memory.to_h, cloned.to_h)
puts "Diff (original vs clone):"
diff.each do |change|
  op, path, *values = change
  case op
  when "+"
    puts "  + #{path}: #{values.first.inspect}"
  when "-"
    puts "  - #{path}: #{values.first.inspect}"
  when "~"
    puts "  ~ #{path}: #{values.first.inspect} -> #{values.last.inspect}"
  end
end
puts

# =============================================================================
# Section 8: Delete and reserved key protection
# =============================================================================

section "Section 8: Delete and Reserved Key Protection"

before_delete = memory.to_h
memory.delete(:status)

puts "After memory.delete(:status):"
diff = Hashdiff.diff(before_delete, memory.to_h)
diff.each do |change|
  op, path, *values = change
  case op
  when "-"
    puts "  - #{path}: #{values.first.inspect}"
  end
end
puts

begin
  memory.delete(:data)
rescue ArgumentError => e
  puts "memory.delete(:data) raises: #{e.message}"
end
puts

# =============================================================================
# Section 9: Clear vs Reset
# =============================================================================

section "Section 9: Clear vs Reset"

memory.set(:temp1, "value1")
memory.set(:temp2, "value2")

puts "Before clear:"
before_clear = memory.to_h
ap before_clear
puts

memory.clear

puts "After clear (non-reserved keys removed):"
after_clear = memory.to_h
ap after_clear
puts

puts "Diff (before clear vs after clear):"
Hashdiff.diff(before_clear, after_clear).each do |change|
  op, path, *values = change
  case op
  when "+"
    puts "  + #{path}: #{values.first.inspect}"
  when "-"
    puts "  - #{path}: #{values.first.inspect}"
  when "~"
    puts "  ~ #{path}: #{values.first.inspect} -> #{values.last.inspect}"
  end
end
puts

before_reset = memory.to_h
memory.reset

puts "After reset (full reset to initial state):"
after_reset = memory.to_h
ap after_reset
puts

puts "Diff (before reset vs after reset):"
Hashdiff.diff(before_reset, after_reset).each do |change|
  op, path, *values = change
  case op
  when "+"
    puts "  + #{path}: #{values.first.inspect}"
  when "-"
    puts "  - #{path}: #{values.first.inspect}"
  when "~"
    puts "  ~ #{path}: #{values.first.inspect} -> #{values.last.inspect}"
  end
end
puts

hr
puts "All sections completed without any LLM calls."
