# frozen_string_literal: true

module RobotLab
  module MCP
    module Transports
      # Server-Sent Events transport for MCP servers
      #
      # Uses async-http for SSE streaming.
      #
      # @example
      #   transport = SSE.new(url: "http://localhost:8080/sse")
      #
      class SSE < Base
        # Creates a new SSE transport.
        #
        # @param config [Hash] transport configuration
        # @option config [String] :url SSE server URL
        def initialize(config)
          super
          @client = nil
          @connected = false
          @event_queue = []
        end

        # Connect to the MCP server via SSE.
        #
        # @return [self]
        # @raise [MCPError] if async-http gem is not available
        def connect
          return self if @connected

          require "async"
          require "async/http/client"
          require "async/http/endpoint"

          url = @config[:url]

          Async do
            endpoint = Async::HTTP::Endpoint.parse(url)
            @client = Async::HTTP::Client.new(endpoint)
            @connected = true

            # Initialize MCP protocol
            send_initialize
          end

          self
        rescue LoadError => e
          raise MCPError, "async-http gem required for SSE transport: #{e.message}"
        end

        # Send a JSON-RPC request to the MCP server.
        #
        # @param message [Hash] JSON-RPC message
        # @return [Hash] the response
        # @raise [MCPError] if not connected
        def send_request(message)
          raise MCPError, "Not connected" unless @connected

          require "async"
          require "async/http/body/writable"

          Async do
            # POST the request
            response = @client.post(
              @config[:url],
              { "Content-Type" => "application/json" },
              [message.to_json]
            )

            # Read response
            body = response.read
            JSON.parse(body, symbolize_names: true)
          end.wait
        end

        # Close the SSE connection.
        #
        # @return [self]
        def close
          return self unless @connected

          @client&.close
          @connected = false
          @client = nil

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
