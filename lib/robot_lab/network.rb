# frozen_string_literal: true

require "simple_flow"

module RobotLab
  # Orchestrates multiple robots in a pipeline workflow
  #
  # Network is a thin wrapper around SimpleFlow::Pipeline that provides
  # a clean DSL for defining robot workflows with sequential, parallel,
  # and conditional execution.
  #
  # == Shared Memory
  #
  # Networks provide a shared reactive memory that all robots can read and write.
  # Robots can subscribe to memory keys and be notified when values change,
  # or use blocking reads to wait for values from other robots.
  #
  # == Broadcast Messages
  #
  # Networks support a broadcast channel for network-wide announcements.
  # Use `broadcast` to send messages to all robots, and `on_broadcast` to
  # register handlers for incoming broadcasts.
  #
  # @example Sequential execution
  #   network = RobotLab.create_network(name: "pipeline") do
  #     task :analyst, analyst_robot, depends_on: :none
  #     task :writer, writer_robot, depends_on: [:analyst]
  #   end
  #
  # @example With per-task context
  #   network = RobotLab.create_network(name: "support") do
  #     task :classifier, classifier_robot, depends_on: :none
  #     task :billing, billing_robot,
  #          context: { department: "billing" },
  #          tools: [RefundTool],
  #          depends_on: :optional
  #   end
  #
  # @example Parallel execution with shared memory
  #   network = RobotLab.create_network(name: "analysis") do
  #     task :fetch, fetcher_robot, depends_on: :none
  #     task :sentiment, sentiment_robot, depends_on: [:fetch]
  #     task :entities, entity_robot, depends_on: [:fetch]
  #     task :summarize, summary_robot, depends_on: [:sentiment, :entities]
  #   end
  #
  #   # In sentiment_robot:
  #   memory.set(:sentiment, analyze_sentiment(text))
  #
  #   # In summarize_robot:
  #   results = memory.get(:sentiment, :entities, wait: 60)
  #
  # @example Broadcasting
  #   network.on_broadcast do |message|
  #     puts "Received: #{message[:event]}"
  #   end
  #
  #   network.broadcast(event: :pause, reason: "rate limit")
  #
  class Network
    # Reserved key for broadcast messages in memory
    BROADCAST_KEY = :_network_broadcast

    # @!attribute [r] name
    #   @return [String] unique identifier for the network
    # @!attribute [r] pipeline
    #   @return [SimpleFlow::Pipeline] the underlying pipeline
    # @!attribute [r] robots
    #   @return [Hash<String, Robot>] robots in this network, keyed by name
    # @!attribute [r] memory
    #   @return [Memory] shared memory for all robots in the network
    attr_reader :name, :pipeline, :robots, :memory

    # Creates a new Network instance.
    #
    # @param name [String] unique identifier for the network
    # @param concurrency [Symbol] concurrency model (:auto, :threads, :async)
    # @param memory [Memory, nil] optional pre-configured memory instance
    # @yield Block for defining pipeline tasks
    #
    # @example
    #   network = Network.new(name: "support") do
    #     task :classifier, classifier, depends_on: :none
    #     task :billing, billing_robot, context: { dept: "billing" }, depends_on: :optional
    #   end
    #
    def initialize(name:, concurrency: :auto, memory: nil, &block)
      @name = name.to_s
      @robots = {}
      @tasks = {}
      @pipeline = SimpleFlow::Pipeline.new(concurrency: concurrency)
      @memory = memory || Memory.new(network_name: @name)
      @broadcast_handlers = []

      instance_eval(&block) if block_given?
    end

    # Add a robot as a pipeline task with optional per-task configuration
    #
    # @param name [Symbol] task name
    # @param robot [Robot] the robot instance
    # @param context [Hash] task-specific context (deep-merged with run params)
    # @param mcp [Symbol, Array] MCP server config (:none, :inherit, or array)
    # @param tools [Symbol, Array] tools config (:none, :inherit, or array)
    # @param memory [Memory, Hash, nil] task-specific memory
    # @param depends_on [Symbol, Array<Symbol>] dependencies (:none, :optional, or task names)
    # @return [self]
    #
    # @example Entry point task
    #   task :classifier, classifier_robot, depends_on: :none
    #
    # @example Task with context and tools
    #   task :billing, billing_robot,
    #        context: { department: "billing", escalation: 2 },
    #        tools: [RefundTool, InvoiceTool],
    #        depends_on: :optional
    #
    # @example Task with dependencies
    #   task :writer, writer_robot, depends_on: [:analyst]
    #
    def task(name, robot, context: {}, mcp: :none, tools: :none, memory: nil, depends_on: :none)
      task_wrapper = Task.new(
        name: name,
        robot: robot,
        context: context,
        mcp: mcp,
        tools: tools,
        memory: memory
      )

      @robots[name.to_s] = robot
      @tasks[name.to_s] = task_wrapper
      @pipeline.step(name, task_wrapper, depends_on: depends_on)
      self
    end

    # Define a parallel execution block
    #
    # @param name [Symbol, nil] optional name for the parallel group
    # @param depends_on [Symbol, Array] dependencies for this group
    # @yield Block containing task definitions
    # @return [self]
    #
    # @example Named parallel group
    #   parallel :fetch_data, depends_on: :validate do
    #     task :fetch_orders, orders_robot
    #     task :fetch_products, products_robot
    #   end
    #   task :process, processor, depends_on: :fetch_data
    #
    def parallel(name = nil, depends_on: :none, &block)
      @pipeline.parallel(name, depends_on: depends_on, &block)
      self
    end

    # Run the network with the given context
    #
    # All robots share the network's memory during execution. The memory
    # is passed to each robot and can be used for inter-robot communication.
    #
    # @param run_context [Hash] context passed to all robots (message:, user_id:, etc.)
    # @return [SimpleFlow::Result] final pipeline result
    #
    # @example
    #   result = network.run(message: "I need help with billing", user_id: 123)
    #   result.value  # => RobotResult from last robot
    #   result.context[:classifier]  # => RobotResult from classifier
    #
    def run(**run_context)
      # Include shared memory in run params so robots can access it
      run_context[:network_memory] = @memory

      initial_result = SimpleFlow::Result.new(
        run_context,
        context: { run_params: run_context }
      )

      @pipeline.call_parallel(initial_result)
    end

    # Broadcast a message to all robots in the network.
    #
    # This sends a network-wide message that all robots subscribed via
    # `on_broadcast` will receive asynchronously.
    #
    # @param payload [Hash] the message payload
    # @return [self]
    #
    # @example Pause all robots
    #   network.broadcast(event: :pause, reason: "rate limit hit")
    #
    # @example Signal completion
    #   network.broadcast(event: :phase_complete, phase: "analysis")
    #
    def broadcast(payload)
      message = {
        payload: payload,
        network: @name,
        timestamp: Time.now
      }

      # Notify handlers asynchronously
      @broadcast_handlers.each do |handler|
        dispatch_async { handler.call(message) }
      end

      # Also set in memory so robots can subscribe via memory.subscribe
      @memory.set(BROADCAST_KEY, message)

      self
    end

    # Register a handler for broadcast messages.
    #
    # The handler is called asynchronously whenever `broadcast` is called.
    #
    # @yield [Hash] the broadcast message with :payload, :network, :timestamp
    # @return [self]
    #
    # @example
    #   network.on_broadcast do |message|
    #     case message[:payload][:event]
    #     when :pause
    #       pause_current_work
    #     when :resume
    #       resume_work
    #     end
    #   end
    #
    def on_broadcast(&block)
      raise ArgumentError, "Block required for on_broadcast" unless block_given?

      @broadcast_handlers << block
      self
    end

    # Reset the shared memory.
    #
    # Clears all values in the network's shared memory. This is useful
    # between runs if you want to start with a fresh memory state.
    #
    # @return [self]
    #
    def reset_memory
      @memory.reset
      self
    end

    # Get a robot by name
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

    # Get all robots in the network
    #
    # @return [Array<Robot>]
    #
    def available_robots
      @robots.values
    end

    # Add a robot to the network without adding it as a task
    #
    # Useful for dynamically adding robots that will be referenced later.
    #
    # @param robot [Robot] the robot instance to add
    # @return [self]
    # @raise [ArgumentError] if a robot with the same name already exists
    #
    def add_robot(robot)
      if @robots.key?(robot.name)
        raise ArgumentError, "Robot '#{robot.name}' already exists in network '#{@name}'"
      end

      @robots[robot.name] = robot
      self
    end

    # Visualize the pipeline as ASCII
    #
    # @return [String, nil]
    #
    def visualize
      @pipeline.visualize_ascii
    end

    # Export pipeline to Mermaid format
    #
    # @return [String, nil]
    #
    def to_mermaid
      @pipeline.visualize_mermaid
    end

    # Export pipeline to DOT format (Graphviz)
    #
    # @return [String, nil]
    #
    def to_dot
      @pipeline.visualize_dot
    end

    # Get the execution plan
    #
    # @return [String, nil]
    #
    def execution_plan
      @pipeline.execution_plan
    end

    # Converts the network to a hash representation
    #
    # @return [Hash]
    #
    def to_h
      {
        name: name,
        robots: @robots.keys,
        tasks: @tasks.keys,
        optional_tasks: @pipeline.optional_steps.to_a
      }.compact
    end

    private

    def dispatch_async(&block)
      # Use Async if available (preferred for fiber-based concurrency)
      if defined?(Async) && Async::Task.current?
        Async { block.call }
      else
        # Fall back to Thread for basic async dispatch
        Thread.new do
          block.call
        rescue StandardError => e
          warn "Network broadcast handler error: #{e.message}"
        end
      end
    end
  end
end
