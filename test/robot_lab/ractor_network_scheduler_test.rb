# frozen_string_literal: true

require "test_helper"
require "ractor_queue"

class RobotLab::RactorNetworkSchedulerTest < Minitest::Test
  # Test double: overrides execute_spec so no live LLM is needed.
  class StubScheduler < RobotLab::RactorNetworkScheduler
    def initialize(memory:, pool_size: :auto, &stub_block)
      super(memory: memory, pool_size: pool_size)
      @stub_block = stub_block || ->(_spec, _msg) { "stub result" }
    end

    private

    def execute_spec(spec, message)
      @stub_block.call(spec, message)
    end
  end

  def setup
    @memory = RobotLab::Memory.new(enable_cache: false)
  end

  def teardown
    @scheduler&.shutdown
  end

  def test_run_spec_returns_result_via_stub
    @scheduler = StubScheduler.new(memory: @memory) { |_spec, _msg| "echo result" }
    spec = RobotLab::RobotSpec.new(
      name:          "echo_bot",
      template:      nil,
      system_prompt: "You are an echo bot.".freeze,
      config_hash:   { model: "claude-sonnet-4" }.freeze
    )

    result = @scheduler.run_spec(spec, message: "hello")
    assert_equal "echo result", result
  end

  def test_respects_dependency_ordering
    order = []
    @scheduler = StubScheduler.new(memory: @memory) do |spec, _msg|
      order << spec.name
      "ok"
    end

    specs_with_deps = [
      {
        spec: RobotLab::RobotSpec.new(
          name: "first", template: nil, system_prompt: nil,
          config_hash: {}.freeze
        ),
        depends_on: :none
      },
      {
        spec: RobotLab::RobotSpec.new(
          name: "second", template: nil, system_prompt: nil,
          config_hash: {}.freeze
        ),
        depends_on: ["first"]
      }
    ]
    @scheduler.run_pipeline(specs_with_deps, message: "go")

    assert_equal ["first", "second"], order
  end

  def test_parallel_specs_both_run
    @scheduler = StubScheduler.new(memory: @memory) { |_spec, _msg| "ok" }

    specs_with_deps = [
      {
        spec: RobotLab::RobotSpec.new(
          name: "alpha", template: nil, system_prompt: nil,
          config_hash: {}.freeze
        ),
        depends_on: :none
      },
      {
        spec: RobotLab::RobotSpec.new(
          name: "beta", template: nil, system_prompt: nil,
          config_hash: {}.freeze
        ),
        depends_on: :none
      }
    ]
    results = @scheduler.run_pipeline(specs_with_deps, message: "go")
    assert_equal "ok", results["alpha"]
    assert_equal "ok", results["beta"]
  end

  def test_shutdown_is_idempotent
    @scheduler = StubScheduler.new(memory: @memory)
    @scheduler.shutdown
    @scheduler.shutdown  # should not raise
  end
end
