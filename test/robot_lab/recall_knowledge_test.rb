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

  def test_no_match_message_includes_skip_guidance
    result = @tool.execute(query: "something unknown", domain: "newsletter curation")
    assert_match(/skip/, result.downcase)
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
