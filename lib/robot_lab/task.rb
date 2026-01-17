# frozen_string_literal: true

module RobotLab
  # Wraps a Robot for use as a pipeline step with per-task configuration
  #
  # Task provides a way to pass step-specific context, MCP servers, tools,
  # and memory to individual robots within a network pipeline. The task's
  # context is deep-merged with the network's run parameters.
  #
  # @example Basic task with context
  #   task = Task.new(
  #     name: :billing,
  #     robot: billing_robot,
  #     context: { department: "billing", escalation_level: 2 }
  #   )
  #
  # @example Task with MCP and tools
  #   task = Task.new(
  #     name: :developer,
  #     robot: dev_robot,
  #     context: { project: "api" },
  #     mcp: [filesystem_server, github_server],
  #     tools: [CodeSearch, FileReader]
  #   )
  #
  class Task
    # @!attribute [r] name
    #   @return [Symbol] the task/step name
    # @!attribute [r] robot
    #   @return [Robot] the wrapped robot instance
    attr_reader :name, :robot

    # Creates a new Task instance.
    #
    # @param name [Symbol] the task/step name
    # @param robot [Robot] the robot instance to wrap
    # @param context [Hash] task-specific context (deep-merged with run params)
    # @param mcp [Symbol, Array] MCP server config (:none, :inherit, or array)
    # @param tools [Symbol, Array] tools config (:none, :inherit, or array)
    # @param memory [Memory, Hash, nil] task-specific memory
    #
    def initialize(name:, robot:, context: {}, mcp: :none, tools: :none, memory: nil)
      @name = name.to_sym
      @robot = robot
      @context = context
      @mcp = mcp
      @tools = tools
      @memory = memory
    end

    # SimpleFlow step interface
    #
    # Enhances the result's run_params with task-specific configuration
    # before delegating to the wrapped robot.
    #
    # @param result [SimpleFlow::Result] incoming result from previous step
    # @return [SimpleFlow::Result] result with robot output
    #
    def call(result)
      # Get current run params and deep merge with task context
      run_params = deep_merge(
        result.context[:run_params] || {},
        @context
      )

      # Add task-specific robot config
      run_params[:mcp] = @mcp unless @mcp == :none
      run_params[:tools] = @tools unless @tools == :none
      run_params[:memory] = @memory if @memory

      # Create enhanced result with merged params
      enhanced_result = result.with_context(:run_params, run_params)

      # Delegate to robot
      @robot.call(enhanced_result)
    end

    # Converts the task to a hash representation.
    #
    # @return [Hash]
    #
    def to_h
      {
        name: @name,
        robot: @robot.name,
        context: @context,
        mcp: @mcp,
        tools: @tools,
        memory: @memory ? true : nil
      }.compact
    end

    private

    # Deep merge two hashes
    #
    # Values from `override` take precedence. Nested hashes are merged
    # recursively. Arrays are replaced, not concatenated.
    #
    # @param base [Hash] the base hash
    # @param override [Hash] the overriding hash
    # @return [Hash] the merged result
    #
    def deep_merge(base, override)
      base = base.transform_keys(&:to_sym)
      override = override.transform_keys(&:to_sym)

      base.merge(override) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end
  end
end
