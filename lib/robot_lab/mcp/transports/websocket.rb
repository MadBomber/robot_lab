# frozen_string_literal: true

module RobotLab
  module MCP
    module Transports
      # WebSocket transport for MCP servers
      #
      # Uses async-websocket for non-blocking communication.
      #
      # @example
      #   transport = WebSocket.new(url: "ws://localhost:8080")
      #
      class WebSocket < Base
        def initialize(config)
          super
          @connection = nil
          @connected = false
          @pending_requests = {}
        end

        def connect
          return self if @connected

          require "async"
          require "async/websocket/client"

          url = @config[:url]

          Async do
            endpoint = Async::HTTP::Endpoint.parse(url)
            @connection = Async::WebSocket::Client.connect(endpoint)
            @connected = true

            # Initialize MCP protocol
            send_initialize
          end

          self
        rescue LoadError => e
          raise MCPError, "async-websocket gem required for WebSocket transport: #{e.message}"
        end

        def send_request(message)
          raise MCPError, "Not connected" unless @connected

          Async do
            @connection.write(message.to_json)
            @connection.flush

            response_text = @connection.read
            JSON.parse(response_text, symbolize_names: true)
          end.wait
        end

        def close
          return self unless @connected

          @connection&.close
          @connected = false
          @connection = nil

          self
        end

        def connected?
          @connected
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
        end
      end
    end
  end
end
