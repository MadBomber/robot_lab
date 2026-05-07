# frozen_string_literal: true

module RobotLab
  # Error serialization utilities
  #
  # Provides methods to serialize Ruby exceptions into a format
  # suitable for tool results and logging.
  #
  module Errors
    class << self
      # Serialize an exception to a hash
      #
      # @param error [Exception] The error to serialize
      # @param include_backtrace [Boolean] Whether to include backtrace
      # @return [Hash] Serialized error
      #
      def serialize(error, include_backtrace: false)
        result = {
          type: error.class.name,
          message: error.message
        }

        if include_backtrace && error.backtrace
          result[:backtrace] = error.backtrace.first(10)
        end

        if error.cause
          result[:cause] = serialize(error.cause, include_backtrace: include_backtrace)
        end

        result
      end

      # Deserialize an error hash back to an exception
      #
      # @param hash [Hash] Serialized error
      # @return [StandardError]
      #
      def deserialize(hash)
        hash = hash.transform_keys(&:to_sym)
        klass = begin
          Object.const_get(hash[:type])
        rescue NameError
          StandardError
        end
        klass.new(hash[:message])
      end

      # Format error for display
      #
      # @param error [Exception] The error
      # @return [String]
      #
      def format(error)
        "[#{error.class.name}] #{error.message}"
      end

      # Wrap a block and return error hash on failure
      #
      # @yield Block to execute
      # @return [Hash] { data: result } or { error: serialized_error }
      #
      def capture
        { data: yield }
      rescue StandardError => e
        { error: serialize(e) }
      end
    end
  end
end
