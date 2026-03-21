#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 23: Debate Convergence Detection
#
# Demonstrates RobotLab::Convergence for detecting when two independent
# agents have reached the same conclusion. This enables a fast-path that
# skips an expensive reconciler LLM call when verifiers already agree.
#
# Demonstrates:
#   - Convergence.similarity(a, b) — 0.0..1.0 cosine similarity score
#   - Convergence.detected?(a, b) — boolean above default threshold (0.85)
#   - Convergence.detected?(a, b, threshold: 0.6) — custom threshold
#   - Router fast-path pattern: skip reconciler when verifiers agree
#
# Requires:
#   gem 'classifier', '~> 2.3'   # add to your Gemfile
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/23_convergence.rb

ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

# ---------------------------------------------------------------------------
# Check optional dependency
# ---------------------------------------------------------------------------
begin
  require "classifier"
rescue LoadError
  puts "This example requires the classifier gem."
  puts "Add to your Gemfile:  gem 'classifier', '~> 2.3'"
  exit 1
end

puts "=" * 60
puts "Example 23: Debate Convergence Detection"
puts "=" * 60
puts

# ---------------------------------------------------------------------------
# Similarity scoring
# ---------------------------------------------------------------------------
pairs = {
  "Identical responses" => [
    "The time complexity of quicksort is O(n log n) average case and O(n²) worst case. Use merge sort for guaranteed O(n log n).",
    "The time complexity of quicksort is O(n log n) average case and O(n²) worst case. Use merge sort for guaranteed O(n log n)."
  ],
  "Semantically similar (same conclusion)" => [
    "Quicksort has average O(n log n) time complexity but degrades to O(n²) in the worst case. Prefer merge sort when stability matters.",
    "The average time complexity of quicksort is O(n log n). In the worst case it becomes O(n²), so merge sort is safer for sorted input."
  ],
  "Partially related (same topic, different focus)" => [
    "Quicksort is O(n log n) average case. It is in-place and cache-friendly, making it fast in practice despite worst-case concerns.",
    "Merge sort guarantees O(n log n) in all cases and is stable. It requires O(n) extra space unlike the in-place quicksort."
  ],
  "Unrelated responses" => [
    "Quicksort has average O(n log n) time complexity but degrades to O(n²) in the worst case.",
    "The Pacific Ocean is the largest and deepest ocean on Earth, covering more than thirty percent of the planet surface area."
  ]
}

puts "Similarity scores:"
puts "-" * 60
pairs.each do |label, (a, b)|
  score = RobotLab::Convergence.similarity(a, b)
  converged = RobotLab::Convergence.detected?(a, b, threshold: 0.6)
  puts "  #{label}"
  puts "    Score: #{"%.3f" % score}  |  Converged at 0.60: #{converged ? "YES" : "no"}"
  puts
end

# ---------------------------------------------------------------------------
# Router fast-path pattern
# ---------------------------------------------------------------------------
puts "=" * 60
puts "Router fast-path pattern"
puts "=" * 60
puts <<~RUBY

  # Two verifier robots run in parallel and store their replies in shared memory.
  # The router checks convergence before dispatching to the expensive reconciler.

  router = ->(args) do
    a = args.context[:verifier_a]&.reply.to_s
    b = args.context[:verifier_b]&.reply.to_s

    if RobotLab::Convergence.detected?(a, b)
      nil   # Both agree — skip reconciler, network halts here
    else
      ["reconciler"]
    end
  end

  network = RobotLab.create_network(
    name:   "fact_check",
    robots: [verifier_a, verifier_b, reconciler],
    router: router
  )

  result = network.run(message: "Is this claim accurate?")

RUBY

# ---------------------------------------------------------------------------
# Demonstrate with simulated verifier outputs
# ---------------------------------------------------------------------------
puts "Simulating verifier fast-path:"
puts "-" * 60

verifier_outputs = [
  {
    label:  "Verifiers agree (skip reconciler)",
    a:      "The claim is accurate. Photosynthesis converts light energy into glucose using carbon dioxide and water, producing oxygen as a byproduct.",
    b:      "This is correct. Photosynthesis uses sunlight, CO₂, and water to produce glucose and oxygen in plant cells.",
    threshold: 0.5
  },
  {
    label:  "Verifiers disagree (call reconciler)",
    a:      "The claim is accurate. The Great Wall of China is visible from space with the naked eye at low Earth orbit.",
    b:      "The claim is false. Astronauts confirm the Great Wall cannot be seen from space without magnification because it is far too narrow.",
    threshold: 0.7
  }
]

verifier_outputs.each do |scenario|
  score     = RobotLab::Convergence.similarity(scenario[:a], scenario[:b])
  converged = RobotLab::Convergence.detected?(scenario[:a], scenario[:b], threshold: scenario[:threshold])
  action    = converged ? "SKIP reconciler (fast-path)" : "CALL reconciler"

  puts "  #{scenario[:label]}"
  puts "    Score: #{"%.3f" % score}  →  #{action}"
  puts
end

puts "Done."
