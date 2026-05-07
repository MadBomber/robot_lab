# Durable Learning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add cross-session and within-session learning capability to RobotLab robots via a `Durable::Store`, two tools (`RecallKnowledge`, `RecordKnowledge`), an end-of-session `Durable::Reflector`, and a `Durable::Learning` mixin opt-in on `Robot`.

**Architecture:** Knowledge entries are structured YAML files in `~/.robot_lab/durable/` (one file per domain), read/written by `Durable::Store`. Robots that opt-in with `learn: true` get two tools and an end-of-session reflection pass. The existing `@learnings` / `learn()` / `inject_learnings` mechanism on `Robot` serves as the within-session layer; durable storage is the cross-session layer.

**Tech Stack:** Ruby `Data.define` (value objects), `YAML` stdlib, Minitest, Zeitwerk autoloading (files in `lib/robot_lab/durable/` auto-register as `RobotLab::Durable::*`).

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/robot_lab/durable/entry.rb` | `Entry` value object — one knowledge record |
| Create | `lib/robot_lab/durable/store.rb` | Read/write/confirm YAML domain files |
| Create | `lib/robot_lab/durable/reflector.rb` | Promote session learnings to store at session end |
| Create | `lib/robot_lab/durable/learning.rb` | `Learning` mixin — wires everything to Robot |
| Create | `lib/robot_lab/recall_knowledge.rb` | `RecallKnowledge` tool — query store before deciding |
| Create | `lib/robot_lab/record_knowledge.rb` | `RecordKnowledge` tool — write to store during session |
| Create | `test/robot_lab/durable/entry_test.rb` | Unit tests for `Entry` |
| Create | `test/robot_lab/durable/store_test.rb` | Unit tests for `Store` |
| Create | `test/robot_lab/durable/reflector_test.rb` | Unit tests for `Reflector` |
| Create | `test/robot_lab/recall_knowledge_test.rb` | Unit tests for `RecallKnowledge` |
| Create | `test/robot_lab/record_knowledge_test.rb` | Unit tests for `RecordKnowledge` |
| Modify | `lib/robot_lab/robot.rb` | Add `learn:`, `learn_domain:`, `durable_store` |
| Modify | `examples/32_newsletter_reader.rb` | Add `learn: true, learn_domain: "newsletter curation"` |

---

## Task 1: `Durable::Entry`

**Files:**
- Create: `lib/robot_lab/durable/entry.rb`
- Create: `test/robot_lab/durable/entry_test.rb`

- [ ] **Step 1: Create the test file**

```ruby
# test/robot_lab/durable/entry_test.rb
# frozen_string_literal: true

require "test_helper"

class RobotLab::Durable::EntryTest < Minitest::Test
  def build_entry(overrides = {})
    RobotLab::Durable::Entry.new(
      content:    overrides.fetch(:content,    "Skip LangChain content"),
      reasoning:  overrides.fetch(:reasoning,  "User is Ruby-only"),
      category:   overrides.fetch(:category,   :preference),
      domain:     overrides.fetch(:domain,     "newsletter curation"),
      confidence: overrides.fetch(:confidence, 0.1),
      use_count:  overrides.fetch(:use_count,  0),
      created_at: overrides.fetch(:created_at, "2026-05-06T12:00:00Z"),
      updated_at: overrides.fetch(:updated_at, "2026-05-06T12:00:00Z")
    )
  end

  def test_entry_is_immutable
    entry = build_entry
    assert_raises(NoMethodError) { entry.content = "changed" }
  end

  def test_confirm_increments_confidence_by_0_1
    entry = build_entry(confidence: 0.2, use_count: 1)
    confirmed = entry.confirm
    assert_in_delta 0.3, confirmed.confidence, 0.001
  end

  def test_confirm_increments_use_count
    entry = build_entry(use_count: 3)
    confirmed = entry.confirm
    assert_equal 4, confirmed.use_count
  end

  def test_confirm_does_not_exceed_max_confidence
    entry = build_entry(confidence: 0.95)
    confirmed = entry.confirm
    assert_in_delta 1.0, confirmed.confidence, 0.001
    confirmed2 = confirmed.confirm
    assert_in_delta 1.0, confirmed2.confidence, 0.001
  end

  def test_confirm_returns_new_entry_leaves_original_unchanged
    entry = build_entry(confidence: 0.1)
    entry.confirm
    assert_in_delta 0.1, entry.confidence, 0.001
  end

  def test_to_h_returns_string_keys
    entry = build_entry
    h = entry.to_h
    assert_equal "Skip LangChain content", h["content"]
    assert_equal "preference",             h["category"]
    assert_in_delta 0.1,                   h["confidence"], 0.001
  end

  def test_from_h_with_string_keys
    h = {
      "content"    => "Skip LangChain content",
      "reasoning"  => "User is Ruby-only",
      "category"   => "preference",
      "domain"     => "newsletter curation",
      "confidence" => 0.2,
      "use_count"  => 1,
      "created_at" => "2026-05-06T12:00:00Z",
      "updated_at" => "2026-05-06T12:00:00Z"
    }
    entry = RobotLab::Durable::Entry.from_h(h)
    assert_equal "Skip LangChain content", entry.content
    assert_equal :preference,              entry.category
    assert_in_delta 0.2,                   entry.confidence, 0.001
  end

  def test_from_h_roundtrips_through_to_h
    original = build_entry(confidence: 0.4, use_count: 2)
    roundtripped = RobotLab::Durable::Entry.from_h(original.to_h)
    assert_equal original.content,    roundtripped.content
    assert_equal original.reasoning,  roundtripped.reasoning
    assert_equal original.category,   roundtripped.category
    assert_in_delta original.confidence, roundtripped.confidence, 0.001
    assert_equal original.use_count,  roundtripped.use_count
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bundle exec rake test_file[robot_lab/durable/entry_test.rb]
```

Expected: `NameError: uninitialized constant RobotLab::Durable` or similar failure.

- [ ] **Step 3: Create `lib/robot_lab/durable/entry.rb`**

```ruby
# lib/robot_lab/durable/entry.rb
# frozen_string_literal: true

