# frozen_string_literal: true

require "etc"
require "ractor_queue"

module RobotLab
  # Schedules frozen robot task descriptions across Ractor workers.
  #
  # Robots stay in threads for LLM calls (ruby_llm is not Ractor-safe).
  # The scheduler distributes frozen RobotSpec payloads; each worker
  # constructs a fresh Robot, runs the task, and returns a frozen result.
  #
  # Task ordering respects depends_on: tasks are only dispatched once all
  # named dependencies have resolved (same topological semantics as
  # SimpleFlow::Pipeline).
  #
  # @example
  #   scheduler = RactorNetworkScheduler.new(memory: shared_memory)
  #   scheduler.run_pipeline([
  #     { spec: analyst_spec, depends_on: :none },
  #     { spec: writer_spec,  depends_on: ["analyst"] }
  #   ], message: "Process this")
  #   scheduler.shutdown
  #
  class RactorNetworkScheduler
    # Capacity for the work queue.
    QUEUE_CAPACITY = 256

    # @param memory [Memory] shared network memory for all robot tasks
    # @param pool_size [Integer, :auto] number of Ractor workers
    def initialize(memory:, pool_size: :auto)
      @memory   = memory
      @work_q   = RactorQueue.new(capacity: QUEUE_CAPACITY)
      @size     = pool_size == :auto ? Etc.nprocessors : pool_size.to_i
      @workers  = @size.times.map { spawn_worker(@work_q) }
      @closed   = false
    end

    # Run a single spec and return the result string.
    #
    # @param spec [RobotSpec]
    # @param message [String]
    # @return [String] the robot's last_text_content
    def run_spec(spec, message:)
      execute_spec(spec, message)
    end

    # Run a pipeline of specs in dependency order.
    #
    # @param specs_with_deps [Array<Hash>] each entry has :spec and :depends_on
    #   :depends_on is :none, :optional, or an Array<String> of spec names
    # @param message [String] initial message passed to entry-point robots
    # @return [Hash<String, String>] name => result for each completed robot
    def run_pipeline(specs_with_deps, message:)
      completed = {}  # name => result string
      remaining = specs_with_deps.dup

      until remaining.empty?
        ready, remaining = remaining.partition do |entry|
          deps = entry[:depends_on]
          deps == :none || deps == :optional ||
            Array(deps).all? { |d| completed.key?(d) }
        end

        raise RobotLab::Error, "Circular dependency or unresolvable deps in RactorNetworkScheduler" if ready.empty?

        # Submit all ready tasks concurrently via threads.
        # report_on_exception is disabled because exceptions are propagated
        # to the caller via t.value — the default reporting is redundant noise.
        threads = ready.map do |entry|
          spec = entry[:spec]
          msg  = completed.values.last || message
          Thread.new { [spec.name, execute_spec(spec, msg)] }.tap { |t| t.report_on_exception = false }
        end

        threads.each do |t|
          name, result = t.value
          completed[name] = result
        end
      end

      completed
    end

    # Gracefully shut down worker Ractors.
    # @return [void]
    def shutdown
      return if @closed

      @closed = true
      @size.times { @work_q.push(nil) }
      @workers.each { |w| w.join rescue nil }
    end

    private

    # Dispatch a spec to a Ractor worker and block for the result.
    def execute_spec(spec, message)
      frozen_spec    = Ractor.make_shareable(spec)
      frozen_message = message.to_s.freeze
      reply_q        = RactorQueue.new(capacity: 1)

      job = RactorJob.new(
        id:          SecureRandom.uuid.freeze,
        type:        :robot,
        payload:     RactorBoundary.freeze_deep({
          spec:    frozen_spec,
          message: frozen_message
        }),
        reply_queue: reply_q
      )

      @work_q.push(job)
      result = reply_q.pop

      if result.is_a?(RactorJobError)
        raise RobotLab::Error, "Robot '#{spec.name}' failed in Ractor: #{result.message}"
      end

      result
    end

    def spawn_worker(work_q)
      Ractor.new(work_q) do |q|
        loop do
          job = q.pop
          break if job.nil?

          begin
            spec    = job.payload[:spec]
            message = job.payload[:message]

            robot = RobotLab::Robot.new(
              name:          spec.name,
              template:      spec.template ? spec.template.to_sym : nil,
              system_prompt: spec.system_prompt,
              config:        spec.config_hash.empty? ? nil : RobotLab::RunConfig.new(**spec.config_hash.transform_keys(&:to_sym))
            )

            robot_result  = robot.run(message)
            frozen_reply  = robot_result.last_text_content.to_s.freeze
            job.reply_queue.push(frozen_reply)
          rescue => e
            err = RobotLab::RactorJobError.new(
              message:   e.message.freeze,
              backtrace: (e.backtrace || []).map(&:freeze).freeze
            )
            job.reply_queue.push(err)
          end
        end
      end
    end
  end
end
