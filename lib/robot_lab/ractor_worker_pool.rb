# frozen_string_literal: true

require "etc"
require "ractor_queue"

module RobotLab
  # A pool of Ractor workers that execute CPU-bound, Ractor-safe tools.
  #
  # Work is distributed via a shared RactorQueue. Each worker runs a
  # blocking loop, pops RactorJob instances, dispatches to the named
  # tool class, and pushes the frozen result (or a RactorJobError) to
  # the job's per-job reply_queue.
  #
  # Shutdown uses a poison-pill pattern: one nil sentinel per worker is
  # pushed to the work queue; each worker exits when it pops nil.
  #
  # Only tools that declare +ractor_safe true+ should be submitted.
  # Tool classes are instantiated fresh inside the Ractor for each call.
  #
  # @example
  #   pool = RactorWorkerPool.new(size: 4)
  #   result = pool.submit("MyTool", { "arg" => "value" })
  #   pool.shutdown
  #
  class RactorWorkerPool
    # Capacity of the shared work queue.
    QUEUE_CAPACITY = 1024

    # @return [Integer] number of worker Ractors
    attr_reader :size

    # Creates a new pool and starts worker Ractors immediately.
    #
    # @param size [Integer, :auto] number of workers (:auto = Etc.nprocessors)
    def initialize(size: :auto)
      @size    = size == :auto ? Etc.nprocessors : size.to_i
      @closed  = false
      @work_q  = RactorQueue.new(capacity: QUEUE_CAPACITY)
      @workers = @size.times.map { spawn_worker(@work_q) }
    end

    # Submit a tool job and block until the result is available.
    #
    # @param tool_class_name [String] fully-qualified Ruby constant name of the tool class
    # @param args [Hash] tool arguments (deep-frozen before crossing Ractor boundary)
    # @return [Object] the tool's return value
    # @raise [RactorBoundaryError] if args cannot be made Ractor-shareable
    # @raise [ToolError] if the tool raises inside the Ractor
    def submit(tool_class_name, args)
      raise ToolError, "Pool is shut down" if @closed

      reply_q = RactorQueue.new(capacity: 1)
      payload = RactorBoundary.freeze_deep({
        tool_class: tool_class_name.to_s,
        args: args
      })

      job = RactorJob.new(
        id:          SecureRandom.uuid.freeze,
        type:        :tool,
        payload:     payload,
        reply_queue: reply_q
      )

      @work_q.push(job)
      result = reply_q.pop

      if result.is_a?(RactorJobError)
        raise ToolError, "Tool '#{tool_class_name}' failed in Ractor: #{result.message}"
      end

      result
    end

    # Gracefully shut down the pool.
    #
    # Pushes one nil poison pill per worker so each exits its loop.
    # Waits for all workers to terminate.
    #
    # @return [void]
    def shutdown
      return if @closed

      @closed = true
      # Push one nil poison pill per worker
      @size.times { @work_q.push(nil) }
      @workers.each { |w| w.join rescue nil }
    end

    private

    def spawn_worker(work_q)
      Ractor.new(work_q) do |q|
        loop do
          job = q.pop

          # nil is the poison pill — exit cleanly
          break if job.nil?

          begin
            tool_class = Object.const_get(job.payload[:tool_class])
            tool       = tool_class.new
            result     = tool.execute(**job.payload[:args].transform_keys(&:to_sym))
            frozen_result = Ractor.make_shareable(result.frozen? ? result : result.dup.freeze)
            job.reply_queue.push(frozen_result)
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
