# frozen_string_literal: true

module RobotLab
  module MCP
    # MCP client for communicating with Model Context Protocol servers
    #
    # Uses actionmcp gem for MCP protocol implementation.
    # Supports multiple transport types: StdIO, SSE, WebSocket, HTTP.
    #
    # @example
    #   client = Client.new(name: "neon", transport: { type: "ws", url: "ws://..." })
    #   client.connect
    #   tools = client.list_tools
    #   result = client.call_tool("createBranch", { project_id: "abc" })
    #
    class Client
      # @!attribute [r] server
      #   @return [Server] the MCP server configuration
      # @!attribute [r] connected
      #   @return [Boolean] whether currently connected
      attr_reader :server, :connected

      # Creates a new MCP Client instance.
      #
      # @param server_or_config [Server, Hash] the server or configuration hash
      # @raise [ArgumentError] if config is invalid
      def initialize(server_or_config)
        @server = case server_or_config
                  when Server
                    server_or_config
                  when Hash
                    Server.new(**server_or_config.transform_keys(&:to_sym))
                  else
                    raise ArgumentError, "Invalid server config"
                  end
        @connected = false
        @transport = nil
        @request_id = 0
      end

      # Connect to the MCP server
      #
      # @return [self]
      #
      def connect
        return self if @connected

        @transport = create_transport
        @transport.connect if @transport.respond_to?(:connect)
        @connected = true

        self
      rescue StandardError => e
        RobotLab.configuration.logger.warn("MCP connection failed for #{@server.name}: #{e.message}")
        @connected = false
        self
      end

      # Disconnect from the server
      #
      # @return [self]
      #
      def disconnect
        return self unless @connected

        @transport.close if @transport.respond_to?(:close)
        @connected = false
        @transport = nil

        self
      end

      # List available tools from the server
      #
      # @return [Array<Hash>] Tool definitions
      #
      def list_tools
        ensure_connected!
        response = request(method: "tools/list")
        response[:tools] || []
      end

      # Call a tool on the server
      #
      # @param name [String] Tool name
      # @param arguments [Hash] Tool arguments
      # @return [Object] Tool result
      #
      def call_tool(name, arguments = {})
        ensure_connected!
        response = request(
          method: "tools/call",
          params: { name: name, arguments: arguments }
        )
        response[:content] || response
      end

      # List available resources
      #
      # @return [Array<Hash>]
      #
      def list_resources
        ensure_connected!
        response = request(method: "resources/list")
        response[:resources] || []
      end

      # Read a resource
      #
      # @param uri [String] Resource URI
      # @return [Object]
      #
      def read_resource(uri)
        ensure_connected!
        response = request(method: "resources/read", params: { uri: uri })
        response[:contents] || response
      end

      # List available prompts
      #
      # @return [Array<Hash>]
      #
      def list_prompts
        ensure_connected!
        response = request(method: "prompts/list")
        response[:prompts] || []
      end

      # Get a prompt
      #
      # @param name [String] Prompt name
      # @param arguments [Hash] Prompt arguments
      # @return [Hash]
      #
      def get_prompt(name, arguments = {})
        ensure_connected!
        response = request(method: "prompts/get", params: { name: name, arguments: arguments })
        response
      end

      # Checks if the client is connected to the server.
      #
      # @return [Boolean]
      def connected?
        @connected
      end

      # Converts the client to a hash representation.
      #
      # @return [Hash]
      def to_h
        {
          server: @server.to_h,
          connected: @connected
        }
      end

      private

      def ensure_connected!
        raise MCPError, "Not connected to MCP server: #{@server.name}" unless @connected
      end

      def create_transport
        case @server.transport_type
        when "stdio"
          Transports::Stdio.new(@server.transport)
        when "ws", "websocket"
          Transports::WebSocket.new(@server.transport)
        when "sse"
          Transports::SSE.new(@server.transport)
        when "streamable-http", "http"
          Transports::StreamableHTTP.new(@server.transport)
        else
          raise MCPError, "Unsupported transport type: #{@server.transport_type}"
        end
      end

      def request(method:, params: nil)
        @request_id += 1

        message = {
          jsonrpc: "2.0",
          id: @request_id,
          method: method
        }
        message[:params] = params if params

        response = @transport.send_request(message)
        parse_response(response)
      end

      def parse_response(response)
        return response[:result] if response.is_a?(Hash) && response[:result]

        case response
        when String
          parsed = JSON.parse(response, symbolize_names: true)
          parsed[:result] || parsed
        when Hash
          response[:result] || response
        else
          response
        end
      rescue JSON::ParserError
        { raw: response }
      end
    end
  end
end
