# frozen_string_literal: true

require "test_helper"

class RobotLab::TaskTest < Minitest::Test
  def setup
    @robot = build_robot(name: "test_robot", description: "Test robot")
  end

  # Initialization tests
  def test_initialization_with_required_params
    task = RobotLab::Task.new(name: :test, robot: @robot)

    assert_equal :test, task.name
    assert_equal @robot, task.robot
  end

  def test_initialization_converts_name_to_symbol
    task = RobotLab::Task.new(name: "test", robot: @robot)

    assert_equal :test, task.name
  end

  def test_initialization_with_context
    task = RobotLab::Task.new(
      name: :test,
      robot: @robot,
      context: { department: "billing" }
    )

    assert_equal :test, task.name
  end

  def test_initialization_with_mcp_config
    mcp_config = [{ name: "server", transport: { type: "stdio", command: "cmd" } }]
    task = RobotLab::Task.new(
      name: :test,
      robot: @robot,
      mcp: mcp_config
    )

    assert_equal :test, task.name
  end

  def test_initialization_with_tools_config
    task = RobotLab::Task.new(
      name: :test,
      robot: @robot,
      tools: %w[tool1 tool2]
    )

    assert_equal :test, task.name
  end

  def test_initialization_with_memory
    memory = RobotLab::Memory.new
    task = RobotLab::Task.new(
      name: :test,
      robot: @robot,
      memory: memory
    )

    assert_equal :test, task.name
  end

  # Deep merge tests
  def test_deep_merge_simple_values
    task = RobotLab::Task.new(
      name: :test,
      robot: @robot,
      context: { key: "task_value" }
    )

    # Call the task to trigger deep merge
    merged_result = task.send(:deep_merge, { key: "network_value", other: "preserved" }, { key: "task_value" })

    assert_equal "task_value", merged_result[:key]
    assert_equal "preserved", merged_result[:other]
  end

  def test_deep_merge_nested_hashes
    task = RobotLab::Task.new(name: :test, robot: @robot)

    base = { user: { id: 123, tier: "free" }, message: "hello" }
    override = { user: { tier: "premium" } }

    merged = task.send(:deep_merge, base, override)

    assert_equal 123, merged[:user][:id]
    assert_equal "premium", merged[:user][:tier]
    assert_equal "hello", merged[:message]
  end

  def test_deep_merge_deeply_nested
    task = RobotLab::Task.new(name: :test, robot: @robot)

    base = { a: { b: { c: 1, d: 2 } } }
    override = { a: { b: { c: 10 } } }

    merged = task.send(:deep_merge, base, override)

    assert_equal 10, merged[:a][:b][:c]
    assert_equal 2, merged[:a][:b][:d]
  end

  def test_deep_merge_arrays_are_replaced
    task = RobotLab::Task.new(name: :test, robot: @robot)

    base = { items: [1, 2, 3] }
    override = { items: [4, 5] }

    merged = task.send(:deep_merge, base, override)

    assert_equal [4, 5], merged[:items]
  end

  def test_deep_merge_handles_string_keys
    task = RobotLab::Task.new(name: :test, robot: @robot)

    base = { "key" => "value1" }
    override = { key: "value2" }

    merged = task.send(:deep_merge, base, override)

    assert_equal "value2", merged[:key]
  end

  # to_h tests
  def test_to_h_basic
    task = RobotLab::Task.new(name: :test, robot: @robot)

    hash = task.to_h

    assert_equal :test, hash[:name]
    assert_equal "test_robot", hash[:robot]
  end

  def test_to_h_with_context
    task = RobotLab::Task.new(
      name: :test,
      robot: @robot,
      context: { department: "billing" }
    )

    hash = task.to_h

    assert_equal({ department: "billing" }, hash[:context])
  end

  def test_to_h_with_mcp
    mcp_config = [{ name: "server" }]
    task = RobotLab::Task.new(
      name: :test,
      robot: @robot,
      mcp: mcp_config
    )

    hash = task.to_h

    assert_equal mcp_config, hash[:mcp]
  end

  def test_to_h_with_tools
    task = RobotLab::Task.new(
      name: :test,
      robot: @robot,
      tools: %w[tool1 tool2]
    )

    hash = task.to_h

    assert_equal %w[tool1 tool2], hash[:tools]
  end

  def test_to_h_with_memory_shows_boolean
    memory = RobotLab::Memory.new
    task = RobotLab::Task.new(
      name: :test,
      robot: @robot,
      memory: memory
    )

    hash = task.to_h

    assert_equal true, hash[:memory]
  end

  def test_to_h_without_memory_excludes_key
    task = RobotLab::Task.new(name: :test, robot: @robot)

    hash = task.to_h

    refute hash.key?(:memory)
  end
end
