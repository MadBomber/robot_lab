# frozen_string_literal: true

require "test_helper"

class RobotLab::ToolManifestTest < Minitest::Test
  def setup
    @tool1 = build_tool(name: "get_weather") { |args| "sunny" }
    @tool2 = build_tool(name: "calculate") { |args| args[:a] + args[:b] }
    @manifest = RobotLab::ToolManifest.new([@tool1, @tool2])
  end

  # Initialization tests
  def test_initialization_with_array_of_tools
    manifest = RobotLab::ToolManifest.new([@tool1, @tool2])
    assert_equal 2, manifest.size
  end

  def test_initialization_with_single_tool
    manifest = RobotLab::ToolManifest.new(@tool1)
    assert_equal 1, manifest.size
    assert_equal @tool1, manifest["get_weather"]
  end

  def test_initialization_with_no_tools
    manifest = RobotLab::ToolManifest.new
    assert manifest.empty?
  end

  def test_initialization_with_nil
    manifest = RobotLab::ToolManifest.new(nil)
    assert manifest.empty?
  end

  # Add tests
  def test_add_tool
    manifest = RobotLab::ToolManifest.new
    manifest.add(@tool1)

    assert manifest.include?("get_weather")
    assert_equal @tool1, manifest["get_weather"]
  end

  def test_add_returns_self
    manifest = RobotLab::ToolManifest.new
    result = manifest.add(@tool1)

    assert_same manifest, result
  end

  def test_shovel_alias
    manifest = RobotLab::ToolManifest.new
    manifest << @tool1

    assert manifest.include?("get_weather")
  end

  def test_add_replaces_existing_tool_with_same_name
    new_tool = build_tool(name: "get_weather") { |_args| "cloudy" }
    @manifest.add(new_tool)

    assert_equal new_tool, @manifest["get_weather"]
    assert_equal 2, @manifest.size
  end

  # Remove tests
  def test_remove_tool
    @manifest.remove("get_weather")

    refute @manifest.include?("get_weather")
    assert_equal 1, @manifest.size
  end

  def test_remove_returns_removed_tool
    result = @manifest.remove("get_weather")

    assert_equal @tool1, result
  end

  def test_remove_with_symbol
    @manifest.remove(:get_weather)

    refute @manifest.include?("get_weather")
  end

  def test_remove_nonexistent_returns_nil
    result = @manifest.remove("nonexistent")

    assert_nil result
  end

  # Bracket access tests
  def test_bracket_access
    assert_equal @tool1, @manifest["get_weather"]
    assert_equal @tool2, @manifest["calculate"]
  end

  def test_bracket_access_with_symbol
    assert_equal @tool1, @manifest[:get_weather]
  end

  def test_bracket_access_missing_returns_nil
    assert_nil @manifest["nonexistent"]
  end

  # Fetch tests
  def test_fetch_returns_tool
    assert_equal @tool1, @manifest.fetch("get_weather")
  end

  def test_fetch_with_symbol
    assert_equal @tool1, @manifest.fetch(:get_weather)
  end

  def test_fetch_raises_for_missing_tool
    error = assert_raises(RobotLab::ToolNotFoundError) do
      @manifest.fetch("nonexistent")
    end

    assert_includes error.message, "Tool not found: nonexistent"
    assert_includes error.message, "Available tools:"
    assert_includes error.message, "get_weather"
    assert_includes error.message, "calculate"
  end

  # Include tests
  def test_include_returns_true_for_existing
    assert @manifest.include?("get_weather")
    assert @manifest.include?(:calculate)
  end

  def test_include_returns_false_for_missing
    refute @manifest.include?("missing")
  end

  def test_has_alias
    assert @manifest.has?("get_weather")
    refute @manifest.has?("missing")
  end

  # Names tests
  def test_names_returns_all_tool_names
    names = @manifest.names

    assert_includes names, "get_weather"
    assert_includes names, "calculate"
    assert_equal 2, names.size
  end

  # Values tests
  def test_values_returns_all_tools
    values = @manifest.values

    assert_includes values, @tool1
    assert_includes values, @tool2
  end

  def test_all_alias
    assert_equal @manifest.values, @manifest.all
  end

  def test_to_a_alias
    assert_equal @manifest.values, @manifest.to_a
  end

  # Size tests
  def test_size
    assert_equal 2, @manifest.size
  end

  def test_count_alias
    assert_equal 2, @manifest.count
  end

  def test_length_alias
    assert_equal 2, @manifest.length
  end

  # Empty tests
  def test_empty_returns_false_for_nonempty
    refute @manifest.empty?
  end

  def test_empty_returns_true_for_empty
    manifest = RobotLab::ToolManifest.new
    assert manifest.empty?
  end

  # Each tests
  def test_each_iterates_over_tools
    tools = []
    @manifest.each { |tool| tools << tool }

    assert_includes tools, @tool1
    assert_includes tools, @tool2
    assert_equal 2, tools.size
  end

  def test_manifest_is_enumerable
    assert @manifest.is_a?(Enumerable)
  end

  def test_map_works
    names = @manifest.map(&:name)

    assert_includes names, "get_weather"
    assert_includes names, "calculate"
  end

  # Clear tests
  def test_clear_removes_all_tools
    @manifest.clear

    assert @manifest.empty?
    assert_equal 0, @manifest.size
  end

  def test_clear_returns_self
    result = @manifest.clear

    assert_same @manifest, result
  end

  # Replace tests
  def test_replace_clears_and_adds_new_tools
    new_tool = build_tool(name: "new_tool") { "result" }
    @manifest.replace([new_tool])

    assert_equal 1, @manifest.size
    assert @manifest.include?("new_tool")
    refute @manifest.include?("get_weather")
  end

  def test_replace_returns_self
    result = @manifest.replace([])

    assert_same @manifest, result
  end

  # Merge tests
  def test_merge_with_tool_manifest
    other_manifest = RobotLab::ToolManifest.new([build_tool(name: "other") { "result" }])
    @manifest.merge(other_manifest)

    assert_equal 3, @manifest.size
    assert @manifest.include?("other")
  end

  def test_merge_with_array_of_tools
    other_tools = [build_tool(name: "other") { "result" }]
    @manifest.merge(other_tools)

    assert_equal 3, @manifest.size
    assert @manifest.include?("other")
  end

  def test_merge_with_single_tool
    other_tool = build_tool(name: "other") { "result" }
    @manifest.merge(other_tool)

    assert_equal 3, @manifest.size
    assert @manifest.include?("other")
  end

  def test_merge_returns_self
    result = @manifest.merge([])

    assert_same @manifest, result
  end

  # Serialization tests
  def test_to_h_returns_hash
    hash = @manifest.to_h

    assert hash.is_a?(Hash)
    assert hash.key?("get_weather")
    assert hash.key?("calculate")
  end

  def test_to_json_returns_json_string
    json = @manifest.to_json

    assert json.is_a?(String)
    parsed = JSON.parse(json)
    assert parsed.key?("get_weather")
    assert parsed.key?("calculate")
  end

  # from_hash tests
  def test_from_hash_creates_manifest
    hash = {
      "search" => { description: "Search for items", parameters: {}, handler: nil },
      "delete" => { description: "Delete an item", parameters: {}, handler: nil }
    }

    manifest = RobotLab::ToolManifest.from_hash(hash)

    assert_equal 2, manifest.size
    assert manifest.include?("search")
    assert manifest.include?("delete")
  end
end
