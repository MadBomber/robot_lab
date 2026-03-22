# frozen_string_literal: true

module RobotLab
  module MCP
    # Configuration for an MCP server connection
    #
    # @example WebSocket transport
    #   Server.new(
    #     name: "neon",
    #     transport: { type: "ws", url: "ws://localhost:8080" }
    #   )
    #
    # @example StdIO transport
    #   Server.new(
    #     name: "filesystem",
    #     transport: {
    #       type: "stdio",
    #       command: "mcp-server-filesystem",
    #       args: ["--root", "/data"]
    #     }
    #   )
    #
    class Server
      # Valid transport types for MCP connections
      VALID_TRANSPORT_TYPES = %w[stdio sse ws websocket streamable-http http].freeze

      # Default timeout for MCP requests (in seconds)
      DEFAULT_TIMEOUT = 15

      # @!attribute [r] name
      #   @return [String] the server name
      # @!attribute [r] transport
      #   @return [Hash] the transport configuration
      # @!attribute [r] timeout
      #   @return [Numeric] request timeout in seconds
      # @!attribute [r] description
      #   @return [String] human-readable description used by ServerDiscovery
      attr_reader :name, :transport, :timeout, :description

      # Creates a new Server configuration.
      #
      # @param name [String] the server name
      # @param transport [Hash] the transport configuration
      # @param timeout [Numeric, nil] request timeout in seconds (default: 15)
      # @param description [String, nil] human-readable description for server discovery
      # @param _extra [Hash] additional keys are silently ignored for forward compatibility
      # @raise [ArgumentError] if transport type is invalid or required fields are missing
      def initialize(name:, transport:, timeout: nil, description: nil, **_extra)
        @name = name.to_s
        @description = description.to_s
        @transport = normalize_transport(transport)
        @timeout = normalize_timeout(timeout)
        validate!
      end

      # Returns the transport type.
      #
      # @return [String] the transport type (stdio, sse, ws, etc.)
      def transport_type
        @transport[:type]
      end

      # Converts the server configuration to a hash.
      #
      # @return [Hash]
      def to_h
        {
          name: name,
          description: description,
          transport: transport,
          timeout: timeout
        }
      end

      private

      def normalize_transport(transport)
        transport = transport.transform_keys(&:to_sym)
        transport[:type] = transport[:type].to_s.downcase
        transport
      end

      def validate!
        unless VALID_TRANSPORT_TYPES.include?(transport_type)
          raise ArgumentError, "Invalid transport type: #{transport_type}. " \
                               "Must be one of: #{VALID_TRANSPORT_TYPES.join(', ')}"
        end

        case transport_type
        when "stdio"
          raise ArgumentError, "StdIO transport requires :command" unless transport[:command]
        when "ws", "websocket", "sse", "streamable-http", "http"
          raise ArgumentError, "Transport requires :url" unless transport[:url]
        end
      end

      def normalize_timeout(value)
        return DEFAULT_TIMEOUT if value.nil?

        seconds = value.to_f
        # If the caller passed milliseconds (>= 1000), convert to seconds
        seconds = seconds / 1000.0 if seconds >= 1000
        [seconds, 1].max
      end
    end
  end
end
