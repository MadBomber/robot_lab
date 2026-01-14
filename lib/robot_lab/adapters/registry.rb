# frozen_string_literal: true

module RobotLab
  module Adapters
    # Registry for looking up provider adapters
    #
    # Maps provider symbols to their adapter classes.
    #
    # @example
    #   adapter = Registry.for(:anthropic)
    #   adapter.format_messages(messages)
    #
    module Registry
      ADAPTERS = {
        anthropic: Anthropic,
        openai: OpenAI,
        gemini: Gemini,
        # Azure uses OpenAI adapter
        azure_openai: OpenAI,
        # Grok uses OpenAI adapter
        grok: OpenAI,
        # Ollama uses OpenAI adapter
        ollama: OpenAI,
        # OpenRouter uses OpenAI adapter
        openrouter: OpenAI,
        # Bedrock uses Anthropic adapter
        bedrock: Anthropic,
        # VertexAI uses Gemini adapter
        vertexai: Gemini
      }.freeze

      class << self
        # Get adapter for a provider
        #
        # @param provider [Symbol, String] Provider name
        # @return [Base] Adapter instance
        # @raise [ArgumentError] If provider not found
        #
        def for(provider)
          provider_sym = provider.to_s.downcase.gsub("-", "_").to_sym
          adapter_class = ADAPTERS[provider_sym]

          unless adapter_class
            raise ArgumentError, "Unknown provider: #{provider}. " \
                                 "Available providers: #{available.join(', ')}"
          end

          adapter_class.new
        end

        # List available providers
        #
        # @return [Array<Symbol>]
        #
        def available
          ADAPTERS.keys
        end

        # Check if provider is supported
        #
        # @param provider [Symbol, String]
        # @return [Boolean]
        #
        def supports?(provider)
          provider_sym = provider.to_s.downcase.gsub("-", "_").to_sym
          ADAPTERS.key?(provider_sym)
        end

        # Register a custom adapter
        #
        # @param provider [Symbol] Provider name
        # @param adapter_class [Class] Adapter class
        #
        def register(provider, adapter_class)
          ADAPTERS[provider.to_sym] = adapter_class
        end
      end
    end
  end
end
