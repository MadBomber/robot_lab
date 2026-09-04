# frozen_string_literal: true

require "ractor_queue"

module RobotLab
  # Centralizes bus delivery serialization for robots.
  #
  # Each robot's TypedBus subscription calls enqueue() instead of
  # handling deliveries inline. BusPoller ensures per-robot sequential
  # processing: if a robot is already processing a delivery, new ones
  # are queued and drained after the current one completes.
  #
  # Unlike the old per-robot @bus_processing flag, BusPoller is mutex-
  # protected and shared across robots, giving a single point of control
  # for delivery ordering. Delivery still happens in the caller's
  # execution context (Async fiber or OS thread), so synchronous test
  # semantics are preserved.
  #
  # == Poller Groups
  #
  # Robots can be assigned to named groups via the Network DSL:
  #
  #   task :fast_bot, fast_robot, depends_on: :none
  #   task :slow_bot, slow_robot, depends_on: :none, poller_group: :slow
  #
  # Groups are purely organizational — they share the same mutex-based
  # drain mechanism. In Async contexts, slow robots naturally yield during
  # LLM HTTP calls without blocking fast robots.
  #
  # @api private
  class BusPoller
    # Capacity of per-robot RactorQueue delivery queues.
    QUEUE_CAPACITY = 512

    # Creates a new BusPoller.
    def initialize
      @mutex        = Mutex.new
      @robot_busy   = {}   # robot_name => Boolean
      @robot_queues = {}   # robot_name => RactorQueue<delivery>
      @groups       = [:default]
    end

    # No-op — BusPoller has no background threads to start.
    # Kept for API symmetry with the old design.
    #
    # @return [self]
    def start
      self
    end

    # No-op — no threads to stop.
    #
    # @return [self]
    def stop(*)
      self
    end

    # Enqueue a delivery for a robot.
    #
    # If the robot is not currently processing, the delivery is handled
    # immediately in the caller's context (Async fiber or OS thread).
    # If the robot is busy, the delivery is queued and will be drained
    # after the current delivery completes.
    #
    # @param robot    [Robot]   the robot that will process the delivery
    # @param delivery [Object]  the TypedBus delivery object
    # @param group    [Symbol]  poller group label (informational only)
    # @return [void]
    #
    # :reek:TooManyStatements -- the queue-or-run decision must stay inside one mutex critical section.
    def enqueue(robot:, delivery:, group: :default)
      should_process = @mutex.synchronize do
        name = robot.name
        @robot_queues[name] ||= RactorQueue.new(capacity: QUEUE_CAPACITY)
        @robot_busy[name]   ||= false

        if @robot_busy[name]
          @robot_queues[name].push(delivery)
          false
        else
          @robot_busy[name] = true
          true
        end
      end

      process_and_drain(robot, delivery) if should_process
    end

    # Add a named poller group.
    #
    # Idempotent. Groups are informational labels — they do not create
    # separate queues or threads.
    #
    # @param name [Symbol]
    # @return [void]
    def add_group(name)
      @mutex.synchronize { @groups << name unless @groups.include?(name) }
    end

    # Names of all registered poller groups.
    #
    # @return [Array<Symbol>]
    def groups
      @mutex.synchronize { @groups.dup }
    end

    # Always true — BusPoller needs no background threads.
    #
    # @return [Boolean]
    def running?
      true
    end

    private

    # Process one delivery, then drain any queued deliveries for the robot.
    def process_and_drain(robot, delivery)
      robot.send(:process_delivery, delivery)
      drain_queued_deliveries(robot)
    rescue BusError => e
      release_robot(robot)
      RobotLab.config.logger.warn("BusPoller: delivery error: #{e.message}")
    rescue => e
      release_robot(robot)
      RobotLab.config.logger.warn("BusPoller: unexpected error: #{e.message}")
    end

    # :reek:TooManyStatements -- pop-under-mutex then process-outside-mutex loop; splitting it would separate the lock from its release.
    def drain_queued_deliveries(robot)
      loop do
        next_delivery = @mutex.synchronize do
          name  = robot.name
          queue = @robot_queues[name]

          if queue && !queue.empty?
            entry = queue.try_pop
            entry.equal?(RactorQueue::EMPTY) ? nil : entry
          else
            @robot_busy[name] = false
            nil
          end
        end

        break unless next_delivery

        begin
          robot.send(:process_delivery, next_delivery)
        rescue BusError => e
          RobotLab.config.logger.warn("BusPoller: delivery error: #{e.message}")
        end
      end
    end

    def release_robot(robot)
      @mutex.synchronize { @robot_busy[robot.name] = false }
    end
  end
end
