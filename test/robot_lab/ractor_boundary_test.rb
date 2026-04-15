# frozen_string_literal: true

require "test_helper"

class RobotLab::RactorBoundaryTest < Minitest::Test
  def test_freezes_string
    result = RobotLab::RactorBoundary.freeze_deep("hello")
    assert result.frozen?
  end

  def test_freezes_hash_recursively
    result = RobotLab::RactorBoundary.freeze_deep({ a: { b: "c" } })
    assert result.frozen?
    assert result[:a].frozen?
    assert result[:a][:b].frozen?
  end

  def test_freezes_array_recursively
    result = RobotLab::RactorBoundary.freeze_deep(["x", { y: "z" }])
    assert result.frozen?
    assert result[0].frozen?
    assert result[1].frozen?
  end

  def test_passes_through_already_frozen
    frozen_str = "hi".freeze
    assert_same frozen_str, RobotLab::RactorBoundary.freeze_deep(frozen_str)
  end

  def test_passes_through_integer
    assert_equal 42, RobotLab::RactorBoundary.freeze_deep(42)
  end

  def test_passes_through_symbol
    assert_equal :foo, RobotLab::RactorBoundary.freeze_deep(:foo)
  end

  def test_result_is_ractor_shareable
    result = RobotLab::RactorBoundary.freeze_deep({ model: "sonnet", args: [1, 2] })
    assert Ractor.shareable?(result)
  end

  def test_raises_ractor_boundary_error_on_unshareable
    io = StringIO.new
    assert_raises(RobotLab::RactorBoundaryError) do
      RobotLab::RactorBoundary.freeze_deep(io)
    end
  end
end