module RobotLab
  module Durable
    Entry = Data.define(:content, :reasoning, :category, :domain, :confidence, :use_count, :created_at, :updated_at) do
      CONFIDENCE_INCREMENT = 0.1
      MAX_CONFIDENCE       = 1.0

      # Return a new Entry with confidence incremented and use_count bumped.
      def confirm
        new_confidence = [confidence + CONFIDENCE_INCREMENT, MAX_CONFIDENCE].min
        with(
          confidence: new_confidence.round(10),
          use_count:  use_count + 1,
          updated_at: Time.now.iso8601
        )
      end

      # Serialize to a plain Hash with string keys (safe for YAML round-trip).
      def to_h
        {
          "content"    => content,
          "reasoning"  => reasoning,
          "category"   => category.to_s,
          "domain"     => domain,
          "confidence" => confidence,
          "use_count"  => use_count,
          "created_at" => created_at,
          "updated_at" => updated_at
        }
      end

      # Deserialize from a Hash (string or symbol keys).
      def self.from_h(hash)
        new(
          content:    hash["content"]    || hash[:content],
          reasoning:  hash["reasoning"]  || hash[:reasoning],
          category:   (hash["category"] || hash[:category]).to_sym,
          domain:     hash["domain"]     || hash[:domain],
          confidence: (hash["confidence"] || hash[:confidence]).to_f,
          use_count:  (hash["use_count"]  || hash[:use_count]).to_i,
          created_at: hash["created_at"] || hash[:created_at],
          updated_at: hash["updated_at"] || hash[:updated_at]
        )
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rake test_file[robot_lab/durable/entry_test.rb]
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/durable/entry.rb test/robot_lab/durable/entry_test.rb
git commit -m "feat(durable): add Durable::Entry value object"
```

---

## Task 2: `Durable::Store`

**Files:**
- Create: `lib/robot_lab/durable/store.rb`
- Create: `test/robot_lab/durable/store_test.rb`

- [ ] **Step 1: Create the test file**

```ruby
# test/robot_lab/durable/store_test.rb
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RobotLab::Durable::StoreTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("robot_lab_durable_test")
    @store  = RobotLab::Durable::Store.new(path: @tmpdir)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def build_entry(overrides = {})
    RobotLab::Durable::Entry.new(
      content:    overrides.fetch(:content,    "Skip LangChain content"),
      reasoning:  overrides.fetch(:reasoning,  "User is Ruby-only"),
      category:   overrides.fetch(:category,   :preference),
      domain:     overrides.fetch(:domain,     "newsletter curation"),
      confidence: overrides.fetch(:confidence, 0.1),
      use_count:  overrides.fetch(:use_count,  0),
      created_at: "2026-05-06T12:00:00Z",
      updated_at: "2026-05-06T12:00:00Z"
    )
  end

  # ── record ────────────────────────────────────────────────

  def test_record_persists_entry_to_disk
    entry = build_entry
    @store.record(entry)

    file = File.join(@tmpdir, "newsletter_curation.yaml")
    assert File.exist?(file)
  end

  def test_record_appends_new_entry
    @store.record(build_entry(content: "First"))
    @store.record(build_entry(content: "Second"))

    entries = @store.recall(query: "newsletter", domain: "newsletter curation")
    assert_equal 2, entries.size
  end

  def test_record_updates_existing_entry_by_content_match
    @store.record(build_entry(content: "Skip LangChain content", confidence: 0.1))
    @store.record(build_entry(content: "Skip LangChain content", confidence: 0.1))

    entries = @store.recall(query: "LangChain", domain: "newsletter curation")
    assert_equal 1, entries.size
  end

  def test_record_increments_confidence_on_duplicate
    @store.record(build_entry(content: "Skip LangChain content", confidence: 0.1))
    @store.record(build_entry(content: "Skip LangChain content", confidence: 0.1))

    entries = @store.recall(query: "LangChain", domain: "newsletter curation")
    assert_in_delta 0.2, entries.first.confidence, 0.001
  end

  # ── recall ────────────────────────────────────────────────

  def test_recall_returns_empty_array_when_no_entries
    results = @store.recall(query: "anything", domain: "newsletter curation")
    assert_empty results
  end

  def test_recall_matches_on_content_keyword
    @store.record(build_entry(content: "Skip LangChain tutorials"))
    results = @store.recall(query: "LangChain", domain: "newsletter curation")
    assert_equal 1, results.size
    assert_equal "Skip LangChain tutorials", results.first.content
  end

  def test_recall_is_case_insensitive
    @store.record(build_entry(content: "Skip langchain tutorials"))
    results = @store.recall(query: "LangChain", domain: "newsletter curation")
    assert_equal 1, results.size
  end

  def test_recall_filters_by_min_confidence
    @store.record(build_entry(content: "Low confidence entry",  confidence: 0.1))
    @store.record(build_entry(content: "High confidence entry", confidence: 0.8))

    results = @store.recall(query: "confidence entry", domain: "newsletter curation", min_confidence: 0.5)
    assert_equal 1, results.size
    assert_equal "High confidence entry", results.first.content
  end

  def test_recall_sorts_by_descending_confidence
    @store.record(build_entry(content: "Low entry",  confidence: 0.2))
    @store.record(build_entry(content: "High entry", confidence: 0.8))

    results = @store.recall(query: "entry", domain: "newsletter curation")
    assert_equal "High entry", results.first.content
  end

  def test_recall_without_domain_searches_all_domains
    @store.record(build_entry(domain: "newsletter curation", content: "Newsletter fact"))
    @store.record(build_entry(domain: "ruby tooling",        content: "Tooling fact"))

    results = @store.recall(query: "fact")
    assert_equal 2, results.size
  end

  # ── confirm ───────────────────────────────────────────────

  def test_confirm_increments_confidence_on_disk
    entry = @store.record(build_entry(confidence: 0.2))
    @store.confirm(entry)

    results = @store.recall(query: "LangChain", domain: "newsletter curation")
    assert_in_delta 0.3, results.first.confidence, 0.001
  end

  # ── domain file naming ────────────────────────────────────

  def test_spaces_in_domain_become_underscores_in_filename
    @store.record(build_entry(domain: "newsletter curation"))
    assert File.exist?(File.join(@tmpdir, "newsletter_curation.yaml"))
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bundle exec rake test_file[robot_lab/durable/store_test.rb]
```

Expected: `NameError: uninitialized constant RobotLab::Durable::Store`.

- [ ] **Step 3: Create `lib/robot_lab/durable/store.rb`**

```ruby
# lib/robot_lab/durable/store.rb
# frozen_string_literal: true

