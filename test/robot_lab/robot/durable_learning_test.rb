# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RobotLab::Robot::DurableLearningTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("robot_lab_robot_durable_test")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_learn_false_does_not_set_durable_store
    robot = RobotLab::Robot.new(name: "no_learn", template: :assistant)
    assert_nil robot.durable_store
  end

  def test_learn_true_sets_durable_store
    robot = RobotLab::Robot.new(
      name:         "learner",
      template:     :assistant,
      learn:        true,
      learn_domain: "test domain",
      store_path:   @tmpdir
    )
    refute_nil robot.durable_store
  end

  def test_learn_true_adds_recall_and_record_tools
    robot = RobotLab::Robot.new(
      name:         "learner",
      template:     :assistant,
      learn:        true,
      learn_domain: "test domain",
      store_path:   @tmpdir
    )
    tool_classes = robot.local_tools.map { |t| t.is_a?(Class) ? t : t.class }
    assert_includes tool_classes, RobotLab::RecallKnowledge
    assert_includes tool_classes, RobotLab::RecordKnowledge
  end

  def test_learn_domain_readable
    robot = RobotLab::Robot.new(
      name:         "learner",
      template:     :assistant,
      learn:        true,
      learn_domain: "newsletter curation",
      store_path:   @tmpdir
    )
    assert_equal "newsletter curation", robot.learn_domain
  end

  def test_learn_true_seeds_learnings_from_existing_store
    store = RobotLab::Durable::Store.new(path: @tmpdir)
    store.record(
      RobotLab::Durable::Entry.new(
        content:    "Skip Python-only tools",
        reasoning:  "Ruby-only context",
        category:   :preference,
        domain:     "test domain",
        confidence: 0.5,
        use_count:  2,
        created_at: "2026-05-06T12:00:00Z",
        updated_at: "2026-05-06T12:00:00Z"
      )
    )

    robot = RobotLab::Robot.new(
      name:         "learner",
      template:     :assistant,
      learn:        true,
      learn_domain: "test domain",
      store_path:   @tmpdir
    )

    assert robot.learnings.any? { |l| l.include?("Skip Python-only tools") }
  end

  def test_learn_false_adds_no_extra_tools
    robot = RobotLab::Robot.new(name: "no_learn", template: :assistant)
    tool_classes = robot.local_tools.map { |t| t.is_a?(Class) ? t : t.class }
    refute_includes tool_classes, RobotLab::RecallKnowledge
    refute_includes tool_classes, RobotLab::RecordKnowledge
  end
end
