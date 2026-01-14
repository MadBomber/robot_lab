# frozen_string_literal: true

require "test_helper"

class RobotLab::ToolConfigTest < Minitest::Test
  def test_resolve_with_inherit_returns_parent_value
    result = RobotLab::ToolConfig.resolve(:inherit, parent_value: %w[tool1 tool2])
    assert_equal %w[tool1 tool2], result
  end

  def test_resolve_with_nil_returns_empty
    result = RobotLab::ToolConfig.resolve(nil, parent_value: %w[tool1 tool2])
    assert_equal [], result
  end

  def test_resolve_with_empty_array_returns_empty
    result = RobotLab::ToolConfig.resolve([], parent_value: %w[tool1 tool2])
    assert_equal [], result
  end

  def test_resolve_with_none_symbol_returns_empty
    result = RobotLab::ToolConfig.resolve(:none, parent_value: %w[tool1 tool2])
    assert_equal [], result
  end

  def test_resolve_with_specific_values_overrides_parent
    result = RobotLab::ToolConfig.resolve(%w[tool3 tool4], parent_value: %w[tool1 tool2])
    assert_equal %w[tool3 tool4], result
  end

  def test_resolve_tools_converts_to_strings
    result = RobotLab::ToolConfig.resolve_tools([:tool1, :tool2], parent_value: [])
    assert_equal %w[tool1 tool2], result
  end

  def test_resolve_tools_with_inherit
    result = RobotLab::ToolConfig.resolve_tools(:inherit, parent_value: %w[search refund])
    assert_equal %w[search refund], result
  end

  def test_none_value_recognizes_nil
    assert RobotLab::ToolConfig.none_value?(nil)
  end

  def test_none_value_recognizes_empty_array
    assert RobotLab::ToolConfig.none_value?([])
  end

  def test_none_value_recognizes_none_symbol
    assert RobotLab::ToolConfig.none_value?(:none)
  end

  def test_none_value_rejects_inherit
    refute RobotLab::ToolConfig.none_value?(:inherit)
  end

  def test_none_value_rejects_array_with_values
    refute RobotLab::ToolConfig.none_value?(%w[tool1])
  end

  def test_inherit_value_recognizes_inherit_symbol
    assert RobotLab::ToolConfig.inherit_value?(:inherit)
  end

  def test_inherit_value_rejects_other_values
    refute RobotLab::ToolConfig.inherit_value?(nil)
    refute RobotLab::ToolConfig.inherit_value?([])
    refute RobotLab::ToolConfig.inherit_value?(:none)
    refute RobotLab::ToolConfig.inherit_value?(%w[tool1])
  end

  def test_filter_tools_with_matching_names
    tool1 = MockTool.new("search")
    tool2 = MockTool.new("refund")
    tool3 = MockTool.new("cancel")

    result = RobotLab::ToolConfig.filter_tools(
      [tool1, tool2, tool3],
      allowed_names: %w[search cancel]
    )

    assert_equal 2, result.size
    assert_includes result, tool1
    assert_includes result, tool3
    refute_includes result, tool2
  end

  def test_filter_tools_with_empty_whitelist_returns_empty
    tool1 = MockTool.new("search")

    result = RobotLab::ToolConfig.filter_tools([tool1], allowed_names: [])

    assert_equal [], result
  end

  def test_filter_tools_with_symbol_names
    tool1 = MockTool.new("search")

    result = RobotLab::ToolConfig.filter_tools([tool1], allowed_names: [:search])

    assert_equal [tool1], result
  end

  private

  class MockTool
    attr_reader :name

    def initialize(name)
      @name = name
    end
  end
end
