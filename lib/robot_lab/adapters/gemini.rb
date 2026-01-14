# frozen_string_literal: true

module RobotLab
  module Adapters
    # Adapter for Google Gemini models
    #
    # Handles Gemini-specific API conventions:
    # - Role mapping (assistant -> model)
    # - Contents/parts array structure
    # - functionCall/functionResponse format
    #
    class Gemini < Base
      def initialize
        super(:gemini)
      end

      # Format messages for Gemini API
      #
      # Gemini uses "model" role instead of "assistant" and structures
      # content as parts arrays.
      #
      # @param messages [Array<Message>]
      # @return [Array<Hash>]
      #
      def format_messages(messages)
        # Gemini handles system messages differently - as system_instruction
        conversation_messages(messages).map { |msg| format_single_message(msg) }
      end

      # Parse Gemini response into internal messages
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

        # Handle function calls
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

      # Format tools for Gemini function declarations
      #
      # Gemini doesn't support additionalProperties in schemas
      #
      # @param tools [Array<Tool>]
      # @return [Array<Hash>]
      #
      def format_tools(tools)
        tools.map do |tool|
          schema = tool.to_json_schema
          params = clean_schema_for_gemini(schema[:parameters] || { type: "object", properties: {} })
          {
            name: schema[:name],
            description: schema[:description],
            parameters: params
          }
        end
      end

      # Gemini tool choice format
      #
      # @param choice [String, Symbol]
      # @return [Hash]
      #
      def format_tool_choice(choice)
        case choice.to_s
        when "auto" then { mode: "AUTO" }
        when "any" then { mode: "ANY" }
        when "none" then { mode: "NONE" }
        else { mode: "ANY", allowed_function_names: [choice.to_s] }
        end
      end

      private

      def format_single_message(msg)
        role = gemini_role(msg.role)

        case msg
        when TextMessage
          {
            role: role,
            parts: [{ text: msg.content }]
          }
        when ToolCallMessage
          {
            role: "model",
            parts: msg.tools.map do |tool|
              {
                functionCall: {
                  name: tool.name,
                  args: tool.input
                }
              }
            end
          }
        when ToolResultMessage
          {
            role: "user",
            parts: [
              {
                functionResponse: {
                  name: msg.tool.name,
                  response: format_tool_result_content(msg.content)
                }
              }
            ]
          }
        else
          { role: role, parts: [{ text: msg.content.to_s }] }
        end
      end

      def gemini_role(role)
        case role.to_s
        when "assistant" then "model"
        when "system" then "user"  # Gemini handles system as system_instruction
        else role.to_s
        end
      end

      def format_tool_result_content(content)
        case content
        when Hash
          content
        when String
          { result: content }
        else
          { result: content.to_s }
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

      # Remove additionalProperties which Gemini doesn't support
      def clean_schema_for_gemini(schema)
        return schema unless schema.is_a?(Hash)

        cleaned = schema.dup
        cleaned.delete(:additionalProperties)
        cleaned.delete("additionalProperties")

        if cleaned[:properties]
          cleaned[:properties] = cleaned[:properties].transform_values do |prop|
            clean_schema_for_gemini(prop)
          end
        end

        cleaned
      end
    end
  end
end
