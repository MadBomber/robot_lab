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

  def test_deep_merge_with_non_hash_overriding_hash
    task = RobotLab::Task.new(name: :test, robot: @robot)

    # When override value is not a Hash but base value is, override wins
    base = { config: { key: "value" } }
    override = { config: "simple_string" }

    merged = task.send(:deep_merge, base, override)

    assert_equal "simple_string", merged[:config]
  end

  def test_deep_merge_with_hash_overriding_non_hash
    task = RobotLab::Task.new(name: :test, robot: @robot)

    base = { config: "simple_string" }
    override = { config: { key: "value" } }

    merged = task.send(:deep_merge, base, override)

    assert_equal({ key: "value" }, merged[:config])
  end

  def test_call_with_none_mcp_does_not_set_run_params_mcp
    # The stub robot's call needs to work; use a SimpleFlow::Result
    require 'simple_flow'
    result_stub = SimpleFlow::Result.new("input", context: {})
    task = RobotLab::Task.new(name: :test, robot: @robot, mcp: :none)

    # Stub the robot's call to avoid real LLM calls
    robot_result = RobotLab::RobotResult.new(robot_name: "test_robot", output: [])
    @robot.define_singleton_method(:call) do |r|
      r.with_context(:test_robot, robot_result).continue(robot_result)
    end

    result = task.call(result_stub)
    # Should not raise
    assert result
  end

  def test_call_with_mcp_config_sets_run_params
    require 'simple_flow'
    result_stub = SimpleFlow::Result.new("input", context: {})
    mcp_config = [{ name: "test", transport: "stdio" }]
    task = RobotLab::Task.new(name: :test, robot: @robot, mcp: mcp_config)

    captured_run_params = nil
    @robot.define_singleton_method(:call) do |r|
      captured_run_params = r.context[:run_params]
      robot_result = RobotLab::RobotResult.new(robot_name: "test_robot", output: [])
      r.with_context(:test_robot, robot_result).continue(robot_result)
    end

    task.call(result_stub)
    assert_equal mcp_config, captured_run_params[:mcp]
  end

  def test_call_with_tools_config_sets_run_params
    require 'simple_flow'
    result_stub = SimpleFlow::Result.new("input", context: {})
    task = RobotLab::Task.new(name: :test, robot: @robot, tools: %w[tool_a])

    captured_run_params = nil
    @robot.define_singleton_method(:call) do |r|
      captured_run_params = r.context[:run_params]
      robot_result = RobotLab::RobotResult.new(robot_name: "test_robot", output: [])
      r.with_context(:test_robot, robot_result).continue(robot_result)
    end

    task.call(result_stub)
    assert_equal %w[tool_a], captured_run_params[:tools]
  end

  def test_call_with_memory_sets_run_params
    require 'simple_flow'
    result_stub = SimpleFlow::Result.new("input", context: {})
    memory = RobotLab::Memory.new
    task = RobotLab::Task.new(name: :test, robot: @robot, memory: memory)

    captured_run_params = nil
    @robot.define_singleton_method(:call) do |r|
      captured_run_params = r.context[:run_params]
      robot_result = RobotLab::RobotResult.new(robot_name: "test_robot", output: [])
      r.with_context(:test_robot, robot_result).continue(robot_result)
    end

    task.call(result_stub)
    assert_equal memory, captured_run_params[:memory]
  end

  def test_call_with_task_config_merges_network_config
    require 'simple_flow'
    network_config = RobotLab::RunConfig.new(temperature: 0.5)
    result_stub = SimpleFlow::Result.new("input", context: { run_params: { network_config: network_config } })
    task_config = RobotLab::RunConfig.new(temperature: 0.8)
    task = RobotLab::Task.new(name: :test, robot: @robot, config: task_config)

    captured_run_params = nil
    @robot.define_singleton_method(:call) do |r|
      captured_run_params = r.context[:run_params]
      robot_result = RobotLab::RobotResult.new(robot_name: "test_robot", output: [])
      r.with_context(:test_robot, robot_result).continue(robot_result)
    end

    task.call(result_stub)
    # Task config (0.8) should override network config (0.5) in merged config
    assert_equal 0.8, captured_run_params[:network_config].temperature
  end

  def test_call_with_task_config_no_network_config
    require 'simple_flow'
    result_stub = SimpleFlow::Result.new("input", context: {})
    task_config = RobotLab::RunConfig.new(temperature: 0.7)
    task = RobotLab::Task.new(name: :test, robot: @robot, config: task_config)

    captured_run_params = nil
    @robot.define_singleton_method(:call) do |r|
      captured_run_params = r.context[:run_params]
      robot_result = RobotLab::RobotResult.new(robot_name: "test_robot", output: [])
      r.with_context(:test_robot, robot_result).continue(robot_result)
    end

    task.call(result_stub)
    assert_equal task_config, captured_run_params[:network_config]
  end
end
