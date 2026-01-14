# frozen_string_literal: true

module RobotLab
  # Specialized robot for routing decisions in networks
  #
  # RoutingRobot extends Robot with an on_route callback that
  # determines which robot(s) should run next based on the
  # current result and network state.
  #
  # @example
  #   routing_robot = RoutingRobot.new(
  #     name: "router",
  #     system: "Analyze requests and route to appropriate robots",
  #     on_route: ->(robot:, network:, memory:, result:) {
  #       # Use memory to track routing decisions
  #       memory.remember(:last_route, result.last_text_content)
  #
  #       # Return robot name(s) or nil to stop
  #       if result.last_text_content&.include?("billing")
  #         "billing_robot"
  #       else
  #         "support_robot"
  #       end
  #     }
  #   )
  #
  class RoutingRobot < Robot
    attr_reader :on_route

    def initialize(name:, system:, on_route:, **kwargs)
      @on_route = on_route

      # Create routing lifecycle
      lifecycle = RoutingLifecycle.new(
        on_route: on_route,
        **(kwargs.delete(:lifecycle)&.to_h || {})
      )

      super(name: name, system: system, lifecycle: lifecycle, **kwargs)
    end

    # Determine next robots after running
    #
    # @param result [RobotResult] The routing robot's result
    # @param network [NetworkRun] The network context
    # @param state [State, nil] State containing memory
    # @return [Array<String>, nil] Robot names to run next
    #
    def route(result:, network:, state: nil)
      mem = state ? memory(state) : nil
      @lifecycle.call_on_route(
        robot: self,
        network: network,
        memory: mem,
        result: result
      )
    end

    def to_h
      super.merge(routing: true)
    end
  end

  # Default routing robot used when no router is specified
  #
  # Uses tools to select robots or signal completion:
  # - select_robot: Choose an robot to handle the request
  # - done: Signal that the task is complete
  #
  module DefaultRouter
    class << self
      def create(network)
        RoutingRobot.new(
          name: "default_router",
          system: build_system_prompt(network),
          tools: [select_robot_tool, done_tool],
          on_route: method(:extract_route)
        )
      end

      private

      def build_system_prompt(network)
        robot_descriptions = network.robots.values.map do |robot|
          "<robot><name>#{robot.name}</name><description>#{robot.description}</description></robot>"
        end.join("\n")

        <<~PROMPT
          You are an orchestrator that routes requests to appropriate robots.

          Available robots:
          #{robot_descriptions}

          Your responsibilities:
          1. Analyze the user's request and conversation history
          2. Determine which robot is best suited to handle the request
          3. Call select_robot with the robot name and your reasoning
          4. When the task is complete, call done with a summary

          Always provide clear reasoning for your routing decisions.
        PROMPT
      end

      def select_robot_tool
        Tool.new(
          name: "select_robot",
          description: "Select an robot to handle the current request",
          parameters: {
            type: "object",
            properties: {
              name: {
                type: "string",
                description: "Name of the robot to select"
              },
              reason: {
                type: "string",
                description: "Reason for selecting this robot"
              }
            },
            required: %w[name reason]
          },
          handler: ->(input, network:, **_opts) {
            robot = network.robots[input[:name]]
            raise ToolNotFoundError, "Robot not found: #{input[:name]}" unless robot

            { selected: input[:name], reason: input[:reason] }
          }
        )
      end

      def done_tool
        Tool.new(
          name: "done",
          description: "Signal that the task is complete",
          parameters: {
            type: "object",
            properties: {
              summary: {
                type: "string",
                description: "Summary of what was accomplished"
              }
            },
            required: []
          },
          handler: ->(input, **_opts) {
            { done: true, summary: input[:summary] }
          }
        )
      end

      def extract_route(robot:, network:, memory:, result:)
        # Look for select_robot tool calls
        result.tool_calls.each do |tool_result|
          content = tool_result.content
          next unless content.is_a?(Hash)

          if content[:data]&.dig(:selected)
            return [content[:data][:selected]]
          elsif content[:data]&.dig(:done)
            return nil
          end
        end

        nil
      end
    end
  end
end
