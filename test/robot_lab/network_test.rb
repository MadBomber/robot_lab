# frozen_string_literal: true

require "test_helper"

class RobotLab::NetworkTest < Minitest::Test
  def setup
    @robot1 = build_robot(name: "robot1", description: "First robot")
    @robot2 = build_robot(name: "robot2", description: "Second robot")
  end

  # Initialization tests
  def test_initialization_with_required_params
    network = RobotLab::Network.new(
      name: "test_network",
      robots: [@robot1]
    )

    assert_equal "test_network", network.name
  end

  def test_initialization_converts_name_to_string
    network = RobotLab::Network.new(
      name: :test_network,
      robots: [@robot1]
    )

    assert_equal "test_network", network.name
  end

  def test_initialization_with_robots_array
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1, @robot2]
    )

    assert_equal 2, network.robots.size
    assert network.robots.key?("robot1")
    assert network.robots.key?("robot2")
  end

  def test_initialization_with_robots_hash
    network = RobotLab::Network.new(
      name: "test",
      robots: { "robot1" => @robot1, "robot2" => @robot2 }
    )

    assert_equal 2, network.robots.size
  end

  def test_initialization_with_symbol_robot_keys
    network = RobotLab::Network.new(
      name: "test",
      robots: { robot1: @robot1 }
    )

    assert network.robots.key?("robot1")
  end

  def test_initialization_with_empty_robots
    network = RobotLab::Network.new(
      name: "test",
      robots: []
    )

    assert_equal({}, network.robots)
  end

  def test_initialization_with_custom_memory
    memory = RobotLab::Memory.new(data: { key: "value" })
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1],
      memory: memory
    )

    cloned_memory = network.memory
    assert_equal "value", cloned_memory.data[:key]
  end

  def test_initialization_with_custom_model
    custom_model = "gpt-4"
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1],
      default_model: custom_model
    )

    assert_equal custom_model, network.default_model
  end

  def test_initialization_uses_config_default_model
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )

    assert_equal RobotLab.configuration.default_model, network.default_model
  end

  def test_initialization_with_router
    router = ->(args) { "robot1" }
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1],
      router: router
    )

    assert_equal router, network.router
  end

  def test_initialization_with_max_iter
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1],
      max_iter: 5
    )

    assert_equal 5, network.max_iter
  end

  def test_initialization_uses_config_max_iterations
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )

    assert_equal RobotLab.configuration.max_iterations, network.max_iter
  end

  def test_initialization_with_history_config
    history_config = RobotLab::History::Config.new(
      get: ->(**_args) { [] },
      append_results: ->(**_args) { }
    )
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1],
      history: history_config
    )

    assert_equal history_config, network.history
  end

  # MCP and tools configuration
  def test_initialization_with_mcp_none
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1],
      mcp: :none
    )

    assert_equal [], network.mcp
  end

  def test_initialization_with_tools_none
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1],
      tools: :none
    )

    assert_equal [], network.tools
  end

  def test_initialization_with_tools_array
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1],
      tools: %w[search refund]
    )

    assert_equal %w[search refund], network.tools
  end

  # Memory access
  def test_memory_returns_clone
    memory = RobotLab::Memory.new(data: { key: "value" })
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1],
      memory: memory
    )

    cloned1 = network.memory
    cloned2 = network.memory

    refute_same cloned1, cloned2
  end

  # Robot access
  def test_available_robots_returns_all_robots
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1, @robot2]
    )

    robots = network.available_robots
    assert_equal 2, robots.size
    assert_includes robots, @robot1
    assert_includes robots, @robot2
  end

  def test_robot_by_name_string
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )

    assert_equal @robot1, network.robot("robot1")
  end

  def test_robot_by_name_symbol
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )

    assert_equal @robot1, network.robot(:robot1)
  end

  def test_robot_returns_nil_for_unknown
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )

    assert_nil network.robot("unknown")
  end

  def test_bracket_alias_for_robot
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )

    assert_equal @robot1, network["robot1"]
  end

  # Add and remove robots
  def test_add_robot
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )

    network.add_robot(@robot2)

    assert_equal 2, network.robots.size
    assert_equal @robot2, network.robot("robot2")
  end

  def test_add_robot_returns_self
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )

    result = network.add_robot(@robot2)

    assert_equal network, result
  end

  def test_add_robot_raises_if_name_exists
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )
    duplicate = build_robot(name: "robot1", description: "Duplicate")

    error = assert_raises(ArgumentError) do
      network.add_robot(duplicate)
    end

    assert_match(/robot1/, error.message)
    assert_match(/already exists/, error.message)
  end

  def test_replace_robot
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )
    replacement = build_robot(name: "robot1", description: "Replacement")

    old_robot = network.replace_robot(replacement)

    assert_equal @robot1, old_robot
    assert_equal 1, network.robots.size
    assert_equal "Replacement", network.robot("robot1").description
  end

  def test_replace_robot_raises_if_not_exists
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )
    new_robot = build_robot(name: "unknown", description: "New")

    error = assert_raises(ArgumentError) do
      network.replace_robot(new_robot)
    end

    assert_match(/unknown/, error.message)
    assert_match(/does not exist/, error.message)
  end

  def test_remove_robot_by_string
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1, @robot2]
    )

    removed = network.remove_robot("robot1")

    assert_equal @robot1, removed
    assert_equal 1, network.robots.size
    assert_nil network.robot("robot1")
  end

  def test_remove_robot_by_symbol
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1, @robot2]
    )

    removed = network.remove_robot(:robot1)

    assert_equal @robot1, removed
    assert_nil network.robot("robot1")
  end

  def test_remove_robot_by_instance
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1, @robot2]
    )

    removed = network.remove_robot(@robot1)

    assert_equal @robot1, removed
    assert_equal 1, network.robots.size
    assert_nil network.robot("robot1")
  end

  def test_remove_robot_returns_nil_for_unknown
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )

    removed = network.remove_robot("unknown")

    assert_nil removed
    assert_equal 1, network.robots.size
  end

  def test_remove_robot_raises_for_invalid_type
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1]
    )

    error = assert_raises(ArgumentError) do
      network.remove_robot(123)
    end

    assert_match(/Expected String, Symbol, or Robot/, error.message)
  end

  # Serialization
  def test_to_h_exports_network_config
    network = RobotLab::Network.new(
      name: "test_network",
      robots: [@robot1, @robot2],
      max_iter: 10,
      tools: %w[search]
    )

    hash = network.to_h

    assert_equal "test_network", hash[:name]
    assert_equal %w[robot1 robot2], hash[:robots].sort
    assert_equal 10, hash[:max_iter]
    assert_equal %w[search], hash[:tools]
  end

  def test_to_h_excludes_nil_values
    network = RobotLab::Network.new(
      name: "test",
      robots: []
    )

    hash = network.to_h

    refute hash.key?(:history)
    assert_equal [], hash[:mcp]
    assert_equal [], hash[:tools]
  end

  def test_to_h_with_history
    history_config = RobotLab::History::Config.new(
      get: ->(**_args) { [] }
    )
    network = RobotLab::Network.new(
      name: "test",
      robots: [],
      history: history_config
    )

    hash = network.to_h
    assert_equal true, hash[:history]
  end
end