require "yaml"
require "fileutils"

module RobotLab
  module Durable
    class Store
      DEFAULT_PATH = File.join(Dir.home, ".robot_lab", "durable")

      def initialize(path: DEFAULT_PATH)
        @path = path
        FileUtils.mkdir_p(@path)
      end

      # Return entries matching query keywords, sorted by descending confidence.
      #
      # @param query [String] natural-language search string
      # @param domain [String, nil] restrict to one domain file; nil searches all
      # @param min_confidence [Float] exclude entries below this threshold
      # @return [Array<Entry>]
      def recall(query:, domain: nil, min_confidence: 0.0)
        entries = domain ? load_domain(domain) : load_all
        words   = tokenize(query)

        entries
          .select { |e| e.confidence >= min_confidence }
          .select { |e| matches?(e, words) }
          .sort_by { |e| -e.confidence }
      end

      # Persist a new entry. If an entry with the same content already exists
      # in the domain file, increment its confidence and use_count instead.
      #
      # @param entry [Entry]
      # @return [Entry] the stored entry (may differ if an existing one was updated)
      def record(entry)
        entries = load_domain(entry.domain)
        idx     = entries.find_index { |e| e.content.downcase == entry.content.downcase }

        if idx
          entries[idx] = entries[idx].confirm
        else
          entries << entry
        end

        save_domain(entry.domain, entries)
        entries[idx || -1]
      end

      # Increment confidence and use_count on a stored entry.
      #
      # @param entry [Entry]
      # @return [Entry] the updated entry
      def confirm(entry)
        updated = entry.confirm
        record_exact(updated)
        updated
      end

      private

      def matches?(entry, words)
        text = "#{entry.content} #{entry.domain}".downcase
        words.any? { |w| text.include?(w) }
      end

      def tokenize(str)
        str.downcase.split(/\s+/).reject { |w| w.length < 3 }
      end

      def load_domain(domain)
        file = domain_file(domain)
        return [] unless File.exist?(file)

        raw = YAML.safe_load(File.read(file)) || []
        raw.map { |h| Entry.from_h(h) }
      end

      def load_all
        Dir.glob(File.join(@path, "*.yaml")).flat_map do |file|
          raw = YAML.safe_load(File.read(file)) || []
          raw.map { |h| Entry.from_h(h) }
        end
      end

      def save_domain(domain, entries)
        File.write(domain_file(domain), YAML.dump(entries.map(&:to_h)))
      end

      # Replace a specific entry by exact content match (used by confirm).
      def record_exact(entry)
        entries = load_domain(entry.domain)
        idx     = entries.find_index { |e| e.content.downcase == entry.content.downcase }
        entries[idx] = entry if idx
        save_domain(entry.domain, entries)
      end

      def domain_file(domain)
        filename = domain.to_s.downcase.gsub(/\s+/, "_") + ".yaml"
        File.join(@path, filename)
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rake test_file[robot_lab/durable/store_test.rb]
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/durable/store.rb test/robot_lab/durable/store_test.rb
git commit -m "feat(durable): add Durable::Store for YAML-backed knowledge persistence"
```

---

## Task 3: `RecordKnowledge` Tool

**Files:**
- Create: `lib/robot_lab/record_knowledge.rb`
- Create: `test/robot_lab/record_knowledge_test.rb`

- [ ] **Step 1: Create the test file**

```ruby
# test/robot_lab/record_knowledge_test.rb
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RobotLab::RecordKnowledgeTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("robot_lab_record_test")
    @store  = RobotLab::Durable::Store.new(path: @tmpdir)
    @robot  = build_robot(name: "test_bot")
    @robot.instance_variable_set(:@durable_store, @store)
    @tool   = RobotLab::RecordKnowledge.new(robot: @robot)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_records_entry_to_store
    @tool.execute(
      content:   "Skip Python-only tools",
      reasoning: "User works exclusively in Ruby",
      category:  "preference",
      domain:    "newsletter curation"
    )

    results = @store.recall(query: "Python", domain: "newsletter curation")
    assert_equal 1, results.size
    assert_equal "Skip Python-only tools", results.first.content
  end

  def test_returns_confirmation_string
    result = @tool.execute(
      content:   "Prefer gems with low dependency count",
      reasoning: "User values minimal dependency footprint",
      category:  "preference",
      domain:    "newsletter curation"
    )

    assert_match(/Recorded/, result)
    assert_match(/dependency/, result)
  end

  def test_adds_learning_to_robot
    @tool.execute(
      content:   "Include RubyLLM news",
      reasoning: "User maintains RubyLLM integrations",
      category:  "preference",
      domain:    "newsletter curation"
    )

    assert @robot.learnings.any? { |l| l.include?("RubyLLM") }
  end

  def test_returns_error_when_no_store_configured
    @robot.instance_variable_set(:@durable_store, nil)
    result = @tool.execute(
      content: "anything", reasoning: "any", category: "fact", domain: "test"
    )
    assert_match(/No durable store/, result)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bundle exec rake test_file[robot_lab/record_knowledge_test.rb]
