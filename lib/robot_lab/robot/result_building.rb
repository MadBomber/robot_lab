# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    # Adapts a ruby_llm response into a RobotResult, including token
    # accounting, stop-reason normalization, and message coercion helpers.
    #
    # Owns:    nothing (pure adapters over the response and @chat)
    # Reads:   @chat, @name; Writes: @total_input_tokens, @total_output_tokens
    module ResultBuilding
      private

      # :reek:TooManyStatements :reek:FeatureEnvy -- adapting a provider response's many optional fields into
      #   a RobotResult is inherently response-centric.
      def build_result(response, _memory)
        text = result_text(response)
        output = text ? [TextMessage.new(role: 'assistant', content: text)] : []

        tool_calls = response.respond_to?(:tool_calls) ? (response.tool_calls || []) : []

        input_toks, output_toks = extract_token_counts(response)
        @total_input_tokens += input_toks
        @total_output_tokens += output_toks

        RobotResult.new(
          robot_name: @name,
          output: output,
          tool_calls: normalize_tool_calls(tool_calls),
          stop_reason: extract_stop_reason(response),
          raw: response,
          input_tokens: input_toks,
          output_tokens: output_toks
        )
      end

      # Token usage from the response. ruby_llm 2.0 nests counts under
      # response.tokens; duck-typed responses may still answer input_tokens.
      # :reek:FeatureEnvy -- reading the response's optional token fields is the extraction itself.
      def extract_token_counts(response)
        if response.respond_to?(:tokens) && (tokens = response.tokens)
          [tokens.input.to_i, tokens.output.to_i]
        elsif response.respond_to?(:input_tokens)
          [response.input_tokens.to_i,
           response.respond_to?(:output_tokens) ? response.output_tokens.to_i : 0]
        else
          [0, 0]
        end
      end

      # ruby_llm 2.0's add_message accepts a Message, an attribute Hash, or a
      # record responding to to_llm. Compression summaries (and tests) hand us
      # plain role/content value objects; convert those to attribute hashes so
      # the chat can coerce them.
      def coerce_replacement_message(message)
        if message.is_a?(RubyLLM::Message) || message.is_a?(Hash) || message.respond_to?(:to_llm)
          message
        else
          { role: message.role, content: message.content }
        end
      end

      # The response's normalized stop reason. ruby_llm 2.0 exposes it as
      # finish_reason (a Symbol such as :stop or :tool_calls); older or
      # duck-typed responses may still answer stop_reason.
      def extract_stop_reason(response)
        return response.finish_reason if response.respond_to?(:finish_reason)

        response.respond_to?(:stop_reason) ? response.stop_reason : nil
      end

      # Text for the result's output. Prefers the final response's content, then
      # falls back in order to: (1) thinking text for models that route all output
      # through reasoning_content (e.g. qwen3 on Ollama), (2) the most recent
      # assistant text within the current turn for models that end on a tool call
      # with no trailing text.
      #
      # The chat-history fallback is scoped to messages AFTER the last user message
      # (the current turn) to prevent a previous turn's response from being returned
      # when a thinking-mode model emits nothing in response.content.
      # :reek:TooManyStatements :reek:FeatureEnvy -- documented fallback chain over the response's optional content/thinking/history fields.
      def result_text(response)
        content = response.content if response.respond_to?(:content)
        return content if content && !content.to_s.empty?

        # Ollama routes qwen3's reasoning to reasoning_content, which ruby_llm
        # surfaces as response.thinking (a RubyLLM::Thinking object). When content
        # is nil and thinking is present, the thinking IS the response for that turn.
        if response.respond_to?(:thinking) && (thinking = response.thinking)
          thinking_text = thinking.respond_to?(:text) ? thinking.text.to_s : thinking.to_s
          return thinking_text unless thinking_text.empty?
        end

        return nil unless @chat.respond_to?(:messages)

        messages = @chat.messages
        last_user_idx = messages.rindex { |m| m.role == :user } || -1
        current_turn = messages[(last_user_idx + 1)..]

        last = current_turn.rfind { |m| m.role == :assistant && m.content && !m.content.to_s.empty? }
        last&.content
      end

      def normalize_tool_calls(tool_calls)
        return [] unless tool_calls

        tool_calls.map do |tc|
          if tc.is_a?(Hash)
            ToolResultMessage.new(
              tool: tc,
              content: tc[:result] || tc['result']
            )
          else
            tc
          end
        end
      end
    end
  end
end
