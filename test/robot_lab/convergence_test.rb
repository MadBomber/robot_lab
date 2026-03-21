# frozen_string_literal: true

require "test_helper"

class RobotLab::ConvergenceTest < Minitest::Test
  RUBY_TEXT_A = <<~TEXT.strip
    Ruby on Rails is a web application framework written in Ruby.
    It follows the MVC pattern and emphasizes convention over configuration.
    ActiveRecord handles database interactions through an ORM layer.
  TEXT

  RUBY_TEXT_B = <<~TEXT.strip
    Rails is a popular Ruby framework for building web applications.
    It uses the Model-View-Controller architecture and ActiveRecord for database access.
    Convention over configuration reduces the need for boilerplate code.
  TEXT

  UNRELATED_TEXT = <<~TEXT.strip
    The Pacific Ocean is the largest and deepest ocean on Earth.
    It covers more than thirty percent of the planet surface area.
    Numerous island chains and coral reefs are found throughout its waters.
  TEXT

  def simulate_load_error(&block)
    original = RobotLab::TextAnalysis.method(:load_classifier_gem)
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem) { raise LoadError }
    block.call
  ensure
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem, &original)
  end

  # -----------------------------------------------------------------------
  # Tests that do NOT require the classifier gem
  # -----------------------------------------------------------------------

  def test_detected_invalid_threshold_high_raises_argument_error
    assert_raises(ArgumentError) { RobotLab::Convergence.detected?("a", "b", threshold: 1.5) }
  end

  def test_detected_invalid_threshold_negative_raises_argument_error
    assert_raises(ArgumentError) { RobotLab::Convergence.detected?("a", "b", threshold: -0.1) }
  end

  def test_similarity_returns_zero_for_empty_strings
    assert_in_delta 0.0, RobotLab::Convergence.similarity("", "")
  end

  def test_similarity_returns_zero_for_short_text
    assert_in_delta 0.0, RobotLab::Convergence.similarity("hi", "hello")
  end

  def test_similarity_returns_zero_when_one_text_short
    assert_in_delta 0.0, RobotLab::Convergence.similarity(RUBY_TEXT_A, "short")
  end

  # -----------------------------------------------------------------------
  # LoadError path
  # -----------------------------------------------------------------------

  def test_similarity_raises_dependency_error_when_classifier_missing
    simulate_load_error do
      assert_raises(RobotLab::DependencyError) do
        RobotLab::Convergence.similarity(RUBY_TEXT_A, RUBY_TEXT_B)
      end
    end
  end

  def test_detected_raises_dependency_error_when_classifier_missing
    simulate_load_error do
      assert_raises(RobotLab::DependencyError) do
        RobotLab::Convergence.detected?(RUBY_TEXT_A, RUBY_TEXT_B)
      end
    end
  end

  # -----------------------------------------------------------------------
  # Tests that require the classifier gem
  # -----------------------------------------------------------------------

  def setup_classifier_or_skip
    RobotLab::TextAnalysis.require_classifier!
  rescue RobotLab::DependencyError
    skip "classifier gem not available"
  end

  def test_similarity_similar_texts_returns_high_score
    setup_classifier_or_skip
    score = RobotLab::Convergence.similarity(RUBY_TEXT_A, RUBY_TEXT_B)
    assert_operator score, :>=, 0.4, "similar Ruby/Rails texts should score >= 0.4, got #{score}"
  end

  def test_similarity_unrelated_texts_returns_lower_score_than_similar
    setup_classifier_or_skip
    similar_score   = RobotLab::Convergence.similarity(RUBY_TEXT_A, RUBY_TEXT_B)
    unrelated_score = RobotLab::Convergence.similarity(RUBY_TEXT_A, UNRELATED_TEXT)
    assert_operator similar_score, :>, unrelated_score,
                    "similar (#{similar_score}) should beat unrelated (#{unrelated_score})"
  end

  def test_similarity_is_in_range
    setup_classifier_or_skip
    score = RobotLab::Convergence.similarity(RUBY_TEXT_A, RUBY_TEXT_B)
    assert_operator score, :>=, 0.0
    assert_operator score, :<=, 1.0
  end

  def test_detected_true_when_similar_above_threshold
    setup_classifier_or_skip
    assert RobotLab::Convergence.detected?(RUBY_TEXT_A, RUBY_TEXT_B, threshold: 0.4),
           "similar Ruby texts should converge at threshold 0.4"
  end

  def test_detected_false_when_unrelated_above_threshold
    setup_classifier_or_skip
    refute RobotLab::Convergence.detected?(RUBY_TEXT_A, UNRELATED_TEXT, threshold: 0.5),
           "unrelated texts should not converge at threshold 0.5"
  end

  def test_detected_uses_default_threshold_for_identical_texts
    setup_classifier_or_skip
    assert RobotLab::Convergence.detected?(RUBY_TEXT_A, RUBY_TEXT_A),
           "identical texts should always converge at the default threshold"
  end

  def test_similarity_symmetric
    setup_classifier_or_skip
    ab = RobotLab::Convergence.similarity(RUBY_TEXT_A, RUBY_TEXT_B)
    ba = RobotLab::Convergence.similarity(RUBY_TEXT_B, RUBY_TEXT_A)
    assert_in_delta ab, ba, 0.001, "similarity should be symmetric"
  end

  def test_similarity_identical_texts_near_one
    setup_classifier_or_skip
    score = RobotLab::Convergence.similarity(RUBY_TEXT_A, RUBY_TEXT_A)
    assert_operator score, :>=, 0.99, "identical texts should score near 1.0, got #{score}"
  end
end