```

Expected: `NameError: uninitialized constant RobotLab::RecordKnowledge`.

- [ ] **Step 3: Create `lib/robot_lab/record_knowledge.rb`**

```ruby
# lib/robot_lab/record_knowledge.rb
# frozen_string_literal: true

module RobotLab
  class RecordKnowledge < Tool
    description "Record a piece of knowledge learned during this session. " \
                "Use after a decision or discussion reveals something worth remembering: " \
                "a user preference, a reliable pattern, or a factual insight. " \
                "Recorded knowledge persists across future sessions."

    param :content,   type: "string", desc: "The knowledge to record, in plain language (one clear statement)"
    param :reasoning, type: "string", desc: "Why this is worth remembering — the observation or discussion that led to it"
    param :category,  type: "string", desc: "One of: fact, preference, pattern, correction"
    param :domain,    type: "string", desc: "Topic area this applies to (e.g. 'newsletter curation', 'ruby tooling')"

    def execute(content:, reasoning:, category:, domain:)
      store = robot&.durable_store
      return "No durable store configured on this robot." unless store

      entry = Durable::Entry.new(
        content:,
        reasoning:,
        category:   category.to_sym,
        domain:,
        confidence: 0.1,
        use_count:  0,
        created_at: Time.now.iso8601,
        updated_at: Time.now.iso8601
      )

      store.record(entry)
      robot.learn("#{content} (#{domain})")

      "Recorded: #{content}"
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rake test_file[robot_lab/record_knowledge_test.rb]
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/record_knowledge.rb test/robot_lab/record_knowledge_test.rb
git commit -m "feat(durable): add RecordKnowledge tool"
```

---

## Task 4: `RecallKnowledge` Tool

**Files:**
- Create: `lib/robot_lab/recall_knowledge.rb`
- Create: `test/robot_lab/recall_knowledge_test.rb`

- [ ] **Step 1: Create the test file**

```ruby
# test/robot_lab/recall_knowledge_test.rb
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RobotLab::RecallKnowledgeTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("robot_lab_recall_test")
    @store  = RobotLab::Durable::Store.new(path: @tmpdir)
    @robot  = build_robot(name: "test_bot")
    @robot.instance_variable_set(:@durable_store, @store)
    @tool   = RobotLab::RecallKnowledge.new(robot: @robot)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def seed_entry(content:, confidence: 0.5, domain: "newsletter curation")
    @store.record(
      RobotLab::Durable::Entry.new(
        content:,
        reasoning:  "seeded in test",
        category:   :preference,
        domain:,
        confidence:,
        use_count:  0,
        created_at: "2026-05-06T12:00:00Z",
        updated_at: "2026-05-06T12:00:00Z"
      )
    )
  end

  def test_returns_matching_entries_as_formatted_string
    seed_entry(content: "Skip LangChain tutorials")

    result = @tool.execute(query: "LangChain", domain: "newsletter curation")

    assert_match(/Skip LangChain tutorials/, result)
    assert_match(/Relevant past knowledge/, result)
  end

  def test_returns_no_match_message_when_empty
    result = @tool.execute(query: "LangChain", domain: "newsletter curation")
    assert_match(/No relevant past knowledge/, result)
  end

  def test_increments_confidence_on_recall
    seed_entry(content: "Skip LangChain tutorials", confidence: 0.3)
    @tool.execute(query: "LangChain", domain: "newsletter curation")

    results = @store.recall(query: "LangChain", domain: "newsletter curation")
    assert_in_delta 0.4, results.first.confidence, 0.001
  end

  def test_returns_error_when_no_store_configured
    @robot.instance_variable_set(:@durable_store, nil)
    result = @tool.execute(query: "anything")
    assert_match(/No durable store/, result)
  end

  def test_includes_category_and_confidence_in_output
    seed_entry(content: "Include RubyLLM updates", confidence: 0.6)
    result = @tool.execute(query: "RubyLLM", domain: "newsletter curation")
    assert_match(/preference/, result)
    assert_match(/0\./, result)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bundle exec rake test_file[robot_lab/recall_knowledge_test.rb]
