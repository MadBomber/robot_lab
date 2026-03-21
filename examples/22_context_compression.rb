#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 22: Context Window Compression
#
# Demonstrates robot.compress_history() for reducing token usage in long
# conversations. Old turns are scored against the recent context using
# stemmed term-frequency cosine similarity. High-relevance turns are kept
# verbatim; irrelevant turns are dropped; medium-relevance turns can be
# summarized by a second robot.
#
# Demonstrates:
#   - robot.compress_history() — drop/keep/summarize old turns in-place
#   - recent_turns: N — last N user+assistant pairs always protected
#   - keep_threshold: / drop_threshold: — tunable relevance bands
#   - summarizer: — optional lambda(text) -> String for medium-relevance
#   - Token reduction reported before/after compression
#
# Requires:
#   gem 'classifier', '~> 2.3'   # add to your Gemfile
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/22_context_compression.rb

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

# ---------------------------------------------------------------------------
# Helper to count approximate tokens (rough: 4 chars per token)
# ---------------------------------------------------------------------------
def approx_tokens(messages)
  messages.sum do |m|
    content = m.respond_to?(:content) ? m.content.to_s : m.to_s
    (content.length / 4.0).ceil
  end
end

puts "=" * 60
puts "Example 22: Context Window Compression"
puts "=" * 60
puts

# ---------------------------------------------------------------------------
# Build a robot and simulate a long conversation on two topics
# ---------------------------------------------------------------------------
bot = RobotLab.build(
  name:          "assistant",
  system_prompt: "You are a concise Ruby expert. Reply in 2-3 sentences."
)

puts "Simulating a long conversation (no real LLM calls)..."
puts

# Simulate a conversation history with two distinct topics:
# older turns: Ruby metaprogramming (will become irrelevant)
# recent turns: Rails routing (current topic)

require "ostruct"

FakeMsg = Struct.new(:role, :content, :tool_calls, :stop_reason) do
  def text?      = true
  def tool_use?  = false
  def system?    = role == :system
  def user?      = role == :user
  def assistant? = role == :assistant
end

def fake(role, content)
  FakeMsg.new(role.to_sym, content, nil, :stop)
end

history = [
  fake(:system,    "You are a concise Ruby expert. Reply in 2-3 sentences."),

  # --- OLD TOPIC: Ruby metaprogramming (5 turns back) ---
  fake(:user,      "Explain Ruby's method_missing and when to use it."),
  fake(:assistant, "method_missing is called when an object receives an undefined message. It's useful for DSLs and proxy objects, but add respond_to_missing? too. Use sparingly as it hurts performance."),
  fake(:user,      "What's the difference between define_method and def?"),
  fake(:assistant, "define_method creates methods dynamically from a block, capturing closure variables. def is the static keyword form. Use define_method when the method body depends on runtime values."),
  fake(:user,      "How does BasicObject differ from Object in Ruby?"),
  fake(:assistant, "BasicObject is the root class with minimal methods, useful for proxy and DSL objects that must not inherit standard methods. Object inherits from BasicObject and adds Kernel, making it the normal base class."),

  # --- RECENT TOPIC: Rails routing (last 2 turns, always protected) ---
  fake(:user,      "How does Rails routing work with resourceful controllers?"),
  fake(:assistant, "resources :posts generates 7 RESTful routes mapping HTTP verbs to controller actions. You can nest resources and add member/collection routes. Run rails routes to see everything."),
  fake(:user,      "What is the difference between member and collection routes in Rails?"),
  fake(:assistant, "Member routes operate on a specific resource (needs :id), collection routes operate on the whole collection. Use member { get :preview } and collection { get :search } inside a resources block.")
]

before_count = history.size
before_tokens = approx_tokens(history)

puts "Before compression:"
puts "  Messages : #{before_count}"
puts "  ~Tokens  : #{before_tokens}"
puts

# ---------------------------------------------------------------------------
# Option A: Drop medium-relevance turns (no summarizer)
# ---------------------------------------------------------------------------
compressor_a = RobotLab::HistoryCompressor.new(
  messages:        history,
  recent_turns:    2,
  keep_threshold:  0.25,
  drop_threshold:  0.05,
  summarizer:      nil
)

result_a = compressor_a.call
tokens_a = approx_tokens(result_a)

puts "After compression (drop mode, recent_turns: 2, keep: 0.25, drop: 0.05):"
puts "  Messages : #{result_a.size}  (removed #{before_count - result_a.size})"
puts "  ~Tokens  : #{tokens_a}  (saved #{before_tokens - tokens_a})"
puts "  Kept roles: #{result_a.map(&:role).join(', ')}"
puts

# ---------------------------------------------------------------------------
# Option B: With a summarizer lambda for medium-relevance turns
# ---------------------------------------------------------------------------
puts "After compression (summarize mode, keep: 0.5, drop: 0.05):"

summarizer = lambda do |text|
  # In production this would call a small LLM robot.
  # Here we fake it by taking the first sentence.
  text.split(/[.!?]/).first.to_s.strip + "."
end

compressor_b = RobotLab::HistoryCompressor.new(
  messages:        history,
  recent_turns:    2,
  keep_threshold:  0.5,
  drop_threshold:  0.05,
  summarizer:      summarizer
)

result_b = compressor_b.call
tokens_b = approx_tokens(result_b)

puts "  Messages : #{result_b.size}  (removed #{before_count - result_b.size})"
puts "  ~Tokens  : #{tokens_b}  (saved #{before_tokens - tokens_b})"
puts "  Kept roles: #{result_b.map(&:role).join(', ')}"
puts

# ---------------------------------------------------------------------------
# Show the LLM summarizer pattern (not executed — requires API key)
# ---------------------------------------------------------------------------
puts "=" * 60
puts "LLM summarizer pattern (requires API key):"
puts "=" * 60
puts <<~RUBY

  summarizer_bot = RobotLab.build(
    name:          "summarizer",
    system_prompt: "Summarize the following text in one sentence."
  )

  robot.compress_history(
    recent_turns:    3,
    keep_threshold:  0.6,
    drop_threshold:  0.2,
    summarizer:      ->(text) { summarizer_bot.run("Summarize: \#{text}").reply }
  )

RUBY

puts "Done."
