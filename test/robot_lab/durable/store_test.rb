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

  def test_confirm_increments_confidence_on_disk
    entry = @store.record(build_entry(confidence: 0.2))
    @store.confirm(entry)
    results = @store.recall(query: "LangChain", domain: "newsletter curation")
    assert_in_delta 0.3, results.first.confidence, 0.001
  end

  def test_spaces_in_domain_become_underscores_in_filename
    @store.record(build_entry(domain: "newsletter curation"))
    assert File.exist?(File.join(@tmpdir, "newsletter_curation.yaml"))
  end
end
