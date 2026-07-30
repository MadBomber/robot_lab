# frozen_string_literal: true

require "test_helper"

class RobotLab::Budget::LedgerTest < Minitest::Test
  def test_remaining_with_no_limit_is_infinite
    ledger = RobotLab::Budget::Ledger.new(limits: {})
    assert_equal Float::INFINITY, ledger.remaining(:tokens)
  end

  def test_remaining_reflects_full_limit_when_unconsumed
    ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 100 })
    assert_equal 100, ledger.remaining(:tokens)
  end

  def test_reserve_within_limit_succeeds
    ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 100 })
    ledger.reserve!(:tokens, 40)
    assert_equal 60, ledger.remaining(:tokens)
  end

  def test_reserve_beyond_limit_raises_budget_exceeded
    ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 100 })
    ledger.reserve!(:tokens, 100)

    assert_raises(RobotLab::BudgetExceeded) { ledger.reserve!(:tokens, 1) }
  end

  def test_reserve_on_unconfigured_dimension_never_raises
    ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 100 })
    ledger.reserve!(:cost, 1_000_000)
    assert_equal Float::INFINITY, ledger.remaining(:cost)
  end

  def test_reconcile_replaces_reservation_with_actual
    ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 100 })
    ledger.reserve!(:tokens, 100)
    ledger.reconcile!(:tokens, 100, 40)

    assert_equal 40, ledger.consumed[:tokens]
    assert_equal 60, ledger.remaining(:tokens)
  end

  def test_reconcile_actual_exceeding_reservation_is_recorded
    ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 100 })
    ledger.reserve!(:tokens, 100)
    ledger.reconcile!(:tokens, 100, 120)

    assert_equal 120, ledger.consumed[:tokens]
    assert_equal 0, ledger.remaining(:tokens)
  end

  def test_reserve_after_overrun_raises_even_for_zero_amount
    ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 100 })
    ledger.reserve!(:tokens, 100)
    ledger.reconcile!(:tokens, 100, 120)

    assert_raises(RobotLab::BudgetExceeded) { ledger.reserve!(:tokens, 0) }
  end

  def test_release_drops_reservation_without_recording_consumption
    ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 100 })
    ledger.reserve!(:tokens, 60)
    ledger.release!(:tokens, 60)

    assert_equal 0, ledger.consumed[:tokens]
    assert_equal 100, ledger.remaining(:tokens)
  end

  def test_release_floors_at_zero
    ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 100 })
    ledger.release!(:tokens, 60)
    assert_equal 100, ledger.remaining(:tokens)
  end

  def test_starting_consumed_is_honored
    ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 100 }, consumed: { tokens: 30 })
    assert_equal 70, ledger.remaining(:tokens)
  end

  def test_multiple_dimensions_are_independent
    ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 100, cost: 1.0 })
    ledger.reserve!(:tokens, 100)
    ledger.reconcile!(:tokens, 100, 100)

    assert_equal 0, ledger.remaining(:tokens)
    assert_equal 1.0, ledger.remaining(:cost)
  end
end
