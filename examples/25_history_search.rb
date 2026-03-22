#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 25: Chat History Search
#
# Demonstrates robot.search_history(query, limit:) — semantic search over a
# robot's accumulated conversation turns using stemmed term-frequency cosine
# similarity (classifier gem).
#
# The conversation fixture (30 turns across 5 topics) lives in:
#   examples/25_history_search/conversation.jsonl
#
# Usage:
#   ruby examples/25_history_search.rb

ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "prompts")

require "json"
require_relative "../lib/robot_lab"

CONVERSATION_TURNS = File.readlines(
  File.join(__dir__, "25_history_search", "conversation.jsonl"), chomp: true
).map { |line| JSON.parse(line, symbolize_names: true) }.freeze

puts "=" * 60
puts "Example 25: Chat History Search"
puts "=" * 60
puts

# ---------------------------------------------------------------------------
# Minimal message stub — populates history without LLM calls
# ---------------------------------------------------------------------------
FakeMsg = Struct.new(:role, :content, :tool_calls)

# ---------------------------------------------------------------------------
# Build a robot and inject the conversation fixture
# ---------------------------------------------------------------------------
robot = RobotLab.build(name: "tech_lead", system_prompt: "You are a senior engineering advisor.")

messages = CONVERSATION_TURNS.map { |t| FakeMsg.new(t[:role], t[:content], nil) }
robot.instance_variable_get(:@chat).instance_variable_set(:@messages, messages)

total_words = messages.sum { |m| m.content.to_s.split.size }
puts "Conversation loaded: #{messages.size} messages, ~#{total_words} words"
puts "Topics: database migration, API performance, deployment pipeline, background jobs, onboarding"
puts

# ---------------------------------------------------------------------------
# Helper: print search results
# ---------------------------------------------------------------------------
def show_results(results)
  results.each do |r|
    preview = r.text.length > 100 ? "#{r.text[0..97]}..." : r.text
    puts "  [#{r.role}] score=#{format("%.3f", r.score)} idx=#{r.index}"
    puts "    #{preview}"
  end
end

# ---------------------------------------------------------------------------
# Searches across four distinct topics
#
# Note on TF cosine artifacts (expected behavior, not bugs):
#
# 'deploy rollback production incident': the rollback playbook (idx=17) ranks
# 3rd rather than 1st. The short question "Should we do blue-green deploys?"
# (idx=18) beats it because "deploy" appears there and TF vectors over-weight
# single high-frequency query terms in short messages.
#
# 'caching Redis invalidation TTL': the Docker GHA cache step (idx=15) is a
# false positive at rank 3 — "cache" appears in that message. The Redis hits
# at ranks 1 and 2 are correct.
#
# These are genuine limitations of keyword-based cosine similarity. The results
# shown here are authentic, not cherry-picked.
# ---------------------------------------------------------------------------
{
  "database migration schema change postgres"    => 3,
  "slow API endpoint N+1 query performance"      => 3,
  "deploy rollback production incident"          => 3,
  "Sidekiq retry Stripe failed jobs dead queue"  => 3,
  "caching Redis invalidation TTL"               => 3,
}.each do |query, limit|
  puts "── Search: '#{query}'"
  show_results robot.search_history(query, limit: limit)
  puts
end

# ---------------------------------------------------------------------------
# RAG pattern — retrieve the most relevant turns, then inject as context
# ---------------------------------------------------------------------------
puts "── RAG pattern: retrieve context, then call LLM ────────────────"
puts "(showing retrieved context — no actual LLM call)"
puts

rag_query = "Sidekiq jobs exhausting retries during Stripe outage"
rag_hits  = robot.search_history(rag_query, limit: 3)
rag_ctx   = rag_hits.map(&:text).join("\n\n")

puts "Query:    \"#{rag_query}\""
puts "Retrieved #{rag_hits.size} turn(s) — #{rag_ctx.split.size} words"
puts "Scores:   #{rag_hits.map { |h| format("%.3f", h.score) }.join("  ")}"
puts "Token savings vs. full history: ~#{total_words} words → #{rag_ctx.split.size} words"
puts
puts "Top retrieved turn:"
puts "  \"#{rag_hits.first.text[0..110]}...\""
puts
puts "LLM call would be:"
puts '  robot.run("Prior context:\n#{context}\n\nQuestion: #{rag_query}")'
puts

# ---------------------------------------------------------------------------
# When to use search_history
# ---------------------------------------------------------------------------
puts "=" * 60
puts "When to use search_history"
puts "=" * 60
puts <<~'TEXT'

  Without search_history:
    robot.run(question)
    — full accumulated history sent to the LLM on every call
    — costs grow linearly with conversation length

  With search_history:
    hits    = robot.search_history(question, limit: 3)
    context = hits.map(&:text).join("\n\n")
    robot.run("Prior context:\n#{context}\n\nQuestion: #{question}")
    — only the N most relevant turns are injected
    — token cost stays flat regardless of history length
    — pairs well with compress_history

  Optional dependency: gem "classifier", "~> 2.3"

TEXT

puts "Done."
