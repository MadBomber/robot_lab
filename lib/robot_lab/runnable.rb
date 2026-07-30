# frozen_string_literal: true

module RobotLab
  # Shared interface for things you can run with a message: a single {Robot} or a
  # multi-robot {Network}. It lets callers treat them uniformly instead of
  # branching on `is_a?(RobotLab::Network)` — which otherwise spreads concrete
  # type knowledge across every consumer.
  #
  # Implementers provide:
  #   - #run(message = nil, **opts) — execute with the given message (both Robot
  #     and Network accept a positional message and keyword options)
  #   - #crew                       — the constituent robots, as an Array
  #   - #network?                   — true for a multi-robot network
  #
  # The rest (chief, robot_count, single?) derive from those.
  #
  # @example treat either uniformly
  #   runnable.run(prompt, mcp: :inherit, tools: :inherit)
  #   names = runnable.crew.map(&:name)
  #   show_network(runnable) if runnable.network?
  module Runnable
    # The constituent robots as an Array. A single Robot is a crew of one.
    #
    # @return [Array<Robot>]
    def crew
      raise NotImplementedError, "#{self.class} must implement #crew"
    end

    # The lead robot — the chief of the crew.
    #
    # @return [Robot, nil]
    def chief
      crew.first
    end

    # @return [Integer] number of constituent robots
    def robot_count
      crew.size
    end

    # @return [Boolean] true for a multi-robot network
    def network?
      false
    end

    # @return [Boolean] true for a single robot
    def single?
      !network?
    end
  end
end
