# frozen_string_literal: true

module RobotLab
  module Adapters
    # Adapter for Anthropic Claude models
    #
    # Handles Anthropic-specific API conventions:
    # - System message as top-level parameter (not in messages array)
    # - Tool use/result format differences
    # - Content block structure
    #
    class Anthropic < Base
      def initialize
        super(:anthropic)
      end

      # Format messages for Anthropic API
      #
      # Anthropic requires system message at top level, not in messages array.
      # Also handles tool_use and tool_result message formats.
      #
      # @param messages [Array<Message>]
      # @return [Array<Hash>]
      #
      def format_messages(messages)
        conversation_messages(messages).map do |msg|
          format_single_message(msg)
        end
      end

      # Parse Anthropic response into internal messages
      #
      # @param response [RubyLLM::Response] ruby_llm response object
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

      # Format tools for Anthropic
      #
      # @param tools [Array<Tool>]
      # @return [Array<Hash>]
      #
      def format_tools(tools)
        tools.map do |tool|
          schema = tool.to_json_schema
          {
            name: schema[:name],
            description: schema[:description],
            input_schema: schema[:parameters] || { type: "object", properties: {} }
          }
        end
      end

      # Anthropic tool choice format
      #
      # @param choice [String, Symbol]
      # @return [Hash]
      #
      def format_tool_choice(choice)
        case choice.to_s
        when "auto" then { type: "auto" }
        when "any" then { type: "any" }
        else { type: "tool", name: choice.to_s }
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
            content: msg.tools.map do |tool|
              {
                type: "tool_use",
                id: tool.id,
                name: tool.name,
                input: tool.input
              }
            end
          }
        when ToolResultMessage
          {
            role: "user",
            content: [
              {
                type: "tool_result",
                tool_use_id: msg.tool.id,
                content: format_tool_result_content(msg.content)
              }
            ]
          }
        else
          { role: msg.role, content: msg.content.to_s }
        end
      end

      def format_tool_result_content(content)
        case content
        when Hash
          if content[:error]
            JSON.generate(content)
          elsif content[:data]
            content[:data].is_a?(String) ? content[:data] : JSON.generate(content[:data])
          else
            JSON.generate(content)
          end
        else
          content.to_s
        end
      end

      def parse_tool_arguments(arguments)
        case arguments
        when String
          begin
            JSON.parse(arguments, symbolize_names: true)
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
