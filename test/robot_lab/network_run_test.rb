# frozen_string_literal: true

require "test_helper"

class RobotLab::NetworkRunTest < Minitest::Test
  def setup
    @robot1 = build_robot(name: "robot1")
    @robot2 = build_robot(name: "robot2")
    @network = RobotLab::Network.new(
      name: "test_network",
      robots: [@robot1, @robot2],
      max_iter: 10
    )
    @state = RobotLab::State.new
  end

  # Initialization tests
  def test_initialization
    run = RobotLab::NetworkRun.new(@network, @state)

    assert_equal @network, run.network
    assert_equal @state, run.state
    assert run.run_id.is_a?(String)
    assert_equal :pending, run.execution_state
  end

  def test_run_id_is_uuid_format
    run = RobotLab::NetworkRun.new(@network, @state)

    # UUID format validation
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i, run.run_id)
  end

  def test_each_run_has_unique_id
    run1 = RobotLab::NetworkRun.new(@network, @state)
    run2 = RobotLab::NetworkRun.new(@network, @state)

    refute_equal run1.run_id, run2.run_id
  end

  # Delegation tests
  def test_robots_delegates_to_network
    run = RobotLab::NetworkRun.new(@network, @state)

    assert_equal @network.robots, run.robots
  end

  def test_default_model_delegates_to_network
    run = RobotLab::NetworkRun.new(@network, @state)

    assert_equal @network.default_model, run.default_model
  end

  # Execute with no router
  def test_execute_with_no_router_returns_self
    run = RobotLab::NetworkRun.new(@network, @state)

    result = run.execute(router: nil)

    assert_equal run, result
    assert_equal :completed, run.execution_state
  end

  def test_execute_with_empty_router_completes_immediately
    run = RobotLab::NetworkRun.new(@network, @state)
    router = ->(_args) { nil }

    run.execute(router: router)

    assert_equal :completed, run.execution_state
    assert_equal 0, run.results.size
  end

  # Results tests
  def test_results_returns_state_results
    run = RobotLab::NetworkRun.new(@network, @state)

    assert_equal @state.results, run.results
  end

  def test_last_result_nil_when_no_results
    run = RobotLab::NetworkRun.new(@network, @state)

    assert_nil run.last_result
  end

  def test_new_results_empty_when_no_execution
    run = RobotLab::NetworkRun.new(@network, @state)
    run.execute(router: nil)

    assert_equal [], run.new_results
  end

  def test_new_results_excludes_pre_existing_results
    # Pre-populate state with existing result
    existing_result = RobotLab::RobotResult.new(
      robot_name: "previous",
      output: [],
      tool_calls: []
    )
    @state.append_result(existing_result)

    run = RobotLab::NetworkRun.new(@network, @state)
    run.execute(router: nil)

    # new_results should not include the pre-existing result
    assert_equal [], run.new_results
    assert_equal 1, run.results.size
  end

  # Serialization
  def test_to_h_exports_run_state
    run = RobotLab::NetworkRun.new(@network, @state)
    run.execute(router: nil)

    hash = run.to_h

    assert hash.key?(:run_id)
    assert_equal "test_network", hash[:network]
    assert_equal :completed, hash[:state]
    assert hash.key?(:counter)
    assert hash.key?(:stack)
    assert hash.key?(:results)
  end

  def test_to_h_includes_run_id
    run = RobotLab::NetworkRun.new(@network, @state)

    hash = run.to_h

    assert_equal run.run_id, hash[:run_id]
  end
end

