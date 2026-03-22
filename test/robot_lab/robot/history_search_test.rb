# frozen_string_literal: true

require "test_helper"

class RobotLab::Robot::HistorySearchTest < Minitest::Test
  # Minimal message stub that quacks like RubyLLM::Message
  FakeMsg = Struct.new(:role, :content, :tool_calls)

  # Fake chat that just holds a message list
  FakeChat = Struct.new(:messages)

  def setup
    @robot = build_robot(name: "searcher", system_prompt: "You search.")
    # Replace the real @chat with a controllable stub
    @fake_chat = FakeChat.new([])
    @robot.instance_variable_set(:@chat, @fake_chat)
  end

  def msg(role, content)
    FakeMsg.new(role.to_sym, content, nil)
  end

  def load_history(*pairs)
    msgs = pairs.each_slice(2).flat_map do |user_text, assistant_text|
      [msg(:user, user_text), msg(:assistant, assistant_text)]
    end
    @fake_chat.messages.replace(msgs)
  end

  def simulate_classifier_missing(&block)
    original = RobotLab::TextAnalysis.method(:load_classifier_gem)
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem) { raise LoadError }
    block.call
  ensure
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem, &original)
  end

  # -------------------------------------------------------------------------
  # Empty / trivial cases
  # -------------------------------------------------------------------------

  def test_empty_history_returns_empty_array
    assert_equal [], @robot.search_history("anything")
  end

  def test_returns_empty_when_query_produces_no_terms
    load_history("What is Ruby?", "Ruby is a programming language.")
    # A query of only stopwords / too-short terms collapses to empty vector
    result = @robot.search_history("a an the")
    assert_instance_of Array, result
  end

  # -------------------------------------------------------------------------
  # Basic ranking
  # -------------------------------------------------------------------------

  def test_relevant_message_scores_higher_than_unrelated
    load_history(
      "Tell me about Ruby on Rails and web frameworks for building APIs.",
      "Rails is a full-stack web framework written in Ruby.",
      "What should I have for lunch today?",
      "Perhaps a salad or sandwich would be nice."
    )

    results = @robot.search_history("Ruby Rails web framework API", limit: 4)
    assert results.size >= 2, "Expected at least 2 results"

    top_texts = results.first(2).map(&:text)
    assert top_texts.any? { |t| t.downcase.include?("rails") || t.downcase.include?("ruby") },
           "Expected Rails/Ruby message in top-2"
  end

  def test_results_are_sorted_by_score_descending
    load_history(
      "Ruby on Rails is a web framework built for rapid application development.",
      "Rails follows convention over configuration for productivity.",
      "The weather today is sunny and warm outside.",
      "I enjoy walking in the park on nice days."
    )

    results = @robot.search_history("Ruby Rails web development", limit: 4)
    scores = results.map(&:score)
    assert_equal scores.sort.reverse, scores, "Results should be sorted by score descending"
  end

  # -------------------------------------------------------------------------
  # Result shape
  # -------------------------------------------------------------------------

  def test_result_has_expected_fields
    load_history(
      "Ruby on Rails enables rapid web application development with convention over configuration.",
      "Rails is opinionated and provides defaults for common patterns."
    )

    results = @robot.search_history("Rails web framework")
    refute_empty results

    r = results.first
    assert_respond_to r, :text
    assert_respond_to r, :role
    assert_respond_to r, :score
    assert_respond_to r, :index
    assert_kind_of Float, r.score
    assert r.score >= 0.0 && r.score <= 1.0
    assert_kind_of Integer, r.index
    assert [:user, :assistant, :system].include?(r.role)
  end

  def test_index_corresponds_to_position_in_message_array
    load_history(
      "Ruby on Rails is great for building web applications.",
      "Rails follows many conventions to speed up development."
    )

    results = @robot.search_history("Rails web", limit: 2)
    results.each do |r|
      assert_equal @fake_chat.messages[r.index].content, r.text
    end
  end

  # -------------------------------------------------------------------------
  # Limit
  # -------------------------------------------------------------------------

  def test_limit_caps_result_count
    load_history(
      "Ruby on Rails is a popular web framework for rapid development.",
      "Rails follows convention over configuration for productivity gains.",
      "ActiveRecord is Rails ORM for database interactions and queries.",
      "Ruby language has elegant syntax and powerful metaprogramming features."
    )

    results = @robot.search_history("Ruby Rails framework", limit: 2)
    assert results.size <= 2
  end

  def test_default_limit_is_five
    msgs = (1..10).flat_map do |i|
      [msg(:user, "Ruby on Rails web framework question number #{i} about development tools"),
       msg(:assistant, "Ruby on Rails answer #{i} covers web development and testing practices")]
    end
    @fake_chat.messages.replace(msgs)

    results = @robot.search_history("Ruby on Rails development")
    assert results.size <= 5
  end

  # -------------------------------------------------------------------------
  # Short messages are skipped
  # -------------------------------------------------------------------------

  def test_short_messages_below_min_length_are_skipped
    @fake_chat.messages.replace([
      msg(:user,      "Hi"),
      msg(:assistant, "Hello"),
      msg(:user,      "Ruby on Rails enables rapid web application development.")
    ])

    results = @robot.search_history("Ruby web Rails development")
    # The two short messages should not appear (below MIN_SCORE_LENGTH)
    results.each do |r|
      assert r.text.length >= RobotLab::Robot::HistorySearch::MIN_SCORE_LENGTH
    end
  end

  # -------------------------------------------------------------------------
  # Classifier missing
  # -------------------------------------------------------------------------

  def test_raises_dependency_error_when_classifier_missing
    load_history(
      "Ruby on Rails enables rapid web application development.",
      "Rails follows convention over configuration for productivity."
    )

    simulate_classifier_missing do
      assert_raises RobotLab::DependencyError do
        @robot.search_history("Ruby Rails")
      end
    end
  end
end
