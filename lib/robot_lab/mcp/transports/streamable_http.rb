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
        def initialize(config)
          super
          @client = nil
          @connected = false
          @session_id = config[:session_id]
        end

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

        def close
          return self unless @connected

          @client&.close
          @connected = false
          @client = nil

          self
        end

        def connected?
          @connected
        end

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
