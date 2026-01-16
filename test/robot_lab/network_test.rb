# frozen_string_literal: true

require "test_helper"

class RobotLab::NetworkTest < Minitest::Test
  def setup
    @robot1 = build_robot(name: "robot1", description: "First robot")
    @robot2 = build_robot(name: "robot2", description: "Second robot")
  end

  # Initialization tests
  def test_initialization_with_name
    network = RobotLab::Network.new(name: "test_network")

    assert_equal "test_network", network.name
    assert_equal({}, network.robots)
  end

  def test_initialization_converts_name_to_string
    network = RobotLab::Network.new(name: :test_network)

    assert_equal "test_network", network.name
  end

  def test_initialization_with_block
    robot = @robot1
    network = RobotLab::Network.new(name: "test") do
      task :robot1, robot, depends_on: :none
    end

    assert_equal 1, network.robots.size
    assert network.robots.key?("robot1")
  end

  def test_initialization_creates_pipeline
    network = RobotLab::Network.new(name: "test")

    assert_instance_of SimpleFlow::Pipeline, network.pipeline
  end

  def test_initialization_with_concurrency_option
    network = RobotLab::Network.new(name: "test", concurrency: :threads)

    assert_equal :threads, network.pipeline.concurrency
  end

  # Task tests
  def test_task_adds_robot_to_robots_hash
    network = RobotLab::Network.new(name: "test")
    network.task(:robot1, @robot1, depends_on: :none)

    assert_equal 1, network.robots.size
    assert_equal @robot1, network.robots["robot1"]
  end

  def test_task_adds_to_pipeline
    network = RobotLab::Network.new(name: "test")
    network.task(:robot1, @robot1, depends_on: :none)

    assert_equal 1, network.pipeline.steps.size
    assert_equal :robot1, network.pipeline.steps.first[:name]
  end

  def test_task_returns_self_for_chaining
    network = RobotLab::Network.new(name: "test")
    result = network.task(:robot1, @robot1, depends_on: :none)

    assert_equal network, result
  end

  def test_task_with_dependencies
    network = RobotLab::Network.new(name: "test")
    network.task(:robot1, @robot1, depends_on: :none)
    network.task(:robot2, @robot2, depends_on: [:robot1])

    assert_equal 2, network.robots.size
    assert_equal [:robot1], network.pipeline.step_dependencies[:robot2]
  end

  def test_task_with_optional_dependency
    network = RobotLab::Network.new(name: "test")
    network.task(:robot1, @robot1, depends_on: :optional)

    assert_includes network.pipeline.optional_steps, :robot1
  end

  def test_task_with_context
    network = RobotLab::Network.new(name: "test")
    network.task(:robot1, @robot1, context: { department: "billing" }, depends_on: :none)

    assert_equal 1, network.robots.size
  end

  def test_task_with_mcp_config
    network = RobotLab::Network.new(name: "test")
    mcp_config = [{ name: "test", transport: { type: "stdio", command: "test" } }]
    network.task(:robot1, @robot1, mcp: mcp_config, depends_on: :none)

    assert_equal 1, network.robots.size
  end

  def test_task_with_tools_config
    network = RobotLab::Network.new(name: "test")
    network.task(:robot1, @robot1, tools: %w[tool1 tool2], depends_on: :none)

    assert_equal 1, network.robots.size
  end

  # Robot access tests
  def test_robot_by_name_string
    robot = @robot1
    network = RobotLab::Network.new(name: "test") do
      task :robot1, robot, depends_on: :none
    end

    assert_equal robot, network.robot("robot1")
  end

  def test_robot_by_name_symbol
    robot = @robot1
    network = RobotLab::Network.new(name: "test") do
      task :robot1, robot, depends_on: :none
    end

    assert_equal robot, network.robot(:robot1)
  end

  def test_robot_returns_nil_for_unknown
    network = RobotLab::Network.new(name: "test")

    assert_nil network.robot("unknown")
  end

  def test_bracket_alias_for_robot
    robot = @robot1
    network = RobotLab::Network.new(name: "test") do
      task :robot1, robot, depends_on: :none
    end

    assert_equal robot, network["robot1"]
  end

  def test_available_robots_returns_all_robots
    robot1 = @robot1
    robot2 = @robot2
    network = RobotLab::Network.new(name: "test") do
      task :robot1, robot1, depends_on: :none
      task :robot2, robot2, depends_on: [:robot1]
    end

    robots = network.available_robots
    assert_equal 2, robots.size
    assert_includes robots, robot1
    assert_includes robots, robot2
  end

  # Add robot tests
  def test_add_robot
    network = RobotLab::Network.new(name: "test")
    network.add_robot(@robot1)

    assert_equal 1, network.robots.size
    assert_equal @robot1, network.robot("robot1")
  end

  def test_add_robot_returns_self
    network = RobotLab::Network.new(name: "test")
    result = network.add_robot(@robot1)

    assert_equal network, result
  end

  def test_add_robot_raises_if_name_exists
    network = RobotLab::Network.new(name: "test")
    network.add_robot(@robot1)
    duplicate = build_robot(name: "robot1", description: "Duplicate")

    error = assert_raises(ArgumentError) do
      network.add_robot(duplicate)
    end

    assert_match(/robot1/, error.message)
    assert_match(/already exists/, error.message)
  end

  # Serialization tests
  def test_to_h_exports_network_config
    robot1 = @robot1
    robot2 = @robot2
    network = RobotLab::Network.new(name: "test_network") do
      task :robot1, robot1, depends_on: :none
      task :robot2, robot2, depends_on: [:robot1]
    end

    hash = network.to_h

    assert_equal "test_network", hash[:name]
    assert_equal %w[robot1 robot2], hash[:robots].sort
    assert_equal %w[robot1 robot2], hash[:tasks].sort
    assert_equal [], hash[:optional_tasks]
  end

  def test_to_h_includes_optional_tasks
    robot1 = @robot1
    robot2 = @robot2
    network = RobotLab::Network.new(name: "test") do
      task :classifier, robot1, depends_on: :none
      task :billing, robot2, depends_on: :optional
    end

    hash = network.to_h

    assert_equal [:billing], hash[:optional_tasks]
  end

  # Visualization tests
  def test_visualize_returns_ascii
    robot1 = @robot1
    robot2 = @robot2
    network = RobotLab::Network.new(name: "test") do
      task :robot1, robot1, depends_on: :none
      task :robot2, robot2, depends_on: [:robot1]
    end

    result = network.visualize

    assert_kind_of String, result
  end

  def test_to_mermaid_returns_mermaid_format
    robot1 = @robot1
    robot2 = @robot2
    network = RobotLab::Network.new(name: "test") do
      task :robot1, robot1, depends_on: :none
      task :robot2, robot2, depends_on: [:robot1]
    end

    result = network.to_mermaid

    assert_kind_of String, result
    assert_match(/graph/, result)
  end

  def test_execution_plan_returns_plan
    robot1 = @robot1
    robot2 = @robot2
    network = RobotLab::Network.new(name: "test") do
      task :robot1, robot1, depends_on: :none
      task :robot2, robot2, depends_on: [:robot1]
    end

    result = network.execution_plan

    assert_kind_of String, result
  end
end
