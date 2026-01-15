# frozen_string_literal: true

require "test_helper"

# Simple mock for last_result in tests
class MockResult
  attr_reader :output

  def initialize(output: nil, export: nil)
    @output = output
    @export_data = export || { output: output }
  end

  def export
    @export_data
  end
end

class RobotLab::RouterModuleTest < Minitest::Test
  def setup
    @robot1 = build_robot(name: "robot1", template: :assistant)
    @robot2 = build_robot(name: "robot2", template: :assistant)
    @network = build_network(name: "test_network", robots: [@robot1, @robot2])
  end

  # Router::Args tests
  class ArgsTest < Minitest::Test
    def setup
      @robot = RobotLab::Robot.new(name: "test", template: :assistant)
      @network = RobotLab::Network.new(name: "test_network", robots: [@robot])
      @context = { message: "Hello", user_id: 123 }
    end

    def test_args_initialization
      args = RobotLab::Router::Args.new(
        context: @context,
        network: @network,
        call_count: 0
      )

      assert_equal @context, args.context
      assert_equal @network, args.network
      assert_equal 0, args.call_count
      assert_equal [], args.stack
      assert_nil args.last_result
    end

    def test_args_initialization_with_stack_and_last_result
      last_result = MockResult.new(export: { output: "test" })
      args = RobotLab::Router::Args.new(
        context: @context,
        network: @network,
        call_count: 2,
        stack: [@robot],
        last_result: last_result
      )

      assert_equal 2, args.call_count
      assert_equal [@robot], args.stack
      assert_equal last_result, args.last_result
    end

    def test_args_message_accessor
      args = RobotLab::Router::Args.new(
        context: @context,
        network: @network,
        call_count: 0
      )

      assert_equal "Hello", args.message
    end

    def test_args_message_with_missing_message_returns_nil
      args = RobotLab::Router::Args.new(
        context: { user_id: 123 },
        network: @network,
        call_count: 0
      )

      assert_nil args.message
    end

    def test_args_to_h
      last_result = MockResult.new(export: { output: "test" })
      args = RobotLab::Router::Args.new(
        context: @context,
        network: @network,
        call_count: 1,
        stack: [@robot],
        last_result: last_result
      )

      hash = args.to_h

      assert_equal @context, hash[:context]
      assert_equal 1, hash[:call_count]
      assert_equal ["test"], hash[:stack]
      assert_equal({ output: "test" }, hash[:last_result])
    end

    def test_args_to_h_with_nil_last_result
      args = RobotLab::Router::Args.new(
        context: @context,
        network: @network,
        call_count: 0
      )

      hash = args.to_h

      assert_nil hash[:last_result]
    end
  end

  # Router.call tests
  def test_call_returns_nil_with_nil_router
    args = build_args(call_count: 0)
    result = RobotLab::Router.call(nil, args)

    assert_nil result
  end

  def test_call_with_proc_router
    router = ->(args) { args.call_count.zero? ? @robot1 : nil }
    args = build_args(call_count: 0)

    result = RobotLab::Router.call(router, args)

    assert_equal [@robot1], result
  end

  def test_call_with_proc_router_returns_nil_when_proc_returns_nil
    router = ->(_args) { nil }
    args = build_args(call_count: 0)

    result = RobotLab::Router.call(router, args)

    assert_nil result
  end

  def test_call_with_proc_returning_array_of_robots
    router = ->(_args) { [@robot1, @robot2] }
    args = build_args(call_count: 0)

    result = RobotLab::Router.call(router, args)

    assert_equal [@robot1, @robot2], result
  end

  def test_call_with_proc_returning_robot_name_string
    router = ->(_args) { "robot1" }
    args = build_args(call_count: 0)

    result = RobotLab::Router.call(router, args)

    assert_equal [@robot1], result
  end

  def test_call_with_proc_returning_robot_name_symbol
    router = ->(_args) { :robot2 }
    args = build_args(call_count: 0)

    result = RobotLab::Router.call(router, args)

    assert_equal [@robot2], result
  end

  def test_call_with_proc_returning_array_of_names
    router = ->(_args) { ["robot1", :robot2] }
    args = build_args(call_count: 0)

    result = RobotLab::Router.call(router, args)

    assert_equal [@robot1, @robot2], result
  end

  def test_call_with_robot_as_router_on_first_call
    args = build_args(call_count: 0)
    result = RobotLab::Router.call(@robot1, args)

    assert_equal [@robot1], result
  end

  def test_call_with_robot_as_router_returns_nil_on_subsequent_calls
    args = build_args(call_count: 1)
    result = RobotLab::Router.call(@robot1, args)

    assert_nil result
  end

  def test_call_with_unsupported_router_type
    args = build_args(call_count: 0)
    result = RobotLab::Router.call("not_a_valid_router", args)

    assert_nil result
  end

  # Result normalization tests
  def test_call_compacts_nil_values_from_array
    router = ->(_args) { ["robot1", nil, :nonexistent] }
    args = build_args(call_count: 0)

    result = RobotLab::Router.call(router, args)

    assert_equal [@robot1], result
  end

  def test_call_returns_empty_array_when_all_resolved_to_nil
    router = ->(_args) { [:nonexistent1, :nonexistent2] }
    args = build_args(call_count: 0)

    result = RobotLab::Router.call(router, args)

    assert_equal [], result
  end

  def test_call_with_unknown_robot_name_returns_empty
    router = ->(_args) { "unknown_robot" }
    args = build_args(call_count: 0)

    result = RobotLab::Router.call(router, args)

    assert_equal [], result
  end

  # Router with context and call_count
  def test_router_receives_context
    captured_context = nil
    router = ->(args) { captured_context = args.context; nil }
    context = { message: "test", custom_data: "value" }
    args = build_args(call_count: 0, context: context)

    RobotLab::Router.call(router, args)

    assert_equal context, captured_context
  end

  def test_router_receives_call_count
    captured_counts = []
    router = ->(args) { captured_counts << args.call_count; args.call_count < 2 ? @robot1 : nil }

    [0, 1, 2].each do |count|
      args = build_args(call_count: count)
      RobotLab::Router.call(router, args)
    end

    assert_equal [0, 1, 2], captured_counts
  end

  def test_router_receives_stack
    router = ->(args) { args.stack.empty? ? @robot1 : nil }
    args = build_args(call_count: 0, stack: [])

    result = RobotLab::Router.call(router, args)
    assert_equal [@robot1], result

    args_with_stack = build_args(call_count: 1, stack: [@robot1])
    result_with_stack = RobotLab::Router.call(router, args_with_stack)
    assert_nil result_with_stack
  end

  def test_router_receives_last_result
    last_result = MockResult.new(output: "previous output")
    router = ->(args) { args.last_result&.output == "previous output" ? @robot2 : @robot1 }

    args_no_result = build_args(call_count: 0, last_result: nil)
    result1 = RobotLab::Router.call(router, args_no_result)
    assert_equal [@robot1], result1

    args_with_result = build_args(call_count: 1, last_result: last_result)
    result2 = RobotLab::Router.call(router, args_with_result)
    assert_equal [@robot2], result2
  end

  private

  def build_args(call_count:, context: {}, stack: [], last_result: nil)
    RobotLab::Router::Args.new(
      context: context,
      network: @network,
      call_count: call_count,
      stack: stack,
      last_result: last_result
    )
  end
end
