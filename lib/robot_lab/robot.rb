# frozen_string_literal: true

module RobotLab
  # LLM-powered robot using ruby_llm-template for prompts
  #
  # Robot is a thin wrapper around RubyLLM.chat that provides:
  # - Template-based prompts via ruby_llm-template
  # - Build-time context (static robot configuration)
  # - Run-time context (per-request dynamic data)
  # - Tool integration via RubyLLM::Tool
  # - Hierarchical MCP and tools configuration
  #
  # @example Simple robot with template
  #   robot = Robot.new(
  #     name: "helper",
  #     template: :helper,
  #     context: { company_name: "Acme Corp" }
  #   )
  #   result = robot.run(message: "Hello!", user_name: "Alice")
  #
  # @example Robot with inline system prompt (no template file needed)
  #   robot = Robot.new(
  #     name: "quick_bot",
  #     system_prompt: "You are a helpful assistant. Be concise."
  #   )
  #
  # @example Robot with template and additional system prompt
  #   robot = Robot.new(
  #     name: "support",
  #     template: :support_agent,
  #     system_prompt: "Today is #{Date.today}. Current promotion: 20% off."
  #   )
  #
  # @example Robot with tools
  #   robot = Robot.new(
  #     name: "support",
  #     template: :support,
  #     context: { policies: POLICIES },
  #     tools: [OrderLookup, RefundProcessor]
  #   )
  #
  # @example Robot with hierarchical MCP/tools config
  #   robot = Robot.new(
  #     name: "assistant",
  #     template: :assistant,
  #     mcp: :inherit,              # Inherit from network/config
  #     tools: %w[search_code]      # Only allow search_code tool
  #   )
  #
  class Robot
    # @!attribute [r] name
    #   @return [String] the unique identifier for the robot
    # @!attribute [r] description
    #   @return [String, nil] an optional description of the robot's purpose
    # @!attribute [r] template
    #   @return [Symbol, nil] the ERB template for the robot's prompt
    # @!attribute [r] system_prompt
    #   @return [String, nil] inline system prompt (used alone or appended to template)
    # @!attribute [r] model
    #   @return [String, Object] the LLM model identifier or model object
    # @!attribute [r] local_tools
    #   @return [Array] the locally defined tools for this robot
    # @!attribute [r] mcp_clients
    #   @return [Hash<String, MCP::Client>] connected MCP clients by server name
    # @!attribute [r] mcp_tools
    #   @return [Array<Tool>] tools discovered from MCP servers
    # @!attribute [r] memory
    #   @return [Memory] the robot's inherent memory (used when standalone, not in network)
    attr_reader :name, :description, :template, :system_prompt, :model, :local_tools, :mcp_clients, :mcp_tools, :memory

    # @!attribute [r] mcp_config
    #   @return [Symbol, Array] build-time MCP configuration (raw, unresolved)
    # @!attribute [r] tools_config
    #   @return [Symbol, Array] build-time tools configuration (raw, unresolved)
    attr_reader :mcp_config, :tools_config

    # Creates a new Robot instance.
    #
    # @param name [String] the unique identifier for the robot
    # @param template [Symbol, nil] the ERB template for the robot's prompt
    # @param system_prompt [String, nil] inline system prompt (can be used alone or with template)
    # @param context [Hash, Proc] variables to pass to the template at build time
    # @param description [String, nil] an optional description of the robot's purpose
    # @param local_tools [Array] tools defined locally for this robot
    # @param model [String, nil] the LLM model to use (defaults to config.default_model)
    # @param mcp_servers [Array] legacy parameter for MCP server configurations
    # @param mcp [Symbol, Array] hierarchical MCP config (:none, :inherit, or array of servers)
    # @param tools [Symbol, Array] hierarchical tools config (:none, :inherit, or array of tool names)
    # @param on_tool_call [Proc, nil] callback invoked when a tool is called
    # @param on_tool_result [Proc, nil] callback invoked when a tool returns a result
    # @param enable_cache [Boolean] whether to enable semantic caching (default: true)
    #
    # @example Basic robot with template
    #   Robot.new(name: "helper", template: :helper)
    #
    # @example Robot with inline system prompt
    #   Robot.new(name: "bot", system_prompt: "You are helpful.")
    #
    # @example Robot with template and additional system prompt
    #   Robot.new(name: "bot", template: :base, system_prompt: "Extra context here.")
    #
    # @example Robot with tools and callbacks
    #   Robot.new(
    #     name: "support",
    #     template: :support,
    #     local_tools: [OrderLookup],
    #     on_tool_call: ->(call) { puts "Calling #{call.name}" }
    #   )
    #
    # @raise [ArgumentError] if neither template nor system_prompt is provided
    def initialize(
      name:,
      template: nil,
      system_prompt: nil,
      context: {},
      description: nil,
      local_tools: [],
      model: nil,
      mcp_servers: [],
      mcp: :none,
      tools: :none,
      on_tool_call: nil,
      on_tool_result: nil,
      enable_cache: true
    )
      unless template || system_prompt
        raise ArgumentError, "Must provide either template or system_prompt"
      end

      @name = name.to_s
      @template = template
      @system_prompt = system_prompt
      @build_context = context
      @description = description
      @local_tools = Array(local_tools)
      @model = model || RobotLab.configuration.default_model
      @on_tool_call = on_tool_call
      @on_tool_result = on_tool_result

      # Store raw config values for hierarchical resolution
      # mcp_servers is legacy parameter, mcp is the new hierarchical one
      @mcp_config = mcp_servers.any? ? mcp_servers : mcp
      @tools_config = tools

      # MCP state
      @mcp_clients = {}
      @mcp_tools = []
      @mcp_initialized = false

      # Inherent memory (used when standalone, not in a network)
      @memory = Memory.new(enable_cache: enable_cache)
    end

    # Returns the robot's local tools (alias for local_tools).
    #
    # Provided for backward compatibility with earlier API versions.
    #
    # @return [Array] the locally defined tools
    def tools
      @local_tools
    end

    # Run the robot with the given context
    #
    # @param network [NetworkRun, nil] Network context if running in network
    # @param memory [Memory, Hash, nil] Runtime memory to merge
    # @param mcp [Symbol, Array, nil] Runtime MCP override (:inherit, :none, nil, [], or array of servers)
    # @param tools [Symbol, Array, nil] Runtime tools override (:inherit, :none, nil, [], or array of tool names)
    # @param run_context [Hash] Context for rendering user template
    # @return [RobotResult]
    #
    # @example Standalone robot with inherent memory
    #   robot.run(message: "My name is Alice")
    #   robot.run(message: "What's my name?")  # Memory persists
    #
    # @example Runtime memory injection
    #   robot.run(message: "Hello", memory: { user_id: 123, session: "abc" })
    #
    def run(network: nil, memory: nil, mcp: :none, tools: :none, **run_context)
      # Determine which memory to use:
      # 1. Network memory if running in a network
      # 2. Otherwise, use robot's inherent memory
      run_memory = network&.memory || @memory

      # Merge runtime memory if provided
      case memory
      when Memory
        run_memory = memory
      when Hash
        run_memory.merge!(memory)
      end

      # Resolve hierarchical MCP and tools configuration
      resolved_mcp = resolve_mcp_hierarchy(mcp, network: network)
      resolved_tools = resolve_tools_hierarchy(tools, network: network)

      # Initialize or update MCP clients based on resolved config
      ensure_mcp_clients(resolved_mcp)

      # Merge build context + run context
      full_context = resolve_context(@build_context, network: network)
                       .merge(run_context)

      # Build chat with template, filtered tools, and semantic cache
      chat = build_chat(full_context, allowed_tools: resolved_tools, memory: run_memory)

      # Execute and return result
      response = chat.complete

      build_result(response, run_memory)
    end

    # Reset the robot's inherent memory
    #
    # @return [self]
    #
    def reset_memory
      @memory.reset
      self
    end

    # Disconnect all MCP clients
    #
    # Call this method when done using the robot to clean up MCP connections.
    #
    # @return [self]
    #
    def disconnect
      @mcp_clients.each_value(&:disconnect)
      self
    end

    # Converts the robot to a hash representation.
    #
    # @return [Hash] a hash containing the robot's configuration
    def to_h
      {
        name: name,
        description: description,
        template: template,
        system_prompt: system_prompt,
        local_tools: local_tools.map { |t| t.respond_to?(:name) ? t.name : t.to_s },
        mcp_tools: mcp_tools.map(&:name),
        mcp_config: @mcp_config,
        tools_config: @tools_config,
        mcp_servers: @mcp_clients.keys,
        model: model.respond_to?(:model_id) ? model.model_id : model
      }.compact
    end

    private

    def resolve_context(context, network:)
      case context
      when Proc then context.call(network: network)
      when Hash then context
      else {}
      end
    end

    def build_chat(context, allowed_tools:, memory:)
      model_id = @model.respond_to?(:model_id) ? @model.model_id : @model.to_s

      chat = RubyLLM.chat(model: model_id)

      # Wrap with semantic cache for automatic caching (if enabled)
      chat = memory.cache.wrap(chat) if memory.cache

      # Apply template and/or system_prompt
      # - Template only: use with_template
      # - system_prompt only: use with_instructions
      # - Both: use with_template, then append with_instructions
      if @template
        chat = chat.with_template(@template, **context)
        chat = chat.with_instructions(@system_prompt) if @system_prompt
      else
        chat = chat.with_instructions(@system_prompt)
      end

      # Get filtered tools based on whitelist
      filtered = filtered_tools(allowed_tools)
      chat = chat.with_tools(*filtered) if filtered.any?

      # Add callbacks if provided
      chat = chat.on_tool_call(&@on_tool_call) if @on_tool_call
      chat = chat.on_tool_result(&@on_tool_result) if @on_tool_result

      chat
    end

    def build_result(response, _memory)
      output = if response.respond_to?(:content) && response.content
                 [TextMessage.new(role: "assistant", content: response.content)]
               else
                 []
               end

      tool_calls = response.respond_to?(:tool_calls) ? (response.tool_calls || []) : []

      RobotResult.new(
        robot_name: @name,
        output: output,
        tool_calls: normalize_tool_calls(tool_calls),
        stop_reason: response.respond_to?(:stop_reason) ? response.stop_reason : nil
      )
    end

    def normalize_tool_calls(tool_calls)
      return [] unless tool_calls

      tool_calls.map do |tc|
        if tc.is_a?(Hash)
          ToolResultMessage.new(
            tool: tc,
            content: tc[:result] || tc["result"]
          )
        else
          tc
        end
      end
    end

    # Resolve MCP hierarchy: runtime -> robot build -> network -> config
    #
    # @param runtime_value [Symbol, Array, nil] Runtime MCP override
    # @param network [NetworkRun, nil] Network context
    # @return [Array] Resolved MCP server configurations
    #
    def resolve_mcp_hierarchy(runtime_value, network:)
      # Get parent value (network or config)
      parent_value = network&.network&.mcp || RobotLab.configuration.mcp

      # Resolve robot build config against parent
      build_resolved = ToolConfig.resolve_mcp(@mcp_config, parent_value: parent_value)

      # Resolve runtime against build
      ToolConfig.resolve_mcp(runtime_value, parent_value: build_resolved)
    end

    # Resolve tools hierarchy: runtime -> robot build -> network -> config
    #
    # @param runtime_value [Symbol, Array, nil] Runtime tools override
    # @param network [NetworkRun, nil] Network context
    # @return [Array<String>] Resolved tool names whitelist
    #
    def resolve_tools_hierarchy(runtime_value, network:)
      # Get parent value (network or config)
      parent_value = network&.network&.tools || RobotLab.configuration.tools

      # Resolve robot build config against parent
      build_resolved = ToolConfig.resolve_tools(@tools_config, parent_value: parent_value)

      # Resolve runtime against build
      ToolConfig.resolve_tools(runtime_value, parent_value: build_resolved)
    end

    # Ensure MCP clients are initialized for the given server configs
    #
    # @param mcp_servers [Array] MCP server configurations
    #
    def ensure_mcp_clients(mcp_servers)
      return if mcp_servers.empty?

      # Get server names from configs
      needed_servers = mcp_servers.map { |s| s.is_a?(Hash) ? s[:name] : s.to_s }.compact

      # Skip if already initialized with same servers
      return if @mcp_initialized && (@mcp_clients.keys.sort == needed_servers.sort)

      # Disconnect existing clients if config changed
      disconnect if @mcp_initialized

      # Initialize new clients
      @mcp_clients = {}
      @mcp_tools = []

      mcp_servers.each do |server_config|
        init_mcp_client(server_config)
      end

      @mcp_initialized = true
    end

    # Initialize a single MCP client
    #
    # @param server_config [Hash] MCP server configuration
    #
    def init_mcp_client(server_config)
      client = MCP::Client.new(server_config)
      client.connect

      if client.connected?
        server_name = client.server.name
        @mcp_clients[server_name] = client
        discover_mcp_tools(client, server_name)
      else
        RobotLab.configuration.logger.warn(
          "Robot '#{@name}' failed to connect to MCP server: #{server_config[:name] || server_config}"
        )
      end
    end

    # Discover tools from an MCP server and add them to @mcp_tools
    #
    # @param client [MCP::Client] Connected MCP client
    # @param server_name [String] Name of the MCP server
    #
    def discover_mcp_tools(client, server_name)
      tools = client.list_tools

      tools.each do |tool_def|
        tool_name = tool_def[:name]
        mcp_client = client

        # Create a Tool that delegates to the MCP client
        tool = Tool.new(
          name: tool_name,
          description: tool_def[:description],
          parameters: tool_def[:inputSchema],
          mcp: server_name,
          handler: ->(input, **_opts) { mcp_client.call_tool(tool_name, input) }
        )

        @mcp_tools << tool
      end

      RobotLab.configuration.logger.info(
        "Robot '#{@name}' discovered #{tools.size} tools from MCP server '#{server_name}'"
      )
    end

    # Get all tools (local + MCP)
    #
    # @return [Array] Combined array of local and MCP tools
    #
    def all_tools
      @local_tools + @mcp_tools
    end

    # Filter tools based on allowed tool names whitelist
    #
    # @param allowed_names [Array<String>] Whitelist of tool names (empty = all allowed)
    # @return [Array] Filtered tools
    #
    def filtered_tools(allowed_names)
      available = all_tools
      return available if allowed_names.empty?

      ToolConfig.filter_tools(available, allowed_names: allowed_names)
    end
  end
end
