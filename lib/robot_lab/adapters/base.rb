# frozen_string_literal: true

module RobotLab
  module Adapters
    # Base adapter interface for LLM providers
    #
    # Adapters handle provider-specific message formatting and response parsing.
    # Each provider (Anthropic, OpenAI, Gemini) has different API conventions
    # that the adapter normalizes.
    #
    # @abstract Subclass and implement {#format_messages} and {#parse_response}
    #
    class Base
      # @!attribute [r] provider
      #   @return [Symbol] the provider name
      attr_reader :provider

      # Creates a new adapter instance.
      #
      # @param provider [Symbol] the provider name
      def initialize(provider)
        @provider = provider
      end

      # Format internal messages for the provider's API
      #
      # @param messages [Array<Message>] Internal message format
      # @return [Array<Hash>] Provider-specific message format
      #
      def format_messages(messages)
        raise NotImplementedError, "#{self.class}#format_messages must be implemented"
      end

      # Parse provider response into internal message format
      #
      # @param response [Object] Provider-specific response
      # @return [Array<Message>] Internal message format
      #
      def parse_response(response)
        raise NotImplementedError, "#{self.class}#parse_response must be implemented"
      end

      # Format tools for the provider's function calling API
      #
      # @param tools [Array<Tool>] Internal tool definitions
      # @return [Array<Hash>] Provider-specific tool format
      #
      def format_tools(tools)
        tools.map(&:to_json_schema)
      end

      # Format tool choice for the provider
      #
      # @param choice [String, Symbol] "auto", "any", or specific tool name
      # @return [Object] Provider-specific tool choice
      #
      def format_tool_choice(choice)
        case choice.to_s
        when "auto" then "auto"
        when "any" then "required"
        else { type: "function", function: { name: choice.to_s } }
        end
      end

      # Extract system message from messages array
      #
      # @param messages [Array<Message>]
      # @return [String, nil]
      #
      def extract_system_message(messages)
        system_msg = messages.find(&:system?)
        system_msg&.content
      end

      # Filter out system messages
      #
      # @param messages [Array<Message>]
      # @return [Array<Message>]
      #
      def conversation_messages(messages)
        messages.reject(&:system?)
      end
    end
  end
end
