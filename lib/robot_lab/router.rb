# frozen_string_literal: true

module RobotLab
  # Router module for robot selection strategies
  #
  # Routers determine which robot(s) should run at each step
  # in a network execution. Two router types are supported:
  #
  # 1. Function router (Proc) - Explicit, code-based routing
  # 2. Robot router (RoutingRobot) - LLM-based routing decisions
  #
  module Router
    # Arguments passed to function routers
    #
    # @example
    #   router = ->(args) {
    #     args[:call_count] == 0 ? classifier_robot : nil
    #   }
    #
    class Args
      attr_reader :input, :user_message, :network, :stack, :call_count, :last_result

      def initialize(input:, network:, call_count:, user_message: nil, stack: [], last_result: nil)
        @input = input
        @user_message = user_message
        @network = network
        @stack = stack
        @call_count = call_count
        @last_result = last_result
      end

      def to_h
        {
          input: input,
          user_message: user_message&.to_h,
          call_count: call_count,
          stack: stack.map(&:name),
          last_result: last_result&.export
        }
      end
    end

    class << self
      # Call a router to get next robots
      #
      # @param router [Proc, RoutingRobot, nil] The router
      # @param args [Args] Router arguments
      # @return [Array<Robot>, nil]
      #
      def call(router, args)
        return nil unless router

        result = case router
                 when Proc
                   router.call(args)
                 when RoutingRobot
                   call_routing_robot(router, args)
                 when Robot
                   # Single robot as router - just return it once
                   args.call_count.zero? ? router : nil
                 else
                   nil
                 end

        normalize_result(result, args.network)
      end

      private

      def call_routing_robot(router, args)
        # Run the routing robot
        result = router.run(
          args.input,
          network: args.network,
          state: args.network.state
        )

        # Get routing decision
        router.route(result: result, network: args.network, state: args.network.state)
      end

      def normalize_result(result, network)
        return nil if result.nil?

        robots = case result
                 when Array
                   result.map { |r| resolve_robot(r, network) }
                 when Robot
                   [result]
                 when String, Symbol
                   [resolve_robot(result, network)]
                 else
                   nil
                 end

        robots&.compact
      end

      def resolve_robot(ref, network)
        case ref
        when Robot
          ref
        when String, Symbol
          network.robots[ref.to_s]
        else
          nil
        end
      end
    end
  end
end
