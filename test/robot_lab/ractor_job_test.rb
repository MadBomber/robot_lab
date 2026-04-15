# frozen_string_literal: true

require "test_helper"
require "ractor_queue"

class RobotLab::RactorJobTest < Minitest::Test
  def test_ractor_job_is_shareable
    reply_q = RactorQueue.new(capacity: 1)
    job = RobotLab::RactorJob.new(
      id: "abc".freeze,
      type: :tool,
      payload: { tool_class: "MyTool", args: { x: 1 }.freeze }.freeze,
      reply_queue: reply_q
    )
    assert Ractor.shareable?(job)
  end

  def test_ractor_job_error_is_shareable
    err = RobotLab::RactorJobError.new(message: "boom".freeze, backtrace: ["line 1"].freeze)
    assert Ractor.shareable?(err)
  end

  def test_robot_spec_is_shareable
    spec = RobotLab::RobotSpec.new(
      name: "bot".freeze,
      template: nil,
      system_prompt: "Be helpful.".freeze,
      config_hash: { model: "claude-sonnet-4" }.freeze
    )
    assert Ractor.shareable?(spec)
  end

  def test_ractor_boundary_error_is_subclass_of_error
    assert RobotLab::RactorBoundaryError < RobotLab::Error
  end
end
