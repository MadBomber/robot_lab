# frozen_string_literal: true

require "test_helper"

class RobotLab::DotStateTest < Minitest::Test
  def setup
    @state = RobotLab::DotState.new
  end

  def test_bracket_assignment_stores_the_value_under_the_key
    @state[:start] = 12_345

    assert_equal 12_345, @state[:start]
    assert_equal({ start: 12_345 }, @state.to_h)
  end

  def test_bracket_access_shares_storage_with_dot_access
    @state[:start] = 1
    @state.finish = 2

    assert_equal 1, @state.start
    assert_equal 2, @state[:finish]
  end

  def test_bracket_access_accepts_string_keys
    @state["count"] = 3

    assert_equal 3, @state[:count]
    assert_equal 3, @state["count"]
  end

  def test_bracket_access_for_a_missing_key_returns_nil
    assert_nil @state[:missing]
  end
end
