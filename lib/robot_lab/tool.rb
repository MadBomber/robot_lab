# frozen_string_literal: true

module RobotLab
  # A tool that robots can use, built on RubyLLM::Tool.
  #
  # Provides two patterns for defining tools:
  #
  # 1. **Subclass pattern** — for reusable, robot-aware tools:
  #
  #   class GetWeather < RobotLab::Tool
  #     description "Get weather for a location"
  #     param :location, type: "string", desc: "City name"
  #
  #     def execute(location:)
  #       WeatherService.fetch(location)
  #     end
  #   end
  #
  # 2. **Factory pattern** — for dynamic/inline tools:
  #
  #   tool = RobotLab::Tool.create(
  #     name: "get_time",
  #     description: "Get the current time"
  #   ) { |args| Time.now.to_s }
  #
  # Subclasses have access to the owning +robot+ via an accessor,
  # enabling tools that modify their robot's state (temperature,
  # system prompt, spawning, etc.).
  #
  class Tool < RubyLLM::Tool
    # @!attribute [rw] robot
    #   @return [Robot, nil] the robot that owns this tool
    attr_accessor :robot

    # @!attribute [r] mcp
    #   @return [String, nil] the MCP server name if this is an MCP-provided tool
    attr_reader :mcp

    class << self
      # When true, exceptions from #execute propagate instead of being caught.
      # Default: false (graceful error handling).
      #
      # @return [Boolean]
      attr_writer :raise_on_error

      def raise_on_error?
        defined?(@raise_on_error) ? @raise_on_error : false
      end
    end

    # Creates a new Tool instance.
    #
    # @param robot [Robot, nil] the owning robot
    def initialize(robot: nil)
      super()
      @robot = robot
    end

    # Wraps RubyLLM::Tool#call with error handling so the LLM receives
    # a plain-text error message instead of crashing the run.
    #
    # @param args [Hash] the tool arguments from the LLM
    # @return [Object] the tool result or an error string
    def call(args)
      super
    rescue StandardError => e
      raise if self.class.raise_on_error?

      RobotLab.config.logger.warn("Tool '#{name}' error: #{e.class}: #{e.message}")
      "Error (#{name}): #{e.message}"
    end

    # Override name to support explicit names for dynamic/MCP tools.
    #
    # @return [String] the tool name
    def name
      defined?(@custom_name) && @custom_name ? @custom_name : super
    end

    # Check if this is an MCP-provided tool.
    #
    # @return [Boolean]
    def mcp?
      !@mcp.nil?
    end

    # Factory for dynamic tools (MCP wrappers, inline tools).
    #
    # @param name [String, Symbol] the tool name
    # @param description [String, nil] what the tool does
    # @param parameters [Hash, nil] JSON Schema parameter definition
    # @param mcp [String, nil] MCP server name
    # @param robot [Robot, nil] the owning robot
    # @yield [args] block that executes the tool logic
    # @return [Tool] a new tool instance
    #
    # @example Simple factory tool
    #   tool = RobotLab::Tool.create(
    #     name: "get_time",
    #     description: "Get the current time"
    #   ) { |args| Time.now.to_s }
    #
    # @example MCP tool wrapper
    #   tool = RobotLab::Tool.create(
    #     name: "search",
    #     description: "Search the web",
    #     parameters: { type: "object", properties: { q: { type: "string" } }, required: ["q"] },
    #     mcp: "brave_search"
    #   ) { |args| mcp_client.call_tool("search", args) }
    #
    def self.create(name:, description: nil, parameters: nil, mcp: nil, robot: nil, &handler)
      desc_text = description
      params_hash = parameters
      block = handler

      tool_class = Class.new(self) do
        description(desc_text) if desc_text

        if params_hash.is_a?(Hash) && params_hash[:properties]
          required_list = Array(params_hash[:required]).map(&:to_s)
          params_hash[:properties].each do |pname, pdef|
            param pname.to_sym,
                  type: pdef[:type] || "string",
                  desc: pdef[:description],
                  required: required_list.include?(pname.to_s)
          end
        end

        define_method(:execute) do |**args|
          block.call(args)
        end
      end

      instance = tool_class.new(robot: robot)
      instance.instance_variable_set(:@custom_name, name.to_s)
      instance.instance_variable_set(:@mcp, mcp)
      instance
    end

    # Convert to JSON Schema for LLM function calling.
    # Used by RobotLab adapters for provider-specific formatting.
    #
    # @return [Hash] JSON Schema representation
    def to_json_schema
      schema = params_schema || { "type" => "object", "properties" => {}, "required" => [] }
      {
        name: name,
        description: description,
        parameters: deep_symbolize_keys(schema)
      }.compact
    end

    # Hash representation.
    #
    # @return [Hash]
    def to_h
      {
        name: name,
        description: description,
        mcp: mcp
      }.compact
    end

    # JSON representation.
    #
    # @param args [Array] arguments passed to to_json
    # @return [String]
    def to_json(*args)
      to_h.to_json(*args)
    end

    private

    def deep_symbolize_keys(obj)
      case obj
      when Hash
        obj.each_with_object({}) { |(k, v), h| h[k.to_sym] = deep_symbolize_keys(v) }
      when Array
        obj.map { |v| deep_symbolize_keys(v) }
      else
        obj
      end
    end
  end
end
