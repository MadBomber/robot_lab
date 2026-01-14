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

  def test_initialization_with_custom_state
    state = RobotLab::State.new(data: { key: "value" })
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1],
      state: state
    )

    cloned_state = network.state
    assert_equal "value", cloned_state.data[:key]
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

  # State access
  def test_state_returns_clone
    state = RobotLab::State.new(data: { key: "value" })
    network = RobotLab::Network.new(
      name: "test",
      robots: [@robot1],
      state: state
    )

    cloned1 = network.state
    cloned2 = network.state

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
