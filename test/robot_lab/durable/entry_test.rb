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
