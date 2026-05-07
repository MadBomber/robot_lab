#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 26: Embedding-Based Document Store
#
# Demonstrates Memory#store_document and Memory#search_documents — a
# lightweight RAG store backed by fastembed (BAAI/bge-small-en-v1.5).
#
# Documents are multi-paragraph engineering guides stored as Markdown files in:
#   examples/26_document_store/
#
# Usage:
#   ruby examples/26_document_store.rb
#   (Downloads the ~23 MB ONNX model on first run; cached afterwards.)

ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"
require "robot_lab/document_store"

puts "=" * 60
puts "Example 26: Embedding-Based Document Store"
puts "=" * 60
puts
puts "Note: First run downloads the fastembed model (~23 MB, cached)."
puts

# ---------------------------------------------------------------------------
# Load documents from the companion directory
# ---------------------------------------------------------------------------
DOC_DIR = File.join(__dir__, "26_document_store")

DOCUMENTS = Dir[File.join(DOC_DIR, "*.md")].sort.each_with_object({}) do |path, h|
  key = File.basename(path, ".md").to_sym
  h[key] = File.read(path)
end.freeze

# ---------------------------------------------------------------------------
# Store into a standalone DocumentStore
# ---------------------------------------------------------------------------
store = RobotLab::DocumentStore.new

print "Storing #{DOCUMENTS.size} documents... "
DOCUMENTS.each { |key, text| store.store(key, text) }
puts "done"
puts
DOCUMENTS.each { |key, text| puts "  #{key.to_s.ljust(24)} #{text.split.size} words" }
puts

# ---------------------------------------------------------------------------
# Queries — each phrased differently from the document content
# ---------------------------------------------------------------------------
QUERIES = [
  {
    label: "Database query performance",
    query: "Why is my Postgres query slow and how do I investigate it?",
    want:  :postgres_runbook
  },
  {
    label: "Background job failures during outage",
    query: "Jobs keep failing when Stripe is down. How do I stop them piling up?",
    want:  :sidekiq_guide
  },
  {
    label: "API breaking changes policy",
    query: "Can I rename a response field in the API without breaking clients?",
    want:  :api_versioning_adr
  },
  {
    label: "Cache expiry and memory pressure",
    query: "Redis is evicting keys unexpectedly and the cache hit rate has dropped.",
    want:  :redis_caching_guide
  },
  {
    label: "Production outage from table lock",
    query: "We had an outage caused by a database lock during a migration. What happened?",
    want:  :incident_postmortem
  },
  {
    label: "Semantic gap — no shared keywords",
    query: "Connection pool is full and new requests are being rejected.",
    want:  :postgres_runbook
  },
].freeze

QUERIES.each do |q|
  results = store.search(q[:query], limit: 3)
  top     = results.first
  verdict = top[:key] == q[:want] ? "✓ correct" : "✗ expected #{q[:want]}"

  puts "── #{q[:label]}"
  puts "   Query:      \"#{q[:query]}\""
  puts "   Top result: #{top[:key]} (#{format("%.3f", top[:score])}) — #{verdict}"
  puts "   Ranking:    " + results.map { |r| "#{r[:key]} #{format("%.3f", r[:score])}" }.join(" | ")
  puts
end

# ---------------------------------------------------------------------------
# Delete and verify
# ---------------------------------------------------------------------------
puts "── Delete :redis_caching_guide, re-run cache query"
store.delete(:redis_caching_guide)
results = store.search("Redis evicting keys unexpectedly", limit: 2)
puts "   Remaining keys: #{store.keys.inspect}"
puts "   Top result after deletion: #{results.first[:key]}"
puts

# ---------------------------------------------------------------------------
# Memory integration
# ---------------------------------------------------------------------------
puts "── Memory integration"
memory = RobotLab::Memory.new(enable_cache: false)

DOCUMENTS.each { |key, text| memory.store_document(key, text) }
puts "   Stored #{memory.document_keys.size} documents via memory.store_document"

hits = memory.search_documents("slow query bloat vacuum autovacuum", limit: 2)
puts "   Search 'slow query bloat vacuum autovacuum':"
hits.each { |h| puts "     #{h[:key]} (#{format("%.3f", h[:score])})" }

memory.delete_document(:postgres_runbook)
puts "   After delete, keys: #{memory.document_keys.inspect}"
puts

# ---------------------------------------------------------------------------
# RAG pattern
# ---------------------------------------------------------------------------
puts "=" * 60
puts "RAG Pattern: retrieve relevant docs, then generate with LLM"
puts "=" * 60
puts

rag_query = "Our Sidekiq jobs exhaust retries and land in the dead queue after a Stripe outage."

hits    = store.search(rag_query, limit: 2)
context = hits.map { |h| h[:text] }.join("\n\n---\n\n")

puts "User question:"
puts "  \"#{rag_query}\""
puts
puts "Retrieved #{hits.size} document(s) — #{context.split.size} words of context:"
hits.each { |h| puts "  #{h[:key]} (score #{format("%.3f", h[:score])})" }
puts
puts "LLM call would be:"
puts '  robot.run("Use the following docs:\n#{context}\n\nQuestion: #{rag_query}")'
puts

puts "Done."
