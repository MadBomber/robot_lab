# frozen_string_literal: true

module RobotLab
  module MCP
    # Multiplexes I/O across multiple stdio MCP transports.
    #
    # When a robot connects to more than one local (stdio) MCP server,
    # the default approach blocks independently per client, each with its
    # own Timeout.timeout wrapper. ConnectionPoller replaces this with a
    # single IO.select call across all registered stdout file descriptors,
    # dispatching each response to the pending request for that client.
    #
    # Async-based transports (SSE, WebSocket, StreamableHTTP) are
    # unaffected — they already use the Async fiber scheduler.
    #
    # == Usage
    #
    #   poller = MCP::ConnectionPoller.new.start
    #   client = MCP::Client.new(server_config, poller: poller)
    #   client.connect     # registers transport with poller
    #   client.call_tool(…)
    #   poller.stop
    #
    # @api private
    class ConnectionPoller
      POLL_INTERVAL = 0.1  # seconds between IO.select checks

      # Creates a new ConnectionPoller.
      def initialize
        @mutex    = Mutex.new
        @clients  = {}    # IO => { client:, queue: Thread::Queue }
        @running  = false
        @thread   = nil
      end

      # Start the multiplexing thread.
      #
      # @return [self]
      def start
        @mutex.synchronize do
          return self if @running

          @running = true
          @thread  = Thread.new { poll_loop }
          @thread.name = "RobotLab::MCP::ConnectionPoller"
        end
        self
      end

      # Stop the multiplexing thread.
      #
      # Cancels all pending requests with an MCPError.
      #
      # @param timeout [Numeric] seconds to wait for thread to finish
      # @return [self]
      def stop(timeout: 5)
        @mutex.synchronize do
          return self unless @running

          @running = false

          # Unblock any pending request queues
          @clients.each_value do |entry|
            entry[:queue]&.push({ error: "ConnectionPoller stopped" })
          end
        end

        @thread&.join(timeout)
        @thread = nil
        self
      end

      # Register an MCP client with the poller.
      #
      # Only stdio clients are registered — others are silently ignored.
      #
      # @param client [MCP::Client]
      # @return [void]
      def register(client)
        return unless stdio_client?(client)

        io = client.transport.stdout
        @mutex.synchronize { @clients[io] = { client: client, queue: nil } }
      end

      # Unregister a client.
      #
      # @param client [MCP::Client]
      # @return [void]
      def unregister(client)
        return unless stdio_client?(client)

        io = client.transport.stdout
        @mutex.synchronize { @clients.delete(io) }
      end

      # Send a JSON-RPC request via the poller and block until the response.
      #
      # Writes to the client's stdin, registers a response queue, then
      # blocks until the poll loop dispatches the response.
      #
      # @param client  [MCP::Client]
      # @param message [Hash] JSON-RPC message
      # @param timeout [Numeric] seconds before raising MCPError
      # @return [Hash] parsed response
      # @raise [MCPError] on timeout or connection error
      def send_request(client, message, timeout:)
        io      = client.transport.stdout
        queue   = Thread::Queue.new

        @mutex.synchronize { @clients[io][:queue] = queue }

        begin
          client.transport.stdin.puts(message.to_json)
          client.transport.stdin.flush
        rescue Errno::EPIPE, IOError => e
          @mutex.synchronize { @clients[io][:queue] = nil }
          raise MCPError.new("MCP connection lost: #{e.message}", retryable: true)
        end

        response = Timeout.timeout(timeout) { queue.pop }

        if response.is_a?(Hash) && response[:error]
          raise MCPError, response[:error]
        end

        response
      rescue Timeout::Error
        @mutex.synchronize { @clients[io]&.[]= :queue, nil }
        raise MCPError.new("MCP server did not respond within #{timeout}s", retryable: true)
      ensure
        @mutex.synchronize { @clients[io]&.[]= :queue, nil }
      end

      # Whether the poller thread is running.
      #
      # @return [Boolean]
      def running?
        @mutex.synchronize { @running }
      end

      private

      def poll_loop
        loop do
          ios = @mutex.synchronize { @clients.keys.reject(&:closed?) }

          if ios.empty?
            sleep POLL_INTERVAL
          else
            begin
              ready, = IO.select(ios, nil, nil, POLL_INTERVAL)
              dispatch(ready) if ready
            rescue Errno::EBADF
              # A pipe was closed between the reject and IO.select — harmless, loop again
            end
          end

          break unless @mutex.synchronize { @running }
        end
      end

      def dispatch(readable_ios)
        readable_ios.each do |io|
          line = io.gets rescue nil
          next unless line

          parsed = JSON.parse(line, symbolize_names: true) rescue nil
          next unless parsed

          # Skip notifications (method present, no id)
          next if parsed[:method] && !parsed.key?(:id)

          entry = @mutex.synchronize { @clients[io] }
          entry[:queue]&.push(parsed)
        end
      end

      def stdio_client?(client)
        client.respond_to?(:transport) &&
          client.transport.is_a?(Transports::Stdio) &&
          client.transport.respond_to?(:stdout) &&
          !client.transport.stdout.nil?
      end
    end
  end
end
