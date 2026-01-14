# frozen_string_literal: true

require "open3"
require "json"

module RobotLab
  module MCP
    module Transports
      # StdIO transport for local MCP servers
      #
      # Spawns a subprocess and communicates via stdin/stdout.
      #
      # @example
      #   transport = Stdio.new(
      #     command: "mcp-server-filesystem",
      #     args: ["--root", "/data"],
      #     env: { "DEBUG" => "true" }
      #   )
      #
      class Stdio < Base
        def initialize(config)
          super
          @stdin = nil
          @stdout = nil
          @stderr = nil
          @wait_thread = nil
          @connected = false
        end

        def connect
          return self if @connected

          command = @config[:command]
          args = @config[:args] || []
          env = @config[:env] || {}

          # Merge with current environment
          full_env = ENV.to_h.merge(env.transform_keys(&:to_s))

          @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(full_env, command, *args)
          @connected = true

          # Initialize MCP protocol
          send_initialize

          self
        end

        def send_request(message)
          raise MCPError, "Not connected" unless @connected

          # Write JSON-RPC message
          json = message.to_json
          @stdin.puts(json)
          @stdin.flush

          # Read response, skipping notifications
          loop do
            response_line = @stdout.gets
            raise MCPError, "No response from MCP server" unless response_line

            parsed = JSON.parse(response_line, symbolize_names: true)

            # Skip notifications (messages without an id)
            next if parsed[:method] && !parsed.key?(:id)

            # Return responses (messages with an id)
            return parsed
          end
        end

        def close
          return self unless @connected

          @stdin&.close
          @stdout&.close
          @stderr&.close
          @wait_thread&.kill if @wait_thread&.alive?

          @connected = false
          self
        end

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
      end
    end
  end
end
