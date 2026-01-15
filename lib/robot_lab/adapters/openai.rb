# frozen_string_literal: true

module RobotLab
  module Adapters
    # Adapter for OpenAI GPT models
    #
    # Handles OpenAI-specific API conventions:
    # - Function calling format
    # - Strict mode for structured outputs
    # - finish_reason to stop_reason mapping
    #
    class OpenAI < Base
      # Creates a new OpenAI adapter instance.
      def initialize
        super(:openai)
      end

      # Format messages for OpenAI API
      #
      # @param messages [Array<Message>]
      # @return [Array<Hash>]
      #
      def format_messages(messages)
        messages.map { |msg| format_single_message(msg) }
      end

      # Parse OpenAI response into internal messages
      #
      # @param response [RubyLLM::Response]
      # @return [Array<Message>]
      #
      def parse_response(response)
        messages = []

        # Handle text content
        if response.content && !response.content.empty?
          messages << TextMessage.new(
            role: "assistant",
            content: response.content,
            stop_reason: response.tool_calls&.any? ? "tool" : "stop"
          )
        end

        # Handle tool calls
        if response.tool_calls&.any?
          tool_messages = response.tool_calls.map do |id, tool_call|
            ToolMessage.new(
              id: id,
              name: tool_call.name,
              input: parse_tool_arguments(tool_call.arguments)
            )
          end

          messages << ToolCallMessage.new(
            role: "assistant",
            tools: tool_messages,
            stop_reason: "tool"
          )
        end

        messages
      end

      # Format tools for OpenAI function calling
      #
      # @param tools [Array<Tool>]
      # @return [Array<Hash>]
      #
      def format_tools(tools)
        tools.map do |tool|
          schema = tool.to_json_schema
          {
            type: "function",
            function: {
              name: schema[:name],
              description: schema[:description],
              parameters: schema[:parameters] || { type: "object", properties: {} },
              strict: tool.strict.nil? ? true : tool.strict
            }.compact
          }
        end
      end

      # OpenAI tool choice format
      #
      # @param choice [String, Symbol]
      # @return [String, Hash]
      #
      def format_tool_choice(choice)
        case choice.to_s
        when "auto" then "auto"
        when "any" then "required"
        when "none" then "none"
        else { type: "function", function: { name: choice.to_s } }
        end
      end

      private

      def format_single_message(msg)
        case msg
        when TextMessage
          { role: msg.role, content: msg.content }
        when ToolCallMessage
          {
            role: "assistant",
            content: nil,
            tool_calls: msg.tools.map do |tool|
              {
                id: tool.id,
                type: "function",
                function: {
                  name: tool.name,
                  arguments: JSON.generate(tool.input)
                }
              }
            end
          }
        when ToolResultMessage
          {
            role: "tool",
            tool_call_id: msg.tool.id,
            content: format_tool_result_content(msg.content)
          }
        else
          { role: msg.role, content: msg.content.to_s }
        end
      end

      def format_tool_result_content(content)
        case content
        when Hash
          JSON.generate(content)
        when String
          content
        else
          content.to_s
        end
      end

      def parse_tool_arguments(arguments)
        case arguments
        when String
          # Handle OpenAI's backtick wrapping quirk
          cleaned = arguments.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "")
          begin
            JSON.parse(cleaned, symbolize_names: true)
          rescue JSON::ParserError
            { raw: arguments }
          end
        when Hash
          arguments.transform_keys(&:to_sym)
        else
          arguments || {}
        end
      end
    end
  end
end
