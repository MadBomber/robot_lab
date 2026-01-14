# frozen_string_literal: true

module RobotLab
  module MCP
    module Transports
      # Base class for MCP transports
      #
      # @abstract Subclass and implement {#connect}, {#send_request}, {#close}
      #
      class Base
        attr_reader :config

        def initialize(config)
          @config = config.transform_keys(&:to_sym)
        end

        # Connect to the server
        #
        # @return [self]
        #
        def connect
          raise NotImplementedError
        end

        # Send a JSON-RPC request
        #
        # @param message [Hash] JSON-RPC message
        # @return [Hash] Response
        #
        def send_request(message)
          raise NotImplementedError
        end

        # Close the connection
        #
        # @return [self]
        #
        def close
          raise NotImplementedError
        end

        def connected?
          false
        end
      end
    end
  end
end
