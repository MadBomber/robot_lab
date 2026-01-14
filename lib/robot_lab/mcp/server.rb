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
      VALID_TRANSPORT_TYPES = %w[stdio sse ws websocket streamable-http http].freeze

      attr_reader :name, :transport

      def initialize(name:, transport:)
        @name = name.to_s
        @transport = normalize_transport(transport)
        validate!
      end

      def transport_type
        @transport[:type]
      end

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
