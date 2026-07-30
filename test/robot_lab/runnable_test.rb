# frozen_string_literal: true

require "test_helper"

class RobotLab::RunnableTest < Minitest::Test
  def test_robot_is_runnable_crew_of_one
    robot = build_robot(name: "solo")

    assert_kind_of RobotLab::Runnable, robot
    assert_equal [robot], robot.crew
    assert_equal robot, robot.chief
    assert_equal 1, robot.robot_count
    refute robot.network?
    assert robot.single?
  end

  def test_network_is_runnable_crew_of_many
    a = build_robot(name: "a")
    b = build_robot(name: "b")
    network = build_network(name: "crew") do
      task :a, a, depends_on: :none
      task :b, b, depends_on: [:a]
    end

    assert_kind_of RobotLab::Runnable, network
    assert_equal %w[a b], network.crew.map(&:name)
    assert_equal a, network.chief
    assert_equal 2, network.robot_count
    assert network.network?
    refute network.single?
  end

  def test_network_run_accepts_positional_message_like_robot
    robot = build_robot(name: "a")
    network = build_network(name: "n") { task :a, robot, depends_on: :none }
    captured = nil
    network.instance_variable_get(:@pipeline).define_singleton_method(:call_parallel) do |result, **|
      captured = result.context[:run_params]
      result
    end

    network.run("positional msg")
    assert_equal "positional msg", captured[:message]
  end

  def test_network_run_keyword_message_still_works
    robot = build_robot(name: "a")
    network = build_network(name: "n") { task :a, robot, depends_on: :none }
    captured = nil
    network.instance_variable_get(:@pipeline).define_singleton_method(:call_parallel) do |result, **|
      captured = result.context[:run_params]
      result
    end

    network.run(message: "keyword msg")
    assert_equal "keyword msg", captured[:message]
  end

  def test_runnable_crew_is_required_by_implementers
    klass = Class.new { include RobotLab::Runnable }
    assert_raises(NotImplementedError) { klass.new.crew }
  end
end
