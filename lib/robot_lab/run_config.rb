# frozen_string_literal: true

module RobotLab
  # Shared configuration object for LLM, tools, callbacks, and infrastructure.
  #
  # RunConfig provides a unified way to express operational defaults that flow
  # through the configuration hierarchy:
  #
  #   RobotLab.config -> Network -> Robot -> Template front matter -> Task -> Runtime
  #
  # Only explicitly set values are stored. Merge semantics: the more-specific
  # config's non-nil values win over the less-specific config.
  #
  # @example Keyword construction
  #   config = RunConfig.new(model: "claude-sonnet-4", temperature: 0.7)
  #
  # @example Block DSL
  #   config = RunConfig.new do |c|
  #     c.model "claude-sonnet-4"
  #     c.temperature 0.7
  #   end
  #
  # @example Merge (more-specific wins)
  #   network_config = RunConfig.new(model: "claude-sonnet-4", temperature: 0.5)
  #   robot_config   = RunConfig.new(temperature: 0.9)
  #   effective       = network_config.merge(robot_config)
  #   effective.temperature  #=> 0.9
  #   effective.model        #=> "claude-sonnet-4"
  #
  class RunConfig
    # LLM configuration fields (applied to chat via with_* methods)
    LLM_FIELDS = %i[
      model temperature top_p top_k max_tokens
      presence_penalty frequency_penalty stop
    ].freeze

    # Tool-related fields
    TOOL_FIELDS = %i[mcp tools].freeze

    # Callback fields (Procs)
    CALLBACK_FIELDS = %i[on_tool_call on_tool_result on_content].freeze

    # Infrastructure fields
    INFRA_FIELDS = %i[bus enable_cache max_tool_rounds token_budget cost_budget ractor_pool_size
                      max_concurrent_robots doom_loop_threshold auto_compact compact_threshold max_tools].freeze

    # All recognized fields
    FIELDS = (LLM_FIELDS + TOOL_FIELDS + CALLBACK_FIELDS + INFRA_FIELDS).freeze

    # Fields that cannot be serialized to JSON (Procs, IO objects, etc.)
    # auto_compact is excluded because it may be a Proc.
    NON_SERIALIZABLE_FIELDS = (CALLBACK_FIELDS + %i[bus auto_compact]).freeze

    # Creates a new RunConfig.
    #
    # @param kwargs [Hash] field values to set
    # @yield [self] optional block for DSL-style configuration
    def initialize(**kwargs)
      @fields = {}

      kwargs.each do |key, value|
        set(key, value)
      end

      yield self if block_given?
    end

    # Define getter/setter DSL methods for each field.
    #
    # With no arguments: returns the current value (getter).
    # With one argument: sets the value and returns self (chainable setter).
    FIELDS.each do |field|
      define_method(field) do |value = :__unset__|
        if value == :__unset__
          @fields[field]
        else
          set(field, value)
          self
        end
      end
    end

    # Returns a duplicate of the internal fields hash.
    #
    # @return [Hash] only the fields that have been explicitly set
    def to_h
      @fields.dup
    end

    # Returns a JSON-safe hash (skips Procs, IO, and other non-serializable values).
    #
    # @return [Hash]
    def to_json_hash
      @fields.except(*NON_SERIALIZABLE_FIELDS)
    end

    # Merges another RunConfig (or Hash) on top of this one.
    # The other's non-nil values win. Returns a new RunConfig.
    #
    # @param other [RunConfig, Hash] the more-specific configuration
    # @return [RunConfig] a new merged RunConfig
    def merge(other)
      other_hash = other.is_a?(RunConfig) ? other.to_h : other
      merged = @fields.merge(other_hash) { |_k, old_v, new_v| new_v.nil? ? old_v : new_v }
      self.class.new(**merged)
    end

    # Applies LLM fields to a chat object via its with_* methods.
    #
    # +provider+/+assume_model_exists+ are threaded through to +with_model+
    # specifically (RunConfig itself has no provider field -- provider lives
    # on the Robot). Without this, re-applying a RunConfig after the chat's
    # provider/model were already set via Robot#initialize (e.g. during
    # template front-matter merging) drops that context on the floor and
    # `with_model` falls back to the static model registry lookup, which
    # raises ModelNotFoundError for any local-provider model (Ollama, etc.)
    # not in RubyLLM's bundled registry.
    #
    # @param chat [Object] a RubyLLM::Chat (or similar) that responds to with_model, with_temperature, etc.
    # @param provider [String, Symbol, nil] passed through to chat.with_model's provider: kwarg
    # @param assume_model_exists [Boolean] passed through to chat.with_model's assume_exists: kwarg
    def apply_to(chat, provider: nil, assume_model_exists: false)
      LLM_FIELDS.each do |field|
        value = @fields[field]
        next unless value

        if field == :model && provider
          # Only take the provider-aware path when a provider was actually
          # given -- preserves the original single-arg call (and thus
          # compatibility with any chat-like object exposing only
          # `with_model(value)`) for the common case.
          chat.with_model(value, provider:, assume_exists: assume_model_exists) if chat.respond_to?(:with_model)
        else
          method = :"with_#{field}"
          chat.public_send(method, value) if chat.respond_to?(method)
        end
      end
    end

    # Build a RunConfig from prompt_manager front matter metadata.
    #
    # @param metadata [Object] a PM::Metadata object (responds to field names)
    # @return [RunConfig]
    def self.from_front_matter(metadata)
      fields = {}

      LLM_FIELDS.each do |key|
        value = metadata.respond_to?(key) ? metadata.send(key) : nil
        fields[key] = value if value
      end

      # Extract tool-related fields
      %i[mcp tools].each do |key|
        value = metadata.respond_to?(key) ? metadata.send(key) : nil
        fields[key] = value if value
      end

      new(**fields)
    end

    # @return [Boolean] true if no fields have been set
    def empty?
      @fields.empty?
    end

    # @param field [Symbol] the field name
    # @return [Boolean] true if the field has been explicitly set
    def key?(field)
      @fields.key?(field)
    end

    # @param other [RunConfig] the other RunConfig to compare
    # @return [Boolean]
    def ==(other)
      other.is_a?(RunConfig) && to_h == other.to_h
    end

    # @return [String]
    def inspect
      "#<#{self.class} #{@fields.inspect}>"
    end

    private

    # Validates and stores a field value. Nil removes the key.
    def set(field, value)
      field = field.to_sym
      raise ArgumentError, "Unknown RunConfig field: #{field}" unless FIELDS.include?(field)

      if value.nil?
        @fields.delete(field)
      else
        @fields[field] = value
      end
    end
  end
end
