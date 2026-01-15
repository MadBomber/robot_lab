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
        # Creates a new WebSocket transport.
        #
        # @param config [Hash] transport configuration
        # @option config [String] :url WebSocket server URL
        def initialize(config)
          super
          @connection = nil
          @connected = false
          @pending_requests = {}
        end

        # Connect to the MCP server via WebSocket.
        #
        # @return [self]
        # @raise [MCPError] if async-websocket gem is not available
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

        # Send a JSON-RPC request to the MCP server.
        #
        # @param message [Hash] JSON-RPC message
        # @return [Hash] the response
        # @raise [MCPError] if not connected
        def send_request(message)
          raise MCPError, "Not connected" unless @connected

          Async do
            @connection.write(message.to_json)
            @connection.flush

            response_text = @connection.read
            JSON.parse(response_text, symbolize_names: true)
          end.wait
        end

        # Close the WebSocket connection.
        #
        # @return [self]
        def close
          return self unless @connected

          @connection&.close
          @connected = false
          @connection = nil

          self
        end

        # Check if the transport is connected.
        #
        # @return [Boolean] true if connected
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
