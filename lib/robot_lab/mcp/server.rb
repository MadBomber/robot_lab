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

      # @!attribute [r] name
      #   @return [String] the server name
      # @!attribute [r] transport
      #   @return [Hash] the transport configuration
      attr_reader :name, :transport

      # Creates a new Server configuration.
      #
      # @param name [String] the server name
      # @param transport [Hash] the transport configuration
      # @raise [ArgumentError] if transport type is invalid or required fields are missing
      def initialize(name:, transport:)
        @name = name.to_s
        @transport = normalize_transport(transport)
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
          transport: transport
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
    end
  end
end