# Router module tests
class RobotLab::RouterTest < Minitest::Test
  def setup
    @robot = build_robot(name: "robot1")
    @network = RobotLab::Network.new(
      name: "test",
      robots: [@robot]
    )
    @network_run = RobotLab::NetworkRun.new(@network, RobotLab::State.new)
  end

  # Router::Args tests
  def test_args_initialization
    args = RobotLab::Router::Args.new(
      context: { message: "Hello" },
      network: @network_run,
      call_count: 0
    )

    assert_equal({ message: "Hello" }, args.context)
    assert_equal @network_run, args.network
    assert_equal 0, args.call_count
    assert_equal [], args.stack
    assert_nil args.last_result
  end

  def test_args_with_stack
    args = RobotLab::Router::Args.new(
      context: {},
      network: @network_run,
      call_count: 0,
      stack: [@robot]
    )

    assert_equal [@robot], args.stack
  end

  def test_args_with_last_result
    result = RobotLab::RobotResult.new(
      robot_name: "robot1",
      output: [],
      tool_calls: []
    )
    args = RobotLab::Router::Args.new(
      context: {},
      network: @network_run,
      call_count: 1,
      last_result: result
    )

    assert_equal result, args.last_result
  end

  def test_args_message_convenience_accessor
    args = RobotLab::Router::Args.new(
      context: { message: "Hello" },
      network: @network_run,
      call_count: 0
    )

    assert_equal "Hello", args.message
  end

  def test_args_to_h
    result = RobotLab::RobotResult.new(
      robot_name: "robot1",
      output: [],
      tool_calls: []
    )
    args = RobotLab::Router::Args.new(
      context: { message: "Hello" },
      network: @network_run,
      call_count: 1,
      stack: [@robot],
      last_result: result
    )

    hash = args.to_h

    assert_equal({ message: "Hello" }, hash[:context])
    assert_equal 1, hash[:call_count]
    assert_equal ["robot1"], hash[:stack]
    assert hash.key?(:last_result)
  end

  # Router.call tests
  def test_call_with_nil_router_returns_nil
    args = build_router_args

    assert_nil RobotLab::Router.call(nil, args)
  end

  def test_call_with_proc_returning_nil
    router = ->(_args) { nil }
    args = build_router_args

    assert_nil RobotLab::Router.call(router, args)
  end

  def test_call_with_proc_returning_robot_name_string
    router = ->(_args) { "robot1" }
    args = build_router_args

    result = RobotLab::Router.call(router, args)

    assert_equal 1, result.size
    assert_equal @robot, result.first
  end

  def test_call_with_proc_returning_robot_name_symbol
    router = ->(_args) { :robot1 }
    args = build_router_args

    result = RobotLab::Router.call(router, args)

    assert_equal 1, result.size
    assert_equal @robot, result.first
  end

  def test_call_with_proc_returning_array_of_names
    robot2 = build_robot(name: "robot2")
    network = RobotLab::Network.new(name: "test", robots: [@robot, robot2])
    network_run = RobotLab::NetworkRun.new(network, RobotLab::State.new)

    router = ->(_args) { %w[robot1 robot2] }
    args = build_router_args(network_run: network_run)

    result = RobotLab::Router.call(router, args)

    assert_equal 2, result.size
  end

  def test_call_with_proc_returning_robot_instance
    router = ->(_args) { @robot }
    args = build_router_args

    result = RobotLab::Router.call(router, args)

    assert_equal 1, result.size
    assert_equal @robot, result.first
  end

  def test_call_returns_empty_for_unknown_robot_name
    router = ->(_args) { "unknown_robot" }
    args = build_router_args

    result = RobotLab::Router.call(router, args)

    assert_equal [], result
  end

  def test_call_filters_out_unknown_robots_from_array
    router = ->(_args) { %w[robot1 unknown_robot] }
    args = build_router_args

    result = RobotLab::Router.call(router, args)

    assert_equal 1, result.size
    assert_equal @robot, result.first
  end

  def test_call_with_conditional_routing
    router = ->(args) {
      args.call_count.zero? ? "robot1" : nil
    }

    args0 = build_router_args(call_count: 0)
    args1 = build_router_args(call_count: 1)

    result0 = RobotLab::Router.call(router, args0)
    result1 = RobotLab::Router.call(router, args1)

    assert_equal 1, result0.size
    assert_nil result1
  end

  def test_call_with_context_based_routing
    router = ->(args) {
      args.context[:category] == "billing" ? "robot1" : nil
    }

    billing_args = build_router_args(context: { category: "billing" })
    other_args = build_router_args(context: { category: "technical" })

    billing_result = RobotLab::Router.call(router, billing_args)
    other_result = RobotLab::Router.call(router, other_args)

    assert_equal 1, billing_result.size
    assert_nil other_result
  end

  private

  def build_router_args(network_run: nil, call_count: 0, context: { message: "Hello" })
    RobotLab::Router::Args.new(
      context: context,
      network: network_run || @network_run,
      call_count: call_count
    )
  end
end
