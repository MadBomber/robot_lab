# frozen_string_literal: true

require "open3"
require "json"
require "timeout"

module RobotLab
  module MCP
    module Transports
      # StdIO transport for local MCP servers
      #
      # Spawns a subprocess and communicates via stdin/stdout.
      # All blocking I/O is wrapped with a configurable timeout
      # so a missing or hung server cannot block the caller forever.
      #
      # @example
      #   transport = Stdio.new(
      #     { command: "mcp-server-filesystem", args: ["--root", "/data"] },
      #     timeout: 10
      #   )
      #
      class Stdio < Base
        # Creates a new Stdio transport.
        #
        # @param config [Hash] transport configuration
        # @option config [String] :command the command to execute
        # @option config [Array<String>] :args command arguments
        # @option config [Hash] :env environment variables
        # @option config [Numeric] :timeout request timeout in seconds (default: 15)
        def initialize(config)
          super
          @stdin = nil
          @stdout = nil
          @stderr = nil
          @wait_thread = nil
          @connected = false
        end

        # Connect to the MCP server via stdio.
        #
        # @return [self]
        # @raise [MCPError] if the server process cannot be started or does not
        #   respond to the MCP initialize handshake within the timeout period
        def connect
          return self if @connected

          command = @config[:command]
          args = @config[:args] || []
          env = @config[:env] || {}

          full_env = ENV.to_h.merge(env.transform_keys(&:to_s))

          @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(full_env, command, *args)

          # Verify the process actually started
          unless @wait_thread.alive?
            raise MCPError, "MCP server process exited immediately (command: #{command})"
          end

          @connected = true

          # Initialize MCP protocol — this must complete within the timeout
          send_initialize

          self
        rescue Errno::ENOENT => e
          cleanup_process
          raise MCPError, "MCP server command not found: #{command} (#{e.message})"
        rescue Timeout::Error
          cleanup_process
          raise MCPError, "MCP server '#{command}' did not respond within #{@timeout}s"
        end

        # Send a JSON-RPC request to the MCP server.
        #
        # @param message [Hash] JSON-RPC message
        # @return [Hash] the response
        # @raise [MCPError] if not connected, no response, or timeout
        def send_request(message)
          raise MCPError, "Not connected" unless @connected

          Timeout.timeout(@timeout, Timeout::Error) do
            json = message.to_json
            @stdin.puts(json)
            @stdin.flush

            loop do
              response_line = @stdout.gets
              raise MCPError, "No response from MCP server (EOF on stdout)" unless response_line

              parsed = JSON.parse(response_line, symbolize_names: true)

              # Skip notifications (messages without an id)
              next if parsed[:method] && !parsed.key?(:id)

              return parsed
            end
          end
        rescue Timeout::Error
          raise MCPError, "MCP server did not respond within #{@timeout}s"
        rescue Errno::EPIPE, IOError => e
          @connected = false
          raise MCPError, "MCP server connection lost: #{e.message}"
        end

        # Close the connection to the MCP server.
        #
        # @return [self]
        def close
          return self unless @connected

          cleanup_process
          self
        end

        # Check if the transport is connected.
        #
        # @return [Boolean] true if connected and process is alive
        def connected?
          @connected && @wait_thread&.alive?
        end

        private

        def send_initialize
          send_request(
            jsonrpc: "2.0",
            id: 0,
            method: "initialize",
            params: {
              protocolVersion: "2024-11-05",
              capabilities: {},
              clientInfo: {
                name: "RobotLab",
                version: RobotLab::VERSION
              }
            }
          )

          # Send initialized notification
          @stdin.puts({ jsonrpc: "2.0", method: "notifications/initialized" }.to_json)
          @stdin.flush
        end

        def cleanup_process
          @connected = false
          @stdin&.close  rescue nil
          @stdout&.close rescue nil
          @stderr&.close rescue nil
          @wait_thread&.kill if @wait_thread&.alive?
          @stdin = nil
          @stdout = nil
          @stderr = nil
          @wait_thread = nil
        end
      end
    end
  end
end
