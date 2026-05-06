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

  def test_entry_starts_with_low_confidence
    @tool.execute(
      content:   "New pattern",
      reasoning: "Observed once",
      category:  "pattern",
      domain:    "newsletter curation"
    )
    results = @store.recall(query: "New pattern", domain: "newsletter curation")
    assert_in_delta 0.1, results.first.confidence, 0.001
  end
end
