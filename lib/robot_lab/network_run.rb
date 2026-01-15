# frozen_string_literal: true

require "simple_flow"

module RobotLab
  # Stateful execution of a network
  #
  # NetworkRun represents a single execution of a Network with its own
  # isolated memory. It manages the robot execution loop, routing decisions,
  # and memory updates.
  #
  # Uses SimpleFlow for potential parallel robot execution.
  #
  class NetworkRun
    # Execution states
    # @return [Array<Symbol>] valid execution state values
    EXECUTION_STATES = %i[pending initializing routing executing_robot robot_complete completed failed].freeze

    # @!attribute [r] network
    #   @return [Network] the network being executed
    # @!attribute [r] memory
    #   @return [Memory] the execution memory
    # @!attribute [r] run_id
    #   @return [String] unique identifier for this run
    # @!attribute [r] execution_state
    #   @return [Symbol] current execution state
    attr_reader :network, :memory, :run_id, :execution_state

    # Creates a new NetworkRun instance.
    #
    # @param network [Network] the network to execute
    # @param memory [Memory] the initial memory
    def initialize(network, memory)
      @network = network
      @memory = memory
      @run_id = SecureRandom.uuid
      @stack = []
      @counter = 0
      @run_context = {}
      @streaming_context = nil
      @initial_result_count = 0
      @execution_state = :pending
    end

    # Delegate robot access to network.
    #
    # @return [Hash<String, Robot>] the network's robots
    def robots
      @network.robots
    end

    # Delegate default_model to network.
    #
    # @return [String] the network's default model
    def default_model
      @network.default_model
    end

    # Execute the network with context
    #
    # @param router [Proc, nil]
    # @param streaming [Proc, nil]
    # @param run_context [Hash] Context passed to all robots
    # @return [self]
    #
    def execute(router:, streaming: nil, **run_context)
      @run_context = run_context
      @streaming_context = create_streaming_context(streaming) if streaming

      @execution_state = :initializing

      begin
        # Initialize thread and load history
        initialize_thread
        @initial_result_count = @memory.results.size

        # Publish run started event
        @streaming_context&.publish_event(
          event: "run.started",
          data: { run_id: @run_id, network: @network.name }
        )

        @execution_state = :routing

        # Get initial robots from router
        router_args = build_router_args(nil)
        next_robots = Router.call(router, router_args)

        unless next_robots&.any?
          # No robots to run
          @execution_state = :completed
          save_to_history
          return self
        end

        # Schedule initial robots
        schedule_robots(next_robots)

        # Main execution loop
        while @stack.any? && @counter < @network.max_iter
          robot_name = @stack.shift
          robot = robots[robot_name]

          unless robot
            RobotLab.configuration.logger.warn("Robot not found: #{robot_name}")
            next
          end

          @execution_state = :executing_robot

          # Create robot-specific streaming context
          _robot_streaming = @streaming_context&.create_child_context(@run_id)

          # Run the robot with context
          result = robot.run(
            network: self,
            **@run_context
          )

          # Store result
          @memory.append_result(result)
          @counter += 1

          @execution_state = :robot_complete

          # Get next robots from router
          router_args = build_router_args(result)
          next_robots = Router.call(router, router_args)

          schedule_robots(next_robots) if next_robots&.any?
        end

        @execution_state = :completed
        save_to_history

        # Publish run completed event
        @streaming_context&.publish_event(
          event: "run.completed",
          data: { run_id: @run_id, robot_count: @counter }
        )

        self
      rescue StandardError => e
        @execution_state = :failed

        @streaming_context&.publish_event(
          event: "run.failed",
          data: { run_id: @run_id, error: Errors.serialize(e) }
        )

        raise
      end
    end

    # Get all results from this run
    #
    # @return [Array<RobotResult>]
    #
    def results
      @memory.results
    end

    # Get new results (since initial load)
    #
    # @return [Array<RobotResult>]
    #
    def new_results
      @memory.results_from(@initial_result_count)
    end

    # Get the last result
    #
    # @return [RobotResult, nil]
    #
    def last_result
      @memory.results.last
    end

    # Build execution pipeline using SimpleFlow
    #
    # @return [SimpleFlow::Pipeline]
    #
    def build_pipeline(robots)
      SimpleFlow::Pipeline.new do
        robots.each do |robot|
          step robot.name.to_sym, ->(result) {
            # Execute robot and return result
            robot_result = robot.run(
              network: result.context[:network],
              **result.context[:run_context]
            )
            result.with_context(:last_result, robot_result).continue(robot_result)
          }
        end
      end
    end

    # Converts the run to a hash representation.
    #
    # @return [Hash] hash with run_id, network, state, counter, stack, results
    def to_h
      {
        run_id: run_id,
        network: network.name,
        state: execution_state,
        counter: @counter,
        stack: @stack,
        results: results.map(&:export)
      }
    end

    private

    def schedule_robots(robots)
      return unless robots

      robots.each do |robot|
        robot_name = robot.respond_to?(:name) ? robot.name : robot.to_s
        @stack.push(robot_name) unless @stack.include?(robot_name)
      end
    end

    def build_router_args(last_result)
      Router::Args.new(
        context: @run_context,
        network: self,
        stack: @stack.map { |n| robots[n] }.compact,
        call_count: @counter,
        last_result: last_result
      )
    end

    def create_streaming_context(streaming_callback)
      Streaming::Context.new(
        run_id: @run_id,
        message_id: SecureRandom.uuid,
        scope: "network",
        publish: streaming_callback
      )
    end

    def initialize_thread
      return unless @network.history

      # Create thread if needed
      if @network.history.create_thread && !@memory.thread_id
        result = @network.history.create_thread.call(
          state: @memory,
          context: @run_context,
          network: self
        )
        @memory.thread_id = result[:thread_id] if result
      end

      # Load existing history
      load_from_history if @memory.thread_id && @network.history.get
    end

    def load_from_history
      return unless @network.history&.get

      existing_results = @network.history.get.call(
        thread_id: @memory.thread_id,
        state: @memory,
        network: self,
        context: @run_context
      )

      @memory.set_results(existing_results) if existing_results&.any?
    end

    def save_to_history
      return unless @network.history&.append_results

      new_results = @memory.results_from(@initial_result_count)
      return if new_results.empty?

      @network.history.append_results.call(
        thread_id: @memory.thread_id,
        state: @memory,
        network: self,
        context: @run_context,
        new_results: new_results
      )
    end
  end
end
