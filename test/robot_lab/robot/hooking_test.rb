# frozen_string_literal: true

require "test_helper"

class RobotLab::Robot::HookingTest < Minitest::Test
  def test_hook_registries_is_defined_only_in_the_hooking_concern
    assert_equal RobotLab::Robot::Hooking,
                 RobotLab::Robot.instance_method(:hook_registries).owner
    refute RobotLab::Robot.private_method_defined?(:hook_registries, false)
  end

  def test_hook_registries_orders_global_network_then_robot
    robot = build_robot(name: "bot", system_prompt: "test")
    network = build_network(name: "net")

    assert_equal [RobotLab.hooks, network.hooks, robot.hooks],
                 robot.send(:hook_registries, network)
    assert_equal [RobotLab.hooks, nil, robot.hooks], robot.send(:hook_registries)
  end
end
