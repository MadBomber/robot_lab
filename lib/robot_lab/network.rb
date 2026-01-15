# frozen_string_literal: true

require "state_machines"

module RobotLab
  # Orchestrates multiple robots in a coordinated workflow
  #
  # Network manages robot coordination, memory sharing, and routing.
  # It provides the high-level interface for running multi-robot workflows.
  #
  # == When to Use a Network
  #
  # Use a Network when a task requires multiple specialized robots working
  # together. For simple tasks, a single Robot is sufficient.
  #
  # - *Single Robot*: Simple Q&A, single specialty tasks
  # - *Network*: Multi-step workflows, triage→specialist patterns, tasks
  #   requiring different expertise
  #
  # == How It Works
  #
  # 1. Router selects which robot handles the current step
  # 2. Robot executes using shared memory
  # 3. Result is stored in memory
  # 4. Router selects next robot (or nil to complete)
  # 5. Repeat until done or max_iter reached
  #
  # Robots execute sequentially, not concurrently. Each robot sees all
  # previous results and can read/write shared memory.
  #
  # @example Simple network
  #   network = Network.new(
  #     name: "support",
  #     robots: [classifier, billing_robot, technical_robot],
  #     router: ->(args) {
  #       return nil if args.call_count > 0
  #       args.network.memory.data[:category] == "billing" ? "billing_robot" : "technical_robot"
  #     }
  #   )
  #   result = network.run(message: "I have a billing question", customer: customer)
  #
  # @example Network with MCP and tools configuration
  #   network = Network.new(
  #     name: "support",
  #     robots: [robot1, robot2],
  #     mcp: :inherit,           # Use RobotLab.configuration.mcp
  #     tools: %w[search refund] # Only these tools available in network
  #   )
  #
  # @example Runtime memory injection
  #   network.run(message: "Help me", memory: { user_id: 123, tier: "premium" })
  #
  class Network
    # @!attribute [r] name
    #   @return [String] the unique identifier for the network
    # @!attribute [r] robots
    #   @return [Hash<String, Robot>] the robots in this network, keyed by name
    # @!attribute [r] default_model
    #   @return [String, Object] the default LLM model for robots without explicit models
    # @!attribute [r] router
    #   @return [Proc, nil] the routing logic to determine which robot handles each message
    # @!attribute [r] max_iter
    #   @return [Integer] the maximum number of iterations before stopping
    # @!attribute [r] history
    #   @return [Object, nil] the history adapter for conversation persistence
    # @!attribute [r] mcp
    #   @return [Array] the resolved MCP server configurations for this network
    # @!attribute [r] tools
    #   @return [Array<String>] the resolved tool names whitelist for this network
    attr_reader :name, :robots, :default_model, :router, :max_iter, :history, :mcp, :tools

    # @!attribute [r] memory
    #   @return [Memory] the network's inherent memory (shared with all robots)

    # Creates a new Network instance.
    #
    # @param name [String] the unique identifier for the network
    # @param robots [Array<Robot>, Hash<String, Robot>] the robots to include
    # @param memory [Memory, nil] the initial memory for network runs
    # @param default_model [String, nil] the default LLM model (defaults to config)
    # @param router [Proc, nil] routing logic to select robots for messages
    # @param max_iter [Integer, nil] maximum iterations (defaults to config)
    # @param history [Object, nil] history adapter for persistence
    # @param mcp [Symbol, Array] hierarchical MCP config (:none, :inherit, or server array)
    # @param tools [Symbol, Array] hierarchical tools config (:none, :inherit, or tool names)
    # @param enable_cache [Boolean] whether to enable semantic caching (default: true)
    #
    # @example Network with router logic
    #   Network.new(
    #     name: "support",
    #     robots: [classifier, handler],
    #     router: ->(args) { args.call_count.zero? ? "classifier" : nil }
    #   )
    def initialize(
      name:,
      robots:,
      memory: nil,
      default_model: nil,
      router: nil,
      max_iter: nil,
      history: nil,
      mcp: :none,
      tools: :none,
      enable_cache: true
    )
      @name = name.to_s
      @robots = normalize_robots(robots)
      @memory = memory || Memory.new(enable_cache: enable_cache)
      @default_model = default_model || RobotLab.configuration.default_model
      @router = router
      @max_iter = max_iter || RobotLab.configuration.max_iterations
      @history = history
      @mcp = resolve_mcp(mcp)
      @tools = resolve_tools(tools)
    end

    # Get the network's memory (returns a clone for isolated execution)
    #
    # @return [Memory]
    #
    def memory
      @memory.clone
    end

    # Reset the network's shared memory
    #
    # This clears the memory used by all robots when running in this network.
    # Individual robots have their own inherent memory for standalone use,
    # but that memory is NOT used during network execution.
    #
    # @return [self]
    #
    # @example
    #   network.run(message: "Remember this")
    #   network.reset_memory  # Clears shared memory for all robots
    #   network.run(message: "What did I say?")  # Won't remember
    #
    def reset_memory
      @memory.reset
      self
    end

    # Run the network with context
    #
    # @param router [Proc, nil] Override router
    # @param memory [Memory, Hash, nil] Runtime memory to merge
    # @param streaming [Proc, nil] Streaming callback
    # @param run_context [Hash] Context passed to all robots
    # @return [NetworkRun]
    #
    # @example Runtime memory injection
    #   network.run(message: "Help me", memory: { ticket_id: 456, user_tier: "premium" })
    #
    def run(router: nil, memory: nil, streaming: nil, **run_context, &block)
      # Prepare memory - use a clone of the network's memory
      run_memory = @memory.clone

      # Merge runtime memory if provided
      case memory
      when Memory
        run_memory = memory
      when Hash
        run_memory.merge!(memory)
      end

      # Create and execute network run
      network_run = NetworkRun.new(self, run_memory)
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

    # @!method [](name)
    #   Alias for {#robot}.
    #   @param name [String, Symbol] the robot name
    #   @return [Robot, nil]
    alias [] robot

    # Add a robot to the network
    #
    # @param robot [Robot] the robot instance to add
    # @return [self]
    # @raise [ArgumentError] if a robot with the same name already exists
    #
    # @example
    #   network.add_robot(new_robot)
    #
    def add_robot(robot)
      if @robots.key?(robot.name)
        raise ArgumentError, "Robot '#{robot.name}' already exists in network '#{@name}'"
      end

      @robots[robot.name] = robot
      self
    end

    # Replace an existing robot in the network
    #
    # @param robot [Robot] the robot instance to replace with
    # @return [Robot] the old robot that was replaced
    # @raise [ArgumentError] if no robot with that name exists
    #
    # @example
    #   old_robot = network.replace_robot(updated_billing)
    #
    def replace_robot(robot)
      unless @robots.key?(robot.name)
        raise ArgumentError, "Robot '#{robot.name}' does not exist in network '#{@name}'"
      end

      old_robot = @robots[robot.name]
      @robots[robot.name] = robot
      old_robot
    end

    # Remove a robot from the network
    #
    # @param name_or_robot [String, Symbol, Robot] the robot name or instance to remove
    # @return [Robot, nil] the removed robot, or nil if not found
    # @raise [ArgumentError] if parameter is neither a String, Symbol, nor Robot
    #
    # @example Remove by name
    #   removed = network.remove_robot("billing")
    #   network.remove_robot(:technical)
    #
    # @example Remove by instance
    #   network.remove_robot(billing_robot)
    #
    def remove_robot(name_or_robot)
      name = case name_or_robot
             when String, Symbol
               name_or_robot.to_s
             when Robot
               name_or_robot.name
             else
               raise ArgumentError, "Expected String, Symbol, or Robot, got #{name_or_robot.class}"
             end

      @robots.delete(name)
    end

    # Converts the network to a hash representation.
    #
    # @return [Hash] a hash containing the network's configuration
    def to_h
      {
        name: name,
        robots: robots.keys,
        default_model: default_model.respond_to?(:model_id) ? default_model.model_id : default_model,
        max_iter: max_iter,
        mcp: mcp,
        tools: tools,
        history: history ? true : nil
      }.compact
    end

    private

    def resolve_mcp(value)
      ToolConfig.resolve_mcp(value, parent_value: RobotLab.configuration.mcp)
    end

    def resolve_tools(value)
      ToolConfig.resolve_tools(value, parent_value: RobotLab.configuration.tools)
    end

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
