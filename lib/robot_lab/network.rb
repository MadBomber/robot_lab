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
    include Utils

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
    attr_reader :name, :pipeline, :robots, :memory, :config, :parallel_mode, :hooks

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
    def initialize(name:, concurrency: :auto, memory: nil, config: nil, parallel_mode: :async, &)
      @name = name.to_s
      @robots = {}
      @tasks = {}
      @pipeline = SimpleFlow::Pipeline.new(concurrency: concurrency)
      @memory = memory || Memory.new(network_name: @name)
      @config = config || RunConfig.new
      @parallel_mode = parallel_mode
      @hooks = HookRegistry.new
      @broadcast_handlers = []
      @bus_poller = BusPoller.new.start

      instance_eval(&) if block_given?
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
    def task(name, robot, context: {}, mcp: :none, tools: :none, memory: nil, config: nil, depends_on: :none,
             poller_group: :default)
      task_wrapper = Task.new(
        name: name,
        robot: robot,
        context: context,
        mcp: mcp,
        tools: tools,
        memory: memory,
        config: config,
        network: self
      )

      # Register the group and assign the shared poller to the robot
      @bus_poller.add_group(poller_group)
      robot.assign_bus_poller(@bus_poller, group: poller_group) if robot.respond_to?(:assign_bus_poller, true)

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
    def parallel(name = nil, depends_on: :none, &)
      @pipeline.parallel(name, depends_on: depends_on, &)
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
      run_context[:network] = self

      # Pass network's config so robots can inherit it
      run_context[:network_config] = @config unless @config.empty?

      context = NetworkRunHookContext.new(
        network: self,
        context: run_context,
        memory: @memory,
        config: @config
      )

      RobotLab::Hooks.run(:network_run, context, registries: [RobotLab.hooks, @hooks]) do
        if @parallel_mode == :ractor
          run_with_ractor_scheduler(context.context)
        else
          initial_result = SimpleFlow::Result.new(
            context.context,
            context: { run_params: context.context }
          )
          @pipeline.call_parallel(initial_result, max_concurrent: @config.max_concurrent_robots)
        end
      end
    end

    def on(hook_name, namespace: nil, context: nil, &callback)
      @hooks.on(hook_name, namespace: namespace, context: context, &callback)
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
        optional_tasks: @pipeline.optional_steps.to_a,
        config: (@config.empty? ? nil : @config.to_json_hash)
      }.compact
    end

    private

    def run_with_ractor_scheduler(run_context)
      unless RobotLab.extension_loaded?(:ractor)
        raise RobotLab::DependencyError,
              "parallel_mode: :ractor requires the robot_lab-ractor gem. " \
              "Add `gem 'robot_lab-ractor'` to your Gemfile."
      end
      message   = run_context[:message].to_s
      dep_graph = @pipeline.step_dependencies  # { task_sym => [dep_sym, ...] }

      specs_with_deps = @tasks.map do |task_name, task_wrapper|
        deps = dep_graph[task_name.to_sym] || []
        deps = deps.empty? ? :none : deps.map(&:to_s)

        spec = RobotSpec.new(
          name:          task_wrapper.robot.name.freeze,
          template:      task_wrapper.robot.template&.to_s&.freeze,
          system_prompt: task_wrapper.robot.system_prompt&.freeze,
          config_hash:   RactorBoundary.freeze_deep(task_wrapper.robot.config.to_json_hash)
        )

        { spec: spec, depends_on: deps }
      end

      scheduler = RactorNetworkScheduler.new(memory: @memory)
      results   = scheduler.run_pipeline(specs_with_deps, message: message)
      scheduler.shutdown
      results
    end
  end
end
