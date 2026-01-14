# frozen_string_literal: true

module RobotLab
  # Handles hierarchical MCP and tools configuration resolution
  #
  # Configuration hierarchy (each level overrides the previous):
  # 1. RobotLab.configuration (global)
  # 2. Network.new (network scope)
  # 3. Robot.new (robot definition scope)
  # 4. robot.run (runtime scope)
  #
  # Value semantics:
  # - :inherit     -> Use parent level's configuration
  # - nil          -> No items allowed
  # - []           -> No items allowed
  # - :none        -> No items allowed
  # - [item1, ...] -> Only these specific items allowed
  #
  # @example
  #   ToolConfig.resolve(:inherit, parent_value: %w[tool1 tool2])
  #   # => ["tool1", "tool2"]
  #
  #   ToolConfig.resolve(nil, parent_value: %w[tool1 tool2])
  #   # => []
  #
  #   ToolConfig.resolve(%w[tool3], parent_value: %w[tool1 tool2])
  #   # => ["tool3"]
  #
  module ToolConfig
    NONE_VALUES = [nil, [], :none].freeze

    class << self
      # Resolve a configuration value against its parent
      #
      # @param value [Symbol, Array, nil] The current level's value
      # @param parent_value [Array] The parent level's resolved value
      # @return [Array] The resolved configuration
      #
      def resolve(value, parent_value:)
        return Array(parent_value) if value == :inherit
        return [] if none_value?(value)

        Array(value)
      end

      # Resolve MCP servers configuration
      #
      # @param value [Symbol, Array, nil] MCP configuration
      # @param parent_value [Array] Parent's MCP servers
      # @return [Array] Resolved MCP server configurations
      #
      def resolve_mcp(value, parent_value:)
        resolve(value, parent_value: parent_value)
      end

      # Resolve tools configuration
      #
      # @param value [Symbol, Array, nil] Tools configuration (tool names as strings)
      # @param parent_value [Array] Parent's tools
      # @return [Array<String>] Resolved tool names
      #
      def resolve_tools(value, parent_value:)
        resolved = resolve(value, parent_value: parent_value)
        resolved.map(&:to_s)
      end

      # Check if value represents "no items"
      #
      # @param value [Object] Value to check
      # @return [Boolean]
      #
      def none_value?(value)
        NONE_VALUES.include?(value)
      end

      # Check if value represents "inherit from parent"
      #
      # @param value [Object] Value to check
      # @return [Boolean]
      #
      def inherit_value?(value)
        value == :inherit
      end

      # Filter tools based on allowed tool names
      #
      # Given a list of tool objects and a whitelist of tool names,
      # returns only the tools whose names are in the whitelist.
      #
      # @param tools [Array] Tool objects (must respond to :name)
      # @param allowed_names [Array<String>] Whitelist of tool names
      # @return [Array] Filtered tools
      #
      def filter_tools(tools, allowed_names:)
        return [] if allowed_names.empty?

        allowed_set = allowed_names.map(&:to_s).to_set
        tools.select { |tool| allowed_set.include?(tool_name(tool)) }
      end

      private

      def tool_name(tool)
        case tool
        when String then tool
        when Symbol then tool.to_s
        else tool.respond_to?(:name) ? tool.name.to_s : tool.to_s
        end
      end
    end
  end
end
