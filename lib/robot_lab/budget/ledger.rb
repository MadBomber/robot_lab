# frozen_string_literal: true

module RobotLab
  module Budget
    # Thread-safe reserve/reconcile ledger for tracking consumption against
    # per-dimension limits (e.g. :tokens, :cost).
    #
    # Call +reserve!+ before doing billable work, so an already-exhausted
    # budget is caught before the work is attempted rather than after.
    # Once the work completes, +reconcile!+ replaces the reservation with
    # the actual amount consumed (which may be more or less than what was
    # reserved — LLM call sizes aren't known in advance). +release!+ drops
    # an unused reservation without recording any consumption.
    #
    # A dimension with no configured limit is treated as unlimited:
    # +reserve!+ never raises for it and +remaining+ returns
    # +Float::INFINITY+.
    #
    # @example
    #   ledger = RobotLab::Budget::Ledger.new(limits: { tokens: 10_000, cost: 0.50 })
    #   held = ledger.remaining(:tokens)
    #   ledger.reserve!(:tokens, held)
    #   # ... do the billable work ...
    #   ledger.reconcile!(:tokens, held, actual_tokens_used)
    class Ledger
      # @!attribute [r] limits
      #   @return [Hash{Symbol=>Numeric}] per-dimension ceilings
      # @!attribute [r] consumed
      #   @return [Hash{Symbol=>Numeric}] actual amount consumed per dimension so far
      attr_reader :limits, :consumed

      # @param limits [Hash{Symbol=>Numeric}] per-dimension ceilings; a dimension absent
      #   from this hash is treated as unlimited
      # @param consumed [Hash{Symbol=>Numeric}] starting consumption (e.g. restored from a prior run)
      def initialize(limits: {}, consumed: {})
        @mutex = Mutex.new
        @limits = limits
        @consumed = Hash.new(0).merge(consumed)
        @reserved = Hash.new(0)
      end

      # Reserves +amount+ against +key+'s remaining budget.
      #
      # A no-op (never raises) when +key+ has no configured limit.
      #
      # @param key [Symbol] the budget dimension
      # @param amount [Numeric] the amount to reserve
      # @raise [RobotLab::BudgetExceeded] if the reservation would exceed the limit
      # @return [void]
      def reserve!(key, amount)
        @mutex.synchronize do
          limit = @limits[key]
          next unless limit

          if amount > headroom(key, limit)
            raise BudgetExceeded,
                  "budget exceeded for #{key}: #{@consumed[key] + @reserved[key] + amount} > #{limit}"
          end

          @reserved[key] += amount
        end
      end

      # Replaces a prior reservation with the actual amount consumed.
      #
      # @param key [Symbol] the budget dimension
      # @param reserved_amount [Numeric] the amount previously passed to +reserve!+
      # @param actual_amount [Numeric] the amount actually consumed
      # @return [void]
      def reconcile!(key, reserved_amount, actual_amount)
        @mutex.synchronize do
          @reserved[key] = [0, @reserved[key] - reserved_amount].max
          @consumed[key] += actual_amount
        end
      end

      # Drops a reservation without recording any consumption (e.g. the
      # reserved work was skipped).
      #
      # @param key [Symbol] the budget dimension
      # @param amount [Numeric] the amount previously passed to +reserve!+
      # @return [void]
      def release!(key, amount)
        @mutex.synchronize { @reserved[key] = [0, @reserved[key] - amount].max }
      end

      # @param key [Symbol] the budget dimension
      # @return [Numeric] remaining budget for +key+, floored at 0; +Float::INFINITY+ when unlimited
      def remaining(key)
        @mutex.synchronize do
          limit = @limits[key]
          next Float::INFINITY unless limit

          [headroom(key, limit), 0].max
        end
      end

      private

      # Unfloored budget left for +key+ (negative after an overrun). Shared by
      # #reserve! and #remaining so that, while headroom is non-negative, reserving
      # exactly what #remaining reports can't trip on Float rounding.
      # Caller must hold @mutex.
      #
      # @param key [Symbol] the budget dimension
      # @param limit [Numeric] the configured limit for +key+
      # @return [Numeric]
      def headroom(key, limit) = limit - @consumed[key] - @reserved[key]
    end
  end
end
