# frozen_string_literal: true

require "simple_flow"

module RobotLab
  # Orchestrates multiple robots in a pipeline workflow
  #
  # Network is a thin wrapper around SimpleFlow::Pipeline that provides
  # a clean DSL for defining robot workflows with sequential, parallel,
  # and conditional execution.
  #
  # @example Sequential execution
  #   network = RobotLab.create_network(name: "pipeline") do
  #     step :analyst, analyst_robot, depends_on: :none
  #     step :writer, writer_robot, depends_on: [:analyst]
  #   end
  #
  # @example With optional steps (conditional routing)
  #   network = RobotLab.create_network(name: "support") do
  #     step :classifier, classifier_robot, depends_on: :none
  #     step :billing, billing_robot, depends_on: :optional
  #     step :technical, technical_robot, depends_on: :optional
  #   end
  #
  # @example Parallel execution
  #   network = RobotLab.create_network(name: "analysis") do
  #     step :fetch, fetcher_robot, depends_on: :none
  #     step :sentiment, sentiment_robot, depends_on: [:fetch]
  #     step :entities, entity_robot, depends_on: [:fetch]
  #     step :summarize, summary_robot, depends_on: [:sentiment, :entities]
  #   end
  #
  class Network
    # @!attribute [r] name
    #   @return [String] unique identifier for the network
    # @!attribute [r] pipeline
    #   @return [SimpleFlow::Pipeline] the underlying pipeline
    # @!attribute [r] robots
    #   @return [Hash<String, Robot>] robots in this network, keyed by name
    attr_reader :name, :pipeline, :robots

    # Creates a new Network instance.
    #
    # @param name [String] unique identifier for the network
    # @param concurrency [Symbol] concurrency model (:auto, :threads, :async)
    # @yield Block for defining pipeline steps
    #
    # @example
    #   network = Network.new(name: "support") do
    #     step :classifier, classifier, depends_on: :none
    #     step :billing, billing_robot, depends_on: :optional
    #   end
    #
    def initialize(name:, concurrency: :auto, &block)
      @name = name.to_s
      @robots = {}
      @pipeline = SimpleFlow::Pipeline.new(concurrency: concurrency)

      instance_eval(&block) if block_given?
    end

    # Add a robot as a pipeline step
    #
    # @param name [Symbol] step name
    # @param robot [Robot] the robot instance
    # @param depends_on [Symbol, Array<Symbol>] dependencies (:none, :optional, or step names)
    # @return [self]
    #
    # @example Entry point step
    #   step :classifier, classifier_robot, depends_on: :none
    #
    # @example Step with dependencies
    #   step :writer, writer_robot, depends_on: [:analyst]
    #
    # @example Optional step (activated at runtime)
    #   step :billing, billing_robot, depends_on: :optional
    #
    def step(name, robot, depends_on: :none)
      @robots[name.to_s] = robot
      @pipeline.step(name, robot, depends_on: depends_on)
      self
    end

    # Define a parallel execution block
    #
    # @param name [Symbol, nil] optional name for the parallel group
    # @param depends_on [Symbol, Array] dependencies for this group
    # @yield Block containing step definitions
    # @return [self]
    #
    # @example Named parallel group
    #   parallel :fetch_data, depends_on: :validate do
    #     step :fetch_orders, orders_robot
    #     step :fetch_products, products_robot
    #   end
    #   step :process, processor, depends_on: :fetch_data
    #
    def parallel(name = nil, depends_on: :none, &block)
      @pipeline.parallel(name, depends_on: depends_on, &block)
      self
    end

    # Run the network with the given context
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
      initial_result = SimpleFlow::Result.new(
        run_context,
        context: { run_params: run_context }
      )

      @pipeline.call_parallel(initial_result)
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

    # Add a robot to the network without adding it as a step
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
        steps: @pipeline.steps.map { |s| s[:name] }.compact,
        optional_steps: @pipeline.optional_steps.to_a
      }.compact
    end
  end
end
