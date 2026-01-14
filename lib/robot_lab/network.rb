# frozen_string_literal: true

require "state_machines"

module RobotLab
  # Orchestrates multiple robots in a coordinated workflow
  #
  # Network manages robot coordination, state sharing, and routing.
  # It provides the high-level interface for running multi-robot workflows.
  #
  # @example Simple network
  #   network = Network.new(
  #     name: "support",
  #     robots: [classifier, billing_robot, technical_robot],
  #     router: ->(args) {
  #       return nil if args.call_count > 0
  #       args.network.state.data[:category] == "billing" ? "billing_robot" : "technical_robot"
  #     }
  #   )
  #   result = network.run(message: "I have a billing question", customer: customer)
  #
  class Network
    attr_reader :name, :robots, :default_model, :router, :max_iter, :history

    def initialize(
      name:,
      robots:,
      state: nil,
      default_model: nil,
      router: nil,
      max_iter: nil,
      history: nil
    )
      @name = name.to_s
      @robots = normalize_robots(robots)
      @state = state || State.new
      @default_model = default_model || RobotLab.configuration.default_model
      @router = router
      @max_iter = max_iter || RobotLab.configuration.max_iterations
      @history = history
    end

    # Get the base state (clone for execution)
    #
    # @return [State]
    #
    def state
      @state.clone
    end

    # Run the network with context
    #
    # @param router [Proc, nil] Override router
    # @param state [State, Hash, nil] Override state
    # @param streaming [Proc, nil] Streaming callback
    # @param run_context [Hash] Context passed to all robots
    # @return [NetworkRun]
    #
    def run(router: nil, state: nil, streaming: nil, **run_context, &block)
      # Prepare state
      run_state = case state
                  when State
                    state
                  when Hash
                    State.new(**state)
                  else
                    @state.clone
                  end

      # Create and execute network run
      network_run = NetworkRun.new(self, run_state)
      network_run.execute(
        router: router || @router,
        streaming: streaming || block,
        **run_context
      )
    end

    # Get available robots
    #
    # @return [Array<Robot>]
    #
    def available_robots
      @robots.values
    end

    # Get robot by name
    #
    # @param name [String, Symbol]
    # @return [Robot, nil]
    #
    def robot(name)
      @robots[name.to_s]
    end
    alias [] robot

    def to_h
      {
        name: name,
        robots: robots.keys,
        default_model: default_model.respond_to?(:model_id) ? default_model.model_id : default_model,
        max_iter: max_iter,
        history: history ? true : nil
      }.compact
    end

    private

    def normalize_robots(robots)
      case robots
      when Hash
        robots.transform_keys(&:to_s)
      when Array
        robots.each_with_object({}) { |a, h| h[a.name] = a }
      else
        {}
      end
    end
  end
end
