# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    # Token/cost budget enforcement for a single Robot, backed by a
    # RobotLab::Budget::Ledger.
    #
    # Two layers of enforcement:
    # - reserve_budget!/reconcile_budget! wrap each LLM call. reserve_budget!
    #   raises BudgetExceeded up front when a *prior* call already pushed
    #   usage over budget, so a robot with an exhausted budget refuses
    #   further calls instead of spending on them.
    # - enforce_token_budget!/enforce_cost_budget! run after the call
    #   completes and raise InferenceError when *this* call's actual usage
    #   pushed cumulative usage over budget — unavoidable for the call that
    #   causes the overage, since token/cost totals aren't known until the
    #   response comes back.
    module Budget
      private

      # @return [RobotLab::Budget::Ledger, nil] nil when neither token_budget
      #   nor cost_budget is configured
      def build_budget_ledger
        limits = { tokens: @config.token_budget, cost: @config.cost_budget }.compact
        return nil if limits.empty?

        RobotLab::Budget::Ledger.new(limits: limits)
      end

      def enforce_token_budget!
        budget = @config.token_budget
        return unless budget && @total_input_tokens + @total_output_tokens > budget

        raise InferenceError,
              "Token budget exceeded: #{@total_input_tokens + @total_output_tokens} tokens used, budget is #{budget}"
      end

      def enforce_cost_budget!
        budget = @config.cost_budget
        return unless budget && @budget_ledger

        consumed = @budget_ledger.consumed[:cost]
        return unless consumed > budget

        raise InferenceError,
              format("Cost budget exceeded: $%<consumed>.6f used, budget is $%<budget>.6f",
                     consumed: consumed, budget: budget)
      end

      # Reserves whatever remains of each configured budget dimension
      # before attempting the LLM call.
      #
      # @return [Hash{Symbol=>Numeric}] the amount reserved per dimension, to pass to reconcile_budget!
      # @raise [RobotLab::BudgetExceeded] if a dimension is already exhausted
      def reserve_budget!
        return {} unless @budget_ledger

        @budget_ledger.limits.each_key.with_object({}) do |dimension, reservation|
          amount = @budget_ledger.remaining(dimension)
          @budget_ledger.reserve!(dimension, amount)
          reservation[dimension] = amount
        end
      end

      # Replaces a reservation from reserve_budget! with the actual usage
      # from this call.
      #
      # @param reservation [Hash{Symbol=>Numeric}] the value returned by reserve_budget!
      # @param response [Object] the raw LLM response, used to extract actual cost
      # @param result [RobotResult] the built result, used to extract actual tokens
      def reconcile_budget!(reservation, response:, result:)
        return unless reservation&.any?

        actual = { tokens: result.input_tokens + result.output_tokens, cost: extract_cost(response) }
        reservation.each_pair { |dimension, amount| @budget_ledger.reconcile!(dimension, amount, actual[dimension] || 0) }
      end

      # @param response [Object] the raw LLM response
      # @return [Float] the response's total cost, or 0.0 when unavailable (no pricing data)
      def extract_cost(response)
        return 0.0 unless response.respond_to?(:cost)

        response.cost.total.to_f
      rescue StandardError
        0.0
      end
    end
  end
end
