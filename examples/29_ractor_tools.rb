#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 29: Ractor-Safe CPU Tools
#
# Demonstrates Track 1 of RobotLab's Ractor parallelism: CPU-bound tools
# that bypass Ruby's GVL by running inside a pool of Ractor workers.
#
# Concepts covered:
#   - ractor_safe true  — opt a tool class into Ractor execution
#   - Inheritance       — subclasses inherit ractor_safe automatically
#   - RactorBoundary.freeze_deep — deep-freeze nested data before
#                         crossing the Ractor boundary
#   - RactorBoundaryError — raised for non-shareable values (Procs, IOs…)
#   - RactorWorkerPool  — global pool, submit jobs, read frozen results
#   - ToolError         — propagated when a tool raises inside a Ractor
#   - Parallel batch    — many threads submitting concurrently vs sequentially
#
# Usage (no LLM API key required):
#   bundle exec ruby examples/29_ractor_tools.rb
#
# Good to know:
#   Ractor dispatch has a fixed overhead of ~20 ms per job (reply-queue
#   Ractor creation + Ractor.make_shareable).  Computation must dominate
#   that overhead for parallelism to win.  HeavyDigestTool uses 500 000
#   SHA-256 rounds (~320 ms on modern hardware) so the 4-6× speedup is
#   clearly visible on a 6-core machine.

require_relative "common"
require "robot_lab/ractor"
require "digest"

# Always shut down the pool when the process exits.
at_exit { RobotLab.shutdown_ractor_pool }

# =============================================================================
# Tool definitions
# =============================================================================

# Base class — declare ractor_safe once; all subclasses inherit it.
class TextTool < RobotLab::Tool
  ractor_safe true
end

# Word and sentence statistics — pure computation, no shared state.
class WordStatsTool < TextTool
  description "Count words, sentences, and average word length"

  param :text, type: :string, desc: "Text to analyze"

  def execute(text:)
    words     = text.scan(/\b\w+\b/)
    sentences = [text.scan(/[.!?]+/).length, 1].max
    avg_len   = words.empty? ? 0.0 : (words.sum(&:length).to_f / words.length).round(2)

    { words: words.length, sentences: sentences, avg_word_len: avg_len }.freeze
  end
end

# Words-per-sentence and long-word density (a simple readability proxy).
class ReadabilityTool < TextTool
  description "Estimate words-per-sentence and long-word density"

  param :text, type: :string, desc: "Text to analyze"

  def execute(text:)
    words      = text.scan(/\b\w+\b/)
    sentences  = [text.scan(/[.!?]+/).length, 1].max
    long_words = words.count { |w| w.length > 6 }
    long_pct   = words.empty? ? 0 : (long_words * 100 / words.length)

    {
      words:              words.length,
      sentences:          sentences,
      words_per_sentence: (words.length.to_f / sentences).round(1),
      long_word_pct:      long_pct
    }.freeze
  end
end

# CPU-intensive: 500 000 SHA-256 rounds (~320 ms per job on modern hardware).
# The overhead of reply-queue Ractor creation + make_shareable is ~20 ms per job
# (constant), so computation must dwarf it to show a real speedup.
class HeavyDigestTool < TextTool
  description "SHA-256 chain (500 000 rounds) — CPU-intensive, Ractor-safe"

  ROUNDS = 500_000

  param :text, type: :string, desc: "Seed text"

  def execute(text:)
    digest = text
    ROUNDS.times { digest = Digest::SHA256.hexdigest(digest) }
    digest[0..15].freeze
  end
end

# NOT Ractor-safe: @@hits is mutable class-level state.
# Shown here purely as a contrast — do not submit this to the pool.
class RequestCounterTool < RobotLab::Tool
  description "Word count plus a mutable global call counter (not Ractor-safe)"

  @@hits = 0   # mutable class variable — Ractor workers cannot access this

  param :text, type: :string, desc: "Text to count"

  def execute(text:)
    @@hits += 1
    "#{text.scan(/\b\w+\b/).length} words (total calls: #{@@hits})"
  end
end

# =============================================================================
# Demo
# =============================================================================

banner "Ractor-Safe CPU Tools"

DIVIDER = ("─" * 54).freeze

SAMPLE_TEXTS = [
  "Ruby makes programmer happiness a first-class concern in language design.",
  "Ractors enable true CPU parallelism by isolating mutable state between actors.",
  "Every distributed system eventually becomes a consistency problem.",
  "The quick brown fox jumps over the lazy dog — a pangram.",
  "Machine learning transforms raw observations into actionable insight.",
  "Simplicity is the ultimate sophistication in software architecture."
].freeze

