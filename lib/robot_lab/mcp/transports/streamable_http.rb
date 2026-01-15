# frozen_string_literal: true

module RobotLab
  module MCP
    module Transports
      # Streamable HTTP transport for MCP servers
      #
      # Supports session management and reconnection.
      #
      # @example
      #   transport = StreamableHTTP.new(
      #     url: "https://server.smithery.ai/neon/mcp",
      #     session_id: "abc123"
      #   )
      #
      class StreamableHTTP < Base
        # Creates a new StreamableHTTP transport.
        #
        # @param config [Hash] transport configuration
        # @option config [String] :url HTTP server URL
        # @option config [String] :session_id optional session identifier
        # @option config [Proc] :auth_provider optional authentication callback
        def initialize(config)
          super
          @client = nil
          @connected = false
          @session_id = config[:session_id]
        end

        # Connect to the MCP server via HTTP.
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
            result = send_initialize
            @session_id ||= result.dig(:serverInfo, :sessionId)
          end

          self
        rescue LoadError => e
          raise MCPError, "async-http gem required for HTTP transport: #{e.message}"
        end

        # Send a JSON-RPC request to the MCP server.
        #
        # @param message [Hash] JSON-RPC message
        # @return [Hash] the response
        # @raise [MCPError] if not connected
        def send_request(message)
          raise MCPError, "Not connected" unless @connected

          require "async"

          Async do
            headers = {
              "Content-Type" => "application/json",
              "Accept" => "application/json"
            }
            headers["X-Session-ID"] = @session_id if @session_id

            # Add auth if configured
            if @config[:auth_provider]
              auth_header = @config[:auth_provider].call
              headers["Authorization"] = auth_header if auth_header
            end

            response = @client.post(
              @config[:url],
              headers,
              [message.to_json]
            )

            body = response.read
            JSON.parse(body, symbolize_names: true)
          end.wait
        end

        # Close the HTTP connection.
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

        # Returns the session identifier.
        #
        # @return [String, nil] the session ID
        def session_id
          @session_id
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
