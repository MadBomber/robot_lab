# frozen_string_literal: true

module RobotLab
  # Lifecycle hooks for robot execution
  #
  # Lifecycle provides callbacks at various points during robot execution:
  # - enabled: Determine if robot should run in current context
  # - on_start: Pre-inference hook (can modify prompt/history or stop execution)
  # - on_response: Post-inference hook before tool invocation
  # - on_finish: Final hook after all tools complete
  #
  # All hooks receive a `memory` parameter providing scoped memory access
  # for the robot, with shared memory accessible via `memory.shared`.
  #
  # @example
  #   lifecycle = Lifecycle.new(
  #     enabled: ->(robot:, network:, memory:) { network.state.data[:active] },
  #     on_start: ->(robot:, network:, memory:, prompt:, history:) {
  #       memory.remember(:started_at, Time.now)
  #       { prompt: prompt, history: history, stop: false }
  #     },
  #     on_finish: ->(robot:, network:, memory:, result:) {
  #       memory.shared.remember(:last_robot, robot.name)
  #       result
  #     }
  #   )
  #
  class Lifecycle
    attr_accessor :enabled, :on_start, :on_response, :on_finish

    def initialize(enabled: nil, on_start: nil, on_response: nil, on_finish: nil)
      @enabled = enabled
      @on_start = on_start
      @on_response = on_response
      @on_finish = on_finish
    end

    # Check if robot is enabled in the current context
    #
    # @param robot [Robot] The robot being checked
    # @param network [NetworkRun, nil] The network context
    # @param memory [ScopedMemory, nil] The robot's scoped memory
    # @return [Boolean]
    #
    def enabled?(robot:, network: nil, memory: nil)
      return true unless @enabled

      @enabled.call(robot: robot, network: network, memory: memory)
    end

    # Call the on_start hook
    #
    # @param robot [Robot]
    # @param network [NetworkRun, nil]
    # @param memory [ScopedMemory, nil] The robot's scoped memory
    # @param prompt [Array<Message>]
    # @param history [Array<Message>]
    # @return [Hash] { prompt:, history:, stop: }
    #
    def call_on_start(robot:, network:, memory:, prompt:, history:)
      return { prompt: prompt, history: history, stop: false } unless @on_start

      result = @on_start.call(
        robot: robot,
        network: network,
        memory: memory,
        prompt: prompt,
        history: history
      )

      # Normalize result
      {
        prompt: result[:prompt] || prompt,
        history: result[:history] || history,
        stop: result[:stop] || false
      }
    end

    # Call the on_response hook
    #
    # @param robot [Robot]
    # @param network [NetworkRun, nil]
    # @param memory [ScopedMemory, nil] The robot's scoped memory
    # @param result [RobotResult]
    # @return [RobotResult]
    #
    def call_on_response(robot:, network:, memory:, result:)
      return result unless @on_response

      @on_response.call(robot: robot, network: network, memory: memory, result: result) || result
    end

    # Call the on_finish hook
    #
    # @param robot [Robot]
    # @param network [NetworkRun, nil]
    # @param memory [ScopedMemory, nil] The robot's scoped memory
    # @param result [RobotResult]
    # @return [RobotResult]
    #
    def call_on_finish(robot:, network:, memory:, result:)
      return result unless @on_finish

      @on_finish.call(robot: robot, network: network, memory: memory, result: result) || result
    end

    def to_h
      {
        enabled: @enabled ? true : nil,
        on_start: @on_start ? true : nil,
        on_response: @on_response ? true : nil,
        on_finish: @on_finish ? true : nil
      }.compact
    end
  end

  # Extended lifecycle for routing robots
  #
  # Adds the on_route callback which determines the next robot(s) to run.
  #
  class RoutingLifecycle < Lifecycle
    attr_accessor :on_route

    def initialize(on_route:, **kwargs)
      super(**kwargs)
      @on_route = on_route
    end

    # Determine next robots based on result
    #
    # @param robot [RoutingRobot] The routing robot
    # @param network [NetworkRun]
    # @param memory [ScopedMemory, nil] The robot's scoped memory
    # @param result [RobotResult]
    # @return [Array<String>, nil] Robot names to run next
    #
    def call_on_route(robot:, network:, memory:, result:)
      return nil unless @on_route

      result = @on_route.call(robot: robot, network: network, memory: memory, result: result)

      # Normalize to array of names
      case result
      when Array
        result.map { |a| a.respond_to?(:name) ? a.name : a.to_s }
      when String, Symbol
        [result.to_s]
      when Robot
        [result.name]
      else
        nil
      end
    end

    def to_h
      super.merge(on_route: @on_route ? true : nil).compact
    end
  end
end
