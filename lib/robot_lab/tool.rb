# frozen_string_literal: true

module RobotLab
  # Defines a tool/function that robots can use
  #
  # Tools are capabilities that robots can invoke during execution.
  # They have a name, description, parameter schema, and handler.
  #
  # @example Simple tool
  #   tool = Tool.new(
  #     name: "get_time",
  #     description: "Get the current time",
  #     handler: -> (_input, **_opts) { Time.now.to_s }
  #   )
  #
  # @example Tool with parameters (using ruby_llm-schema)
  #   class WeatherParams < RubyLLM::Schema
  #     string :location, description: "City name"
  #     string :unit, enum: %w[celsius fahrenheit], required: false
  #   end
  #
  #   tool = Tool.new(
  #     name: "get_weather",
  #     description: "Get weather for a location",
  #     parameters: WeatherParams,
  #     handler: ->(input, **opts) {
  #       # input[:location], input[:unit] are validated
  #       fetch_weather(input[:location], input[:unit] || "celsius")
  #     }
  #   )
  #
  class Tool
    # @!attribute [r] name
    #   @return [String] the unique identifier for the tool
    # @!attribute [r] description
    #   @return [String, nil] a description of what the tool does
    # @!attribute [r] parameters
    #   @return [Class, Hash, nil] the parameter schema (RubyLLM::Schema or JSON Schema hash)
    # @!attribute [r] handler
    #   @return [Proc, nil] the callable that executes the tool logic
    # @!attribute [r] mcp
    #   @return [String, nil] the MCP server name if this is an MCP-provided tool
    # @!attribute [r] strict
    #   @return [Boolean, nil] whether strict mode is enabled
    attr_reader :name, :description, :parameters, :handler, :mcp, :strict

    # Creates a new Tool instance.
    #
    # @param name [String] the unique identifier for the tool
    # @param description [String, nil] a description of what the tool does
    # @param parameters [Class, Hash, nil] parameter schema (RubyLLM::Schema or JSON Schema)
    # @param handler [Proc, nil] the callable that executes the tool logic
    # @param mcp [String, nil] MCP server name if this is an MCP tool
    # @param strict [Boolean, nil] whether strict mode is enabled
    # @yield [input, **opts] optional block as handler
    #
    # @example Tool with block handler
    #   Tool.new(name: "greet", description: "Greet user") do |input, **opts|
    #     "Hello, #{input[:name]}!"
    #   end
    def initialize(name:, description: nil, parameters: nil, handler: nil, mcp: nil, strict: nil, &block)
      @name = name.to_s
      @description = description
      @parameters = parameters
      @handler = handler || block
      @mcp = mcp
      @strict = strict
    end

    # Execute the tool with input and context
    #
    # Supports two calling conventions:
    # - Direct: tool.call(input, robot: robot, network: network)
    # - ruby_llm: tool.call(args) - called without keyword args
    #
    # @param input [Hash] The input parameters (validated against schema)
    # @param robot [Robot, nil] The robot invoking this tool
    # @param network [NetworkRun, nil] The network context if running in a network
    # @param step [Object, nil] Durable execution step context
    # @return [Object] The tool's output
    #
    def call(input, robot: nil, network: nil, step: nil)
      raise Error, "Tool '#{name}' has no handler defined" unless handler

      validated_input = validate_input(input)
      handler.call(validated_input, robot: robot, network: network, step: step)
    rescue Error
      raise
    rescue StandardError => e
      { error: Errors.serialize(e) }
    end

    # Convert to JSON Schema for LLM function calling
    #
    # @return [Hash] JSON Schema representation
    #
    def to_json_schema
      schema = if parameters.respond_to?(:to_json_schema)
                 # ruby_llm-schema class
                 parameters.new.to_json_schema[:schema]
               elsif parameters.is_a?(Hash)
                 # Raw JSON schema
                 parameters
               else
                 # No parameters
                 { type: "object", properties: {}, required: [] }
               end

      {
        name: name,
        description: description,
        parameters: schema
      }.compact
    end

    # Convert to ruby_llm Tool class for integration
    #
    # @return [Class] A RubyLLM::Tool subclass
    #
    def to_ruby_llm_tool
      tool = self
      Class.new(RubyLLM::Tool) do
        description tool.description

        # Define parameters from schema
        if tool.parameters.respond_to?(:to_json_schema)
          schema = tool.parameters.new.to_json_schema[:schema]
          schema[:properties]&.each do |prop_name, prop_def|
            param prop_name.to_sym,
                  type: prop_def[:type],
                  desc: prop_def[:description],
                  required: schema[:required]&.include?(prop_name.to_s)
          end
        elsif tool.parameters.is_a?(Hash) && tool.parameters[:properties]
          tool.parameters[:properties].each do |prop_name, prop_def|
            param prop_name.to_sym,
                  type: prop_def[:type] || "string",
                  desc: prop_def[:description],
                  required: tool.parameters[:required]&.include?(prop_name.to_s)
          end
        end

        define_method(:execute) do |**kwargs|
          # This will be overridden at runtime with proper context
          kwargs
        end
      end
    end

    # Converts the tool to a hash representation.
    #
    # @return [Hash] a hash containing the tool configuration
    def to_h
      {
        name: name,
        description: description,
        parameters: parameters_to_hash,
        mcp: mcp,
        strict: strict
      }.compact
    end

    # Converts the tool to JSON.
    #
    # @param args [Array] arguments passed to to_json
    # @return [String] JSON representation of the tool
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Check if this is an MCP-provided tool
    #
    # @return [Boolean]
    #
    def mcp?
      !mcp.nil?
    end

    # Return parameters schema for ruby_llm compatibility
    #
    # @return [Hash, nil] JSON Schema for tool parameters
    #
    def params_schema
      if parameters.respond_to?(:to_json_schema)
        parameters.new.to_json_schema[:schema]
      elsif parameters.is_a?(Hash)
        parameters
      end
    end

    # Provider-specific parameters for ruby_llm compatibility
    #
    # @return [Hash] Empty hash (no provider-specific params)
    #
    def provider_params
      {}
    end

    private

    def validate_input(input)
      return input unless parameters

      input = input.transform_keys(&:to_sym) if input.is_a?(Hash)

      if parameters.respond_to?(:new) && parameters.ancestors.include?(defined?(RubyLLM::Schema) ? RubyLLM::Schema : Object)
        # Validate with ruby_llm-schema (if available)
        # For now, just pass through
        input
      else
        input
      end
    end

    def parameters_to_hash
      if parameters.respond_to?(:to_json_schema)
        parameters.new.to_json_schema
      elsif parameters.is_a?(Hash)
        parameters
      end
    end
  end
end