# ── 1. ractor_safe? flags ─────────────────────────────────────

puts "1.  ractor_safe? flags"
puts "    #{DIVIDER}"

{
  "WordStatsTool"     => WordStatsTool,
  "ReadabilityTool"   => ReadabilityTool,
  "HeavyDigestTool"   => HeavyDigestTool,
  "RequestCounterTool" => RequestCounterTool
}.each do |name, klass|
  mark = klass.ractor_safe ? "✓ ractor_safe (inherits from TextTool)" : "✗ NOT ractor_safe"
  puts "    #{name.ljust(22)}  #{mark}"
end
puts

# ── 2. RactorBoundary.freeze_deep ─────────────────────────────

puts "2.  RactorBoundary.freeze_deep"
puts "    #{DIVIDER}"

nested = { tags: ["ruby", "ractor"], meta: { version: 2 } }
frozen = RobotLab::RactorBoundary.freeze_deep(nested)

puts "    Input frozen?               #{nested.frozen?}"
puts "    Output frozen?              #{frozen.frozen?}"
puts "    Inner :tags array frozen?   #{frozen[:tags].frozen?}"
puts "    Inner :meta hash frozen?    #{frozen[:meta].frozen?}"
puts

# A Proc cannot cross a Ractor boundary — freeze_deep raises immediately.
require "stringio"
begin
  RobotLab::RactorBoundary.freeze_deep(StringIO.new("I cannot be frozen"))
rescue RobotLab::RactorBoundaryError => e
  puts "    RactorBoundaryError on StringIO:"
  puts "    #{e.message.split('.').first}."
end
puts

# ── 3. Single pool submissions ─────────────────────────────────

pool = RobotLab.ractor_pool
puts "3.  Worker pool  (#{pool.size} Ractors — one per CPU core)"
puts "    #{DIVIDER}"

sample = SAMPLE_TEXTS.first

r = pool.submit("WordStatsTool",   { text: sample })
puts "    WordStatsTool:   #{r.inspect}"

r = pool.submit("ReadabilityTool", { text: sample })
puts "    ReadabilityTool: words_per_sentence=#{r[:words_per_sentence]}  long_word_pct=#{r[:long_word_pct]}%"
puts

# ── 4. ToolError propagation ───────────────────────────────────

puts "4.  ToolError propagation"
puts "    #{DIVIDER}"
puts "    Submitting nil as :text (WordStatsTool will call nil.scan — NoMethodError)"
puts

begin
  pool.submit("WordStatsTool", { text: nil })
rescue RobotLab::ToolError => e
  puts "    RobotLab::ToolError caught:"
  puts "    #{e.message}"
end
puts

# ── 5. Parallel batch vs sequential ───────────────────────────

puts "5.  Parallel batch — #{SAMPLE_TEXTS.length} jobs, each doing #{HeavyDigestTool::ROUNDS.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1_').reverse} SHA-256 rounds"
puts "    #{DIVIDER}"

# Parallel: one Thread per job, all submitted simultaneously.
t0       = Process.clock_gettime(Process::CLOCK_MONOTONIC)
threads  = SAMPLE_TEXTS.map { |text| Thread.new { pool.submit("HeavyDigestTool", { text: text }) } }
parallel_results = threads.map(&:value)
parallel_time    = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

# Sequential: jobs submitted one-at-a-time from the main thread.
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
SAMPLE_TEXTS.each { |text| pool.submit("HeavyDigestTool", { text: text }) }
seq_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

puts "    Parallel  (#{SAMPLE_TEXTS.length} threads → #{pool.size} Ractors): #{"%.3f" % parallel_time}s"
puts "    Sequential (1 thread  → #{pool.size} Ractors): #{"%.3f" % seq_time}s"

if seq_time > parallel_time * 1.2
  puts "    Speedup: #{(seq_time / parallel_time).round(1)}×"
else
  puts "    Note: overhead (~20 ms/job for reply-queue Ractor + make_shareable)"
  puts "    dominated this run. Increase ROUNDS further to widen the gap."
end

puts
puts "    First result (truncated digest): #{parallel_results.first}"
puts

# ── 6. Shutdown ────────────────────────────────────────────────

puts "6.  Shutdown"
puts "    #{DIVIDER}"
RobotLab.shutdown_ractor_pool
puts "    Pool shut down cleanly (poison-pill × #{pool.size} workers)."
puts
hr
puts "Example 29 complete."
