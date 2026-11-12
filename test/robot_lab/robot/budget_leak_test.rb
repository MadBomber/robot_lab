# frozen_string_literal: true

require "test_helper"

class RobotLab::Robot::BudgetLeakTest < Minitest::Test
  FakeResponse = Data.define(:content, :tool_calls, :stop_reason, :tokens)

  def test_failed_call_releases_its_budget_reservation
    robot = build_robot(name: "bot", system_prompt: "test", token_budget: 1_000)
    stub_ask(robot, failures: 1)

    assert_raises(RuntimeError) { robot.run("fails") }
    assert_equal 1_000, robot.budget_ledger.remaining(:tokens)

    robot.run("one")
    robot.run("two")

    assert_equal 20, robot.budget_ledger.consumed[:tokens]
    assert_equal 980, robot.budget_ledger.remaining(:tokens)
  end

  def test_reserve_budget_releases_earlier_dimensions_when_a_later_one_is_exhausted
    robot = build_robot(name: "bot", system_prompt: "test", token_budget: 1_000, cost_budget: 0.5)
    ledger = robot.budget_ledger
    ledger.reconcile!(:cost, 0, 0.6) # a prior call overspent cost

    assert_raises(RobotLab::BudgetExceeded) { robot.send(:reserve_budget!) }
    assert_equal 1_000, ledger.remaining(:tokens)
  end

  private

  def stub_ask(robot, failures:)
    response = FakeResponse.new(content: "ok", tool_calls: nil, stop_reason: "end_turn",
                                tokens: RubyLLM::Tokens.new(input: 6, output: 4))
    remaining_failures = failures
    robot.instance_variable_get(:@chat).define_singleton_method(:ask) do |_msg = nil, **_kw, &_b|
      raise "transient 503" if (remaining_failures -= 1) >= 0

      response
    end
  end
end