```

Expected: `NameError: uninitialized constant RobotLab::RecallKnowledge`.

- [ ] **Step 3: Create `lib/robot_lab/recall_knowledge.rb`**

```ruby
# lib/robot_lab/recall_knowledge.rb
# frozen_string_literal: true

module RobotLab
  class RecallKnowledge < Tool
    description "Recall relevant knowledge from past sessions before making a decision. " \
                "Use this when uncertain whether to include or skip content, or when you want " \
                "to check if you have seen a similar situation before. " \
                "When in doubt and no relevant knowledge is found, skip the action."

    param :query,  type: "string", desc: "Natural language description of the decision you are about to make"
    param :domain, type: "string", desc: "Topic area to search (e.g. 'newsletter curation')", required: false

    def execute(query:, domain: nil)
      store = robot&.durable_store
      return "No durable store configured on this robot." unless store

      entries = store.recall(query: query, domain: domain, min_confidence: 0.0)

      if entries.empty?
        "No relevant past knowledge found for: #{query}. When in doubt, skip."
      else
        entries.each { |e| store.confirm(e) }

        lines = entries.map do |e|
          "[#{e.category}/conf:#{format("%.1f", e.confidence)}] #{e.content} — #{e.reasoning}"
        end

        "Relevant past knowledge:\n#{lines.join("\n")}"
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rake test_file[robot_lab/recall_knowledge_test.rb]
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/recall_knowledge.rb test/robot_lab/recall_knowledge_test.rb
git commit -m "feat(durable): add RecallKnowledge tool"
```

---

## Task 5: `Durable::Reflector`

**Files:**
- Create: `lib/robot_lab/durable/reflector.rb`
- Create: `test/robot_lab/durable/reflector_test.rb`

- [ ] **Step 1: Create the test file**

```ruby
# test/robot_lab/durable/reflector_test.rb
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RobotLab::Durable::ReflectorTest < Minitest::Test
  def setup
    @tmpdir    = Dir.mktmpdir("robot_lab_reflector_test")
    @store     = RobotLab::Durable::Store.new(path: @tmpdir)
    @reflector = RobotLab::Durable::Reflector.new(store: @store, domain: "newsletter curation")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_promotes_new_learning_to_store
    @reflector.reflect(["User prefers practical tooling examples"])

    results = @store.recall(query: "practical tooling", domain: "newsletter curation")
    assert_equal 1, results.size
    assert_equal "User prefers practical tooling examples", results.first.content
  end

  def test_does_not_duplicate_existing_entry
    @store.record(
      RobotLab::Durable::Entry.new(
        content:    "User prefers practical tooling examples",
        reasoning:  "already stored",
        category:   :pattern,
        domain:     "newsletter curation",
        confidence: 0.3,
        use_count:  2,
        created_at: "2026-05-06T12:00:00Z",
        updated_at: "2026-05-06T12:00:00Z"
      )
    )

    @reflector.reflect(["User prefers practical tooling examples"])

    results = @store.recall(query: "practical tooling", domain: "newsletter curation")
    assert_equal 1, results.size
  end

  def test_promotes_multiple_learnings
    @reflector.reflect(["First insight", "Second insight"])

    r1 = @store.recall(query: "First insight",  domain: "newsletter curation")
    r2 = @store.recall(query: "Second insight", domain: "newsletter curation")
    assert_equal 1, r1.size
    assert_equal 1, r2.size
  end

  def test_skips_empty_learnings
    @reflector.reflect(["", "  ", nil].compact)

    results = @store.recall(query: "anything", domain: "newsletter curation")
    assert_empty results
  end

  def test_new_entries_start_with_low_confidence
    @reflector.reflect(["Something worth knowing"])

    results = @store.recall(query: "worth knowing", domain: "newsletter curation")
    assert_in_delta 0.1, results.first.confidence, 0.001
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bundle exec rake test_file[robot_lab/durable/reflector_test.rb]
```

Expected: `NameError: uninitialized constant RobotLab::Durable::Reflector`.

- [ ] **Step 3: Create `lib/robot_lab/durable/reflector.rb`**

```ruby
# lib/robot_lab/durable/reflector.rb
# frozen_string_literal: true

