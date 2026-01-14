# frozen_string_literal: true

module RobotLab
  # Router module for robot selection strategies
  #
  # Routers determine which robot(s) should run at each step
  # in a network execution using lambda functions.
  #
  module Router
    # Arguments passed to function routers
    #
    # @example
    #   router = ->(args) {
    #     args.call_count == 0 ? classifier_robot : nil
    #   }
    #
    class Args
      attr_reader :context, :network, :stack, :call_count, :last_result

      def initialize(context:, network:, call_count:, stack: [], last_result: nil)
        @context = context
        @network = network
        @stack = stack
        @call_count = call_count
        @last_result = last_result
      end

      # Convenience accessor for message in context
      def message
        @context[:message]
      end

      def to_h
        {
          context: context,
          call_count: call_count,
          stack: stack.map(&:name),
          last_result: last_result&.export
        }
      end
    end

    class << self
      # Call a router to get next robots
      #
      # @param router [Proc, nil] The router lambda
      # @param args [Args] Router arguments
      # @return [Array<Robot>, nil]
      #
      def call(router, args)
        return nil unless router

        result = case router
                 when Proc
                   router.call(args)
                 when Robot
                   # Single robot as router - just return it once
                   args.call_count.zero? ? router : nil
                 else
                   nil
                 end

        normalize_result(result, args.network)
      end

      private

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
