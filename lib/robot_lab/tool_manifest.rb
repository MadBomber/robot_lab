# frozen_string_literal: true

module RobotLab
  # Registry of tools with lookup by name
  #
  # ToolManifest provides a collection interface for managing multiple tools,
  # with methods for lookup, iteration, and conversion to various formats.
  #
  # @example Creating a manifest
  #   manifest = ToolManifest.new([weather_tool, calculator_tool])
  #   manifest[:get_weather]  # => Tool
  #   manifest.names          # => ["get_weather", "calculate"]
  #
  class ToolManifest
    include Enumerable

    def initialize(tools = [])
      @tools = {}
      Array(tools).each { |tool| add(tool) }
    end

    # Add a tool to the manifest
    #
    # @param tool [Tool] The tool to add
    # @return [self]
    #
    def add(tool)
      @tools[tool.name] = tool
      self
    end
    alias << add

    # Remove a tool from the manifest
    #
    # @param name [String, Symbol] The tool name
    # @return [Tool, nil] The removed tool
    #
    def remove(name)
      @tools.delete(name.to_s)
    end

    # Get a tool by name
    #
    # @param name [String, Symbol] The tool name
    # @return [Tool, nil]
    #
    def [](name)
      @tools[name.to_s]
    end

    # Get a tool by name, raising if not found
    #
    # @param name [String, Symbol] The tool name
    # @return [Tool]
    # @raise [ToolNotFoundError] If tool doesn't exist
    #
    def fetch(name)
      @tools.fetch(name.to_s) do
        raise ToolNotFoundError, "Tool not found: #{name}. Available tools: #{names.join(', ')}"
      end
    end

    # Check if a tool exists
    #
    # @param name [String, Symbol] The tool name
    # @return [Boolean]
    #
    def include?(name)
      @tools.key?(name.to_s)
    end
    alias has? include?

    # Get all tool names
    #
    # @return [Array<String>]
    #
    def names
      @tools.keys
    end

    # Get all tools
    #
    # @return [Array<Tool>]
    #
    def values
      @tools.values
    end
    alias all values
    alias to_a values

    # Number of tools
    #
    # @return [Integer]
    #
    def size
      @tools.size
    end
    alias count size
    alias length size

    # Check if manifest is empty
    #
    # @return [Boolean]
    #
    def empty?
      @tools.empty?
    end

    # Iterate over tools
    #
    # @yield [Tool] Each tool in the manifest
    #
    def each(&block)
      @tools.values.each(&block)
    end

    # Clear all tools
    #
    # @return [self]
    #
    def clear
      @tools.clear
      self
    end

    # Replace all tools
    #
    # @param tools [Array<Tool>] New tools
    # @return [self]
    #
    def replace(tools)
      clear
      Array(tools).each { |tool| add(tool) }
      self
    end

    # Merge another manifest or array of tools
    #
    # @param other [ToolManifest, Array<Tool>] Tools to merge
    # @return [self]
    #
    def merge(other)
      case other
      when ToolManifest
        other.each { |tool| add(tool) }
      when Array
        other.each { |tool| add(tool) }
      when Tool
        add(other)
      end
      self
    end

    # Convert to hash for JSON Schema
    #
    # @return [Hash] Map of tool names to their JSON schemas
    #
    def to_json_schema
      @tools.transform_values(&:to_json_schema)
    end

    # Convert to array of ruby_llm Tool classes
    #
    # @return [Array<Class>]
    #
    def to_ruby_llm_tools
      @tools.values.map(&:to_ruby_llm_tool)
    end

    def to_h
      @tools.transform_values(&:to_h)
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    # Create manifest from hash of tool definitions
    #
    # @param hash [Hash] Map of names to tool configs
    # @return [ToolManifest]
    #
    def self.from_hash(hash)
      tools = hash.map do |name, config|
        Tool.new(
          name: name,
          description: config[:description],
          parameters: config[:parameters],
          handler: config[:handler]
        )
      end
      new(tools)
    end
  end
end