module RobotLab
  module Durable
    class Reflector
      def initialize(store:, domain:)
        @store  = store
        @domain = domain.to_s
      end

      # Examine plain-text learnings accumulated during a session and promote
      # any that are not already represented in the store.
      #
      # @param learnings [Array<String>] robot.learnings from the completed session
      def reflect(learnings)
        learnings.each do |text|
          next if text.nil? || text.strip.empty?

          text = text.strip
          next if already_stored?(text)

          @store.record(
            Entry.new(
              content:    text,
              reasoning:  "Observed during session (auto-promoted by Reflector)",
              category:   :pattern,
              domain:     @domain,
              confidence: 0.1,
              use_count:  0,
              created_at: Time.now.iso8601,
              updated_at: Time.now.iso8601
            )
          )
        end
      end

      private

      def already_stored?(text)
        words = text.downcase.split(/\s+/).reject { |w| w.length < 4 }
        return false if words.empty?

        @store.recall(query: text, domain: @domain, min_confidence: 0.0).any? do |e|
          e.content.downcase == text.downcase
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rake test_file[robot_lab/durable/reflector_test.rb]
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/durable/reflector.rb test/robot_lab/durable/reflector_test.rb
git commit -m "feat(durable): add Durable::Reflector for end-of-session learning promotion"
```

---

## Task 6: `Durable::Learning` Mixin

**Files:**
- Create: `lib/robot_lab/durable/learning.rb`

- [ ] **Step 1: Create `lib/robot_lab/durable/learning.rb`**

No separate test file — integration is tested via Robot in Task 7.

```ruby
# lib/robot_lab/durable/learning.rb
# frozen_string_literal: true

