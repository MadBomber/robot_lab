# frozen_string_literal: true

require "test_helper"

class RobotLab::TextAnalysisTest < Minitest::Test
  # -----------------------------------------------------------------------
  # dot — pure math, no classifier gem needed
  # -----------------------------------------------------------------------

  def test_dot_shared_keys
    a = { foo: 0.5, bar: 0.5 }
    b = { bar: 0.5, baz: 0.5 }
    assert_in_delta 0.25, RobotLab::TextAnalysis.dot(a, b)
  end

  def test_dot_no_shared_keys
    a = { foo: 1.0 }
    b = { bar: 1.0 }
    assert_in_delta 0.0, RobotLab::TextAnalysis.dot(a, b)
  end

  def test_dot_empty_vectors
    assert_in_delta 0.0, RobotLab::TextAnalysis.dot({}, {})
  end

  # -----------------------------------------------------------------------
  # l2_normalize
  # -----------------------------------------------------------------------

  def test_l2_normalize_unit_vector
    result = RobotLab::TextAnalysis.l2_normalize({ a: 3.0, b: 4.0 })
    assert_in_delta 0.6, result[:a], 0.001
    assert_in_delta 0.8, result[:b], 0.001
  end

  def test_l2_normalize_zero_vector_returns_empty
    assert_equal({}, RobotLab::TextAnalysis.l2_normalize({ a: 0.0 }))
  end

  def test_l2_normalize_empty_vector_returns_empty
    assert_equal({}, RobotLab::TextAnalysis.l2_normalize({}))
  end

  # -----------------------------------------------------------------------
  # cosine_similarity — pure math, no classifier gem needed
  # -----------------------------------------------------------------------

  def test_cosine_similarity_identical_unit_vectors
    v = { a: 1.0 }
    assert_in_delta 1.0, RobotLab::TextAnalysis.cosine_similarity(v, v)
  end

  def test_cosine_similarity_orthogonal_vectors
    a = { x: 1.0 }
    b = { y: 1.0 }
    assert_in_delta 0.0, RobotLab::TextAnalysis.cosine_similarity(a, b)
  end

  def test_cosine_similarity_partial_overlap
    a = { x: 0.707, y: 0.707 }
    b = { x: 1.0 }
    result = RobotLab::TextAnalysis.cosine_similarity(a, b)
    assert_operator result, :>, 0.0
    assert_operator result, :<, 1.0
  end

  def test_cosine_similarity_empty_vec_a
    assert_in_delta 0.0, RobotLab::TextAnalysis.cosine_similarity({}, { a: 1.0 })
  end

  def test_cosine_similarity_empty_vec_b
    assert_in_delta 0.0, RobotLab::TextAnalysis.cosine_similarity({ a: 1.0 }, {})
  end

  def test_cosine_similarity_clamps_above_one
    a = { x: 0.9999999 }
    b = { x: 1.0000001 }
    result = RobotLab::TextAnalysis.cosine_similarity(a, b)
    assert_operator result, :<=, 1.0
  end

  # -----------------------------------------------------------------------
  # require_classifier! — LoadError path (define_singleton_method pattern)
  # -----------------------------------------------------------------------

  def test_require_classifier_wraps_load_error_as_dependency_error
    original = RobotLab::TextAnalysis.method(:load_classifier_gem)
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem) { raise LoadError, "no classifier" }
    assert_raises(RobotLab::DependencyError) { RobotLab::TextAnalysis.require_classifier! }
  ensure
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem, &original)
  end

  def test_dependency_error_message_includes_install_hint
    original = RobotLab::TextAnalysis.method(:load_classifier_gem)
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem) { raise LoadError, "no classifier" }
    error = assert_raises(RobotLab::DependencyError) { RobotLab::TextAnalysis.require_classifier! }
    assert_match(/classifier/, error.message)
    assert_match(/Gemfile/, error.message)
  ensure
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem, &original)
  end

  # -----------------------------------------------------------------------
  # fit / transform — require classifier gem
  # -----------------------------------------------------------------------

  def setup_classifier_or_skip
    RobotLab::TextAnalysis.require_classifier!
  rescue RobotLab::DependencyError
    skip "classifier gem not available"
  end

  def test_fit_returns_tfidf_model
    setup_classifier_or_skip
    corpus = ["the quick brown fox", "jumps over the lazy dog"]
    model  = RobotLab::TextAnalysis.fit(corpus)
    refute_nil model
    assert_respond_to model, :transform
  end

  def test_transform_returns_hash_with_symbol_keys
    setup_classifier_or_skip
    corpus = ["ruby programming language", "python programming language"]
    model  = RobotLab::TextAnalysis.fit(corpus)
    vec    = RobotLab::TextAnalysis.transform(model, "ruby programming")
    assert_kind_of Hash, vec
    assert vec.keys.all?(Symbol), "expected Symbol keys"
    assert vec.values.all?(Float), "expected Float values"
  end

  def test_transform_empty_text_returns_hash
    setup_classifier_or_skip
    corpus = ["hello world"]
    model  = RobotLab::TextAnalysis.fit(corpus)
    vec    = RobotLab::TextAnalysis.transform(model, "")
    assert_kind_of Hash, vec
  end

  def test_transform_unknown_terms_returns_sparse_or_empty
    setup_classifier_or_skip
    corpus = ["hello world"]
    model  = RobotLab::TextAnalysis.fit(corpus)
    vec    = RobotLab::TextAnalysis.transform(model, "zzz xyz qqqq")
    assert_kind_of Hash, vec
  end

  # -----------------------------------------------------------------------
  # tf_cosine_similarity — word_hash based
  # -----------------------------------------------------------------------

  def test_tf_cosine_similar_texts_score_higher_than_unrelated
    setup_classifier_or_skip
    rails_a = "Ruby on Rails is a web framework built on top of the Ruby programming language"
    rails_b = "Rails provides a structure for web applications using the Ruby language and MVC"
    ocean   = "The Pacific Ocean is the largest body of water on the surface of the Earth"

    sim_rails = RobotLab::TextAnalysis.tf_cosine_similarity(rails_a, rails_b)
    sim_ocean = RobotLab::TextAnalysis.tf_cosine_similarity(rails_a, ocean)

    assert_operator sim_rails, :>, sim_ocean,
                    "Rails/Rails similarity (#{sim_rails}) should exceed Rails/Ocean (#{sim_ocean})"
  end

  def test_tf_cosine_identical_texts_returns_one
    setup_classifier_or_skip
    text  = "Ruby on Rails is a popular web application framework for building great software"
    score = RobotLab::TextAnalysis.tf_cosine_similarity(text, text)
    assert_in_delta 1.0, score, 0.001
  end

  def test_tf_cosine_raises_dependency_error_when_classifier_missing
    original = RobotLab::TextAnalysis.method(:load_classifier_gem)
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem) { raise LoadError }
    assert_raises(RobotLab::DependencyError) do
      RobotLab::TextAnalysis.tf_cosine_similarity("hello world test", "hello world test")
    end
  ensure
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem, &original)
  end

  def test_similar_tfidf_texts_have_higher_score_than_dissimilar
    setup_classifier_or_skip
    corpus = [
      "Ruby on Rails is a web framework",
      "ActiveRecord is the Rails ORM layer",
      "The Pacific Ocean covers most of the globe"
    ]
    model = RobotLab::TextAnalysis.fit(corpus)

    rails_vec  = RobotLab::TextAnalysis.transform(model, corpus[0])
    active_vec = RobotLab::TextAnalysis.transform(model, corpus[1])
    ocean_vec  = RobotLab::TextAnalysis.transform(model, corpus[2])

    rails_active_sim = RobotLab::TextAnalysis.cosine_similarity(rails_vec, active_vec)
    rails_ocean_sim  = RobotLab::TextAnalysis.cosine_similarity(rails_vec, ocean_vec)

    assert_operator rails_active_sim, :>=, rails_ocean_sim,
                    "Rails/ActiveRecord should score >= Rails/Ocean (got #{rails_active_sim} vs #{rails_ocean_sim})"
  end
end
