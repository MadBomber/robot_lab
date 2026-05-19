# frozen_string_literal: true

require "test_helper"

class RobotLab::BusPollerTest < Minitest::Test
  def setup
    @poller = RobotLab::BusPoller.new
  end

  # Lifecycle
  def test_start_returns_self
    assert_same @poller, @poller.start
  end

  def test_stop_returns_self
    assert_same @poller, @poller.stop
  end

  def test_always_running
    assert @poller.running?
    @poller.stop
    assert @poller.running?
  end

  # Groups
  def test_default_group_exists
    assert_includes @poller.groups, :default
  end

  def test_add_group_registers_name
    @poller.add_group(:slow)
    assert_includes @poller.groups, :slow
  end

  def test_add_group_is_idempotent
    @poller.add_group(:slow)
    @poller.add_group(:slow)
    assert_equal 1, @poller.groups.count(:slow)
  end

  def test_groups_returns_dup
    groups = @poller.groups
    groups << :injected
    refute_includes @poller.groups, :injected
  end

  # Enqueue — happy path
  def test_enqueue_calls_process_delivery
    processed = []
    robot = stub_robot("bot") { |d| processed << d }

    delivery = Object.new
    @poller.enqueue(robot: robot, delivery: delivery)

    assert_equal [delivery], processed
  end

  def test_enqueue_serializes_concurrent_deliveries
    order      = []
    call_count = 0
    poller     = @poller

    # Build robot directly (no stub_robot) to avoid redefining process_delivery
    robot = Object.new
    robot.define_singleton_method(:name) { "bot" }
    robot.define_singleton_method(:process_delivery) do |d|
      order << d
      call_count += 1
      # On the first delivery, attempt to re-enqueue the second while still processing
      poller.enqueue(robot: self, delivery: :second) if call_count == 1
    end

    @poller.enqueue(robot: robot, delivery: :first)

    assert_equal %i[first second], order
  end

  def test_enqueue_clears_busy_flag_after_processing
    robot = stub_robot("bot") { |_d| }

    @poller.enqueue(robot: robot, delivery: :x)

    # Robot should no longer be marked busy
    refute @poller.instance_variable_get(:@robot_busy)["bot"]
  end

  # Error recovery
  def test_enqueue_clears_busy_flag_on_bus_error
    robot = stub_robot("bot") { |_d| raise RobotLab::BusError, "boom" }

    @poller.enqueue(robot: robot, delivery: :x)

    refute @poller.instance_variable_get(:@robot_busy)["bot"]
  end

  def test_enqueue_clears_busy_flag_on_unexpected_error
    robot = stub_robot("bot") { |_d| raise "unexpected" }

    @poller.enqueue(robot: robot, delivery: :x)

    refute @poller.instance_variable_get(:@robot_busy)["bot"]
  end

  # Group label passed through (informational only)
  def test_enqueue_accepts_group_keyword
    processed = []
    robot = stub_robot("bot") { |d| processed << d }

    @poller.enqueue(robot: robot, delivery: :x, group: :slow)

    assert_equal [:x], processed
  end

  def test_robot_queues_are_ractor_queue_instances
    robot = stub_robot("ractor_q_bot") { |_d| }

    @poller.enqueue(robot: robot, delivery: "msg1")

    queues = @poller.instance_variable_get(:@robot_queues)
    assert_instance_of RactorQueue, queues["ractor_q_bot"]
  end

  private

  # Builds a minimal robot-like object whose #process_delivery calls &block.
  def stub_robot(name, &)
    robot = Object.new
    robot.define_singleton_method(:name) { name }
    robot.define_singleton_method(:process_delivery, &)
    robot
  end
end