module RobotLab
  module Durable
    module Learning
      def self.included(base)
        base.attr_reader :durable_store, :learn_domain
      end

      # Configure durable learning on a robot after initialization.
      #
      # @param domain [String] topic area for this robot's knowledge
      # @param store_path [String, nil] override default ~/.robot_lab/durable path
      def setup_durable_learning(domain:, store_path: nil)
        @learn_domain = domain.to_s
        opts          = store_path ? { path: store_path } : {}
        @durable_store = Store.new(**opts)

        seed_from_store
        @local_tools = (@local_tools + [RecallKnowledge, RecordKnowledge]).uniq
      end

      # Run the end-of-session reflection pass.
      # Called automatically from Robot#run when durable learning is active.
      def run_reflector
        return unless @durable_store && @learn_domain && @learnings&.any?

        Reflector.new(store: @durable_store, domain: @learn_domain).reflect(@learnings)
      end

      private

      def seed_from_store
        return unless @durable_store && @learn_domain

        entries = @durable_store.recall(query: @learn_domain, domain: @learn_domain, min_confidence: 0.0)
        entries.each do |e|
          learn("[#{e.category}] #{e.content}: #{e.reasoning}")
        end
      end
    end
  end
end
```

- [ ] **Step 2: Run the full test suite to verify nothing is broken**

```bash
bundle exec rake test
```

Expected: all existing tests still pass.

- [ ] **Step 3: Commit**

```bash
git add lib/robot_lab/durable/learning.rb
git commit -m "feat(durable): add Durable::Learning mixin"
```

---

## Task 7: Robot Integration

**Files:**
- Modify: `lib/robot_lab/robot.rb`
- Create: `test/robot_lab/robot/durable_learning_test.rb`

- [ ] **Step 1: Create the integration test**

```ruby
# test/robot_lab/robot/durable_learning_test.rb
# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RobotLab::Robot::DurableLearningTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("robot_lab_robot_durable_test")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_learn_false_does_not_set_durable_store
    robot = RobotLab::Robot.new(name: "no_learn", template: :assistant)
    assert_nil robot.durable_store
  end

  def test_learn_true_sets_durable_store
    robot = RobotLab::Robot.new(
      name:         "learner",
      template:     :assistant,
      learn:        true,
      learn_domain: "test domain",
      store_path:   @tmpdir
    )
    refute_nil robot.durable_store
  end

  def test_learn_true_adds_recall_and_record_tools
    robot = RobotLab::Robot.new(
      name:         "learner",
      template:     :assistant,
      learn:        true,
      learn_domain: "test domain",
      store_path:   @tmpdir
    )
    tool_names = robot.local_tools.map { |t| t.is_a?(Class) ? t.name : t.class.name }
    assert tool_names.any? { |n| n.include?("RecallKnowledge") }
    assert tool_names.any? { |n| n.include?("RecordKnowledge") }
  end

  def test_learn_true_seeds_learnings_from_existing_store
    store = RobotLab::Durable::Store.new(path: @tmpdir)
    store.record(
      RobotLab::Durable::Entry.new(
        content:    "Skip Python-only tools",
        reasoning:  "Ruby-only context",
        category:   :preference,
        domain:     "test domain",
        confidence: 0.5,
        use_count:  2,
        created_at: "2026-05-06T12:00:00Z",
        updated_at: "2026-05-06T12:00:00Z"
      )
    )

    robot = RobotLab::Robot.new(
      name:         "learner",
      template:     :assistant,
      learn:        true,
      learn_domain: "test domain",
      store_path:   @tmpdir
    )

    assert robot.learnings.any? { |l| l.include?("Skip Python-only tools") }
  end

  def test_learn_domain_readable
    robot = RobotLab::Robot.new(
      name:         "learner",
      template:     :assistant,
      learn:        true,
      learn_domain: "newsletter curation",
      store_path:   @tmpdir
    )
    assert_equal "newsletter curation", robot.learn_domain
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bundle exec rake test_file[robot_lab/robot/durable_learning_test.rb]
```

Expected: failures — `learn:` param not yet accepted.

- [ ] **Step 3: Modify `lib/robot_lab/robot.rb` — include the mixin**

Add after the existing `include Robot::HistorySearch` line (around line 8):

```ruby
include Durable::Learning
```

- [ ] **Step 4: Modify `lib/robot_lab/robot.rb` — add constructor params**

In the `initialize` parameter list (after `config: nil`), add:

```ruby
learn: false,
learn_domain: nil,
store_path: nil,
```

- [ ] **Step 5: Modify `lib/robot_lab/robot.rb` — call setup in initialize body**

After the line `@learnings = Array(persisted) if persisted` (around line 202), add:

```ruby
if learn && learn_domain
  setup_durable_learning(domain: learn_domain, store_path: store_path)
end
```

- [ ] **Step 6: Modify `lib/robot_lab/robot.rb` — call reflector in run**

In the `run` method's `ensure` block (near the end), after `restore_tool_call_callback` add:

```ruby
run_reflector if @durable_store
```

- [ ] **Step 7: Run the integration tests**

```bash
bundle exec rake test_file[robot_lab/robot/durable_learning_test.rb]
```

Expected: all green.

- [ ] **Step 8: Run the full suite**

```bash
bundle exec rake test
```

Expected: all existing tests still pass.

- [ ] **Step 9: Commit**

```bash
git add lib/robot_lab/robot.rb test/robot_lab/robot/durable_learning_test.rb
git commit -m "feat(durable): integrate Durable::Learning into Robot via learn: param"
```

---

## Task 8: Update Newsletter Reader Example

**Files:**
- Modify: `examples/32_newsletter_reader.rb`

- [ ] **Step 1: Update the robot constructor in the example**

Replace:

```ruby
robot = RobotLab.build(
  name: "newsletter_analyst",
  system_prompt: <<~PROMPT,
    ...
  PROMPT
  local_tools: [FetchLatestNewsletter],
  model: "claude-haiku-4-5-20251001"
)
```

With:

```ruby
robot = RobotLab.build(
  name:         "newsletter_analyst",
  system_prompt: <<~PROMPT,
    You are a sharp technical editor summarizing the RoboRuby Ruby AI newsletter
    for busy developers. When given newsletter content, extract and present:

    1. **Headline story** — the biggest news in Ruby/AI this issue.
    2. **Notable gems or tools** — new or updated libraries worth knowing about.
    3. **Key articles or tutorials** — important reads linked in the issue.
    4. **Quick takes** — 3-5 bullets on other interesting items.

    The content includes Markdown links in [text](url) format. You MUST preserve
    these links in your output — every article title, gem name, and tool mentioned
    should be a clickable Markdown link using the URL from the source content.

    Before deciding what to include, use RecallKnowledge to check past preferences.
    When you notice something new about what content resonates, use RecordKnowledge.
    When uncertain whether to include something and no past knowledge applies, skip it.

    Use the FetchLatestNewsletter tool to get the content, then give your summary.
    Be concise and opinionated — developers are busy.
  PROMPT
  local_tools:  [FetchLatestNewsletter],
  model:        "claude-haiku-4-5-20251001",
  learn:        true,
  learn_domain: "newsletter curation"
)
```

- [ ] **Step 2: Verify the example loads without error**

```bash
ruby -c examples/32_newsletter_reader.rb
```

Expected: `Syntax OK`.

- [ ] **Step 3: Commit**

```bash
git add examples/32_newsletter_reader.rb
git commit -m "feat(examples): add durable learning to newsletter reader robot"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| `Durable::Entry` — content, reasoning, category, domain, confidence, use_count | Task 1 |
| `Durable::Store` — recall, record, confirm, YAML files per domain | Task 2 |
| `RecordKnowledge` tool — write to store + update learnings | Task 3 |
| `RecallKnowledge` tool — read from store, confirm on recall | Task 4 |
| `Durable::Reflector` — promote session learnings at session end | Task 5 |
| `Durable::Learning` mixin — wire tools + seed + reflector hook | Task 6 |
| Robot `learn:`, `learn_domain:` params, `durable_store` reader | Task 7 |
| Conservative bias: when no match + uncertainty, skip | Baked into RecallKnowledge output string and system prompt guidance |
| Newsletter reader updated with `learn: true` | Task 8 |
| Confidence starts at 0.1, increments 0.1 per confirmation | Task 1 (`Entry#confirm`) |
| Cross-session: `~/.robot_lab/durable/` default path | Task 2 (`Store::DEFAULT_PATH`) |
| Within-session: existing `@learnings` / `learn()` mechanism reused | Task 6 (`seed_from_store`, `run_reflector`) |

**Placeholder scan:** None found.

**Type consistency:** `Entry.from_h` / `Entry#to_h` string keys used consistently in `Store`. `store.confirm` → `entry.confirm` chain consistent throughout. `robot.durable_store` reader used in both tools.
