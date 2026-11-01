# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    # MCP servers: the robot's registry, per-run server selection, tool
    # collection, and connection failures.
    #
    # Servers are +RubyLLM::MCP+ instances (see RobotLab::MCP). They connect
    # lazily on the first +tools+ request and stay connected across runs
    # until #disconnect. Each run attaches the selected servers' tools to the
    # chat with +with_tools+, so the per-run +tools:+ allowlist, +max_tools+
    # cap and +:none+ apply to MCP tools exactly as to local ones.
    #
    # Owns:    @mcp_registry, @mcp_failures, @mcp_tool_owners, @run_mcp_servers
    # Reads:   @mcp_config, @tools_config, @name, @mcp_discovery, @bus
    # Contract: ivars initialized by initialize_runtime_state
    module MCPManagement
      # The robot's MCP servers, keyed by name. Each entry is a
      # +RubyLLM::MCP+ with the full protocol surface: +tools+, +call+,
      # +resources+, +resource(uri)+, +prompts+, +prompt(name)+,
      # +instructions+, +close+, and the OAuth flow.
      #
      # @return [MCP::Registry]
      #
      # @example
      #   robot.mcp[:github].resources.map(&:uri)
      #   robot.run(robot.mcp[:github].prompt("code_review", code: diff))
      def mcp
        @mcp_registry
      end

      # Register MCP servers on this robot. Accepts config Hashes,
      # +RubyLLM::MCP+ instances and +RubyLLM::MCP+ subclasses, in any mix.
      # Registering a spec already known returns the same server, so hosts
      # may call this on every request. +with_mcp(nil)+ closes and forgets
      # every server.
      #
      # Registered servers are available to runs that select them through
      # the +mcp:+ cascade (+run(..., mcp: :inherit)+ picks up the build-time
      # list; a run-time Array picks exactly those).
      #
      # @param servers [Array<Hash, RubyLLM::MCP, Class<RubyLLM::MCP>>, nil]
      # @return [self]
      def with_mcp(*servers)
        if servers == [nil]
          @mcp_registry.clear
        else
          servers.flatten.compact.each { |spec| @mcp_registry.add(spec) }
        end
        self
      end

      # Eagerly register the build-time MCP servers and connect to each.
      # Connections are otherwise made on the first run that selects a
      # server. Failures are recorded in #mcp_failures, not raised.
      #
      # @return [self]
      def connect_mcp!
        collect_mcp_tools(servers_for(resolve_mcp_hierarchy(@mcp_config)))
        self
      end

      # The MCP tools offered by the given servers (default: every
      # registered server). Connects servers that are not connected yet and
      # skips, with a warning, any that cannot be reached.
      #
      # @param servers [Enumerable<RubyLLM::MCP>]
      # @return [Array<RubyLLM::MCP::Tool>]
      def mcp_tools(servers = @mcp_registry)
        collect_mcp_tools(servers.to_a)
      end

      # Names of servers whose last connection attempt failed. A server is
      # retried on the next run that selects it and leaves this list once it
      # answers.
      #
      # @return [Array<String>]
      def failed_mcp_server_names
        @mcp_failures.keys
      end

      # The last connection error per failed server name.
      #
      # @return [Hash{String => Exception}]
      def mcp_failures
        @mcp_failures.dup
      end

      # The server that owns +tool+, or nil for a local tool.
      #
      # @param tool [RubyLLM::Tool]
      # @return [RubyLLM::MCP, nil]
      def mcp_server_for(tool)
        @mcp_tool_owners[tool]
      end

      # Close every MCP server (stopping stdio processes) and the bus channel.
      # Servers stay registered and reconnect on their next use.
      #
      # @return [self]
      def disconnect
        @mcp_registry.each(&:close)
        teardown_bus_channel if @bus
        self
      end

      private

      # Resolve MCP hierarchy: runtime -> robot build -> network -> config
      # :reek:ControlParameter -- `network_config&.mcp || ...` is the documented fallback cascade, not a mode switch.
      def resolve_mcp_hierarchy(runtime_value, network: nil, network_config: nil)
        parent_value = network_config&.mcp || network_parent_config(network)&.mcp || RobotLab.config.mcp
        build_resolved = ToolConfig.resolve_mcp(@mcp_config, parent_value: parent_value)
        ToolConfig.resolve_mcp(runtime_value, parent_value: build_resolved)
      end

      # Resolve tools hierarchy: runtime -> robot build -> network -> config
      # :reek:ControlParameter -- `network_config&.tools || ...` is the documented fallback cascade, not a mode switch.
      def resolve_tools_hierarchy(runtime_value, network: nil, network_config: nil)
        parent_value = network_config&.tools || network_parent_config(network)&.tools || RobotLab.config.tools
        build_resolved = ToolConfig.resolve_tools(@tools_config, parent_value: parent_value)
        ToolConfig.resolve_tools(runtime_value, parent_value: build_resolved)
      end

      def network_parent_config(network)
        return network.config if network.respond_to?(:config)

        network&.network
      end

      # The registered server instances a run's resolved +mcp+ value names.
      # Specs not registered yet are registered here. With +mcp_discovery+,
      # the candidates are narrowed to those relevant to +message+ first.
      #
      # @param resolved [Array<Hash, RubyLLM::MCP, Class>] output of resolve_mcp_hierarchy
      # @param message [String, RubyLLM::MCP::Prompt, nil] this run's request
      # @return [Array<RubyLLM::MCP>]
      def servers_for(resolved, message: nil)
        specs = Array(resolved)
        specs = MCP::ServerDiscovery.select(discovery_query(message), from: specs) if @mcp_discovery && message
        specs.map { |spec| @mcp_registry.add(spec) }
      end

      # The text ServerDiscovery scores servers against.
      def discovery_query(message)
        return message.to_s unless message.is_a?(RubyLLM::MCP::Prompt)

        message.messages.map { |prompt_message| prompt_message.content.to_s }.join(' ')
      end

      # The tools of +servers+, connecting each as needed. A server that
      # cannot be reached is recorded in @mcp_failures, warned about, and
      # contributes no tools; the run goes on with the rest.
      #
      # @param servers [Array<RubyLLM::MCP>]
      # @return [Array<RubyLLM::MCP::Tool>]
      def collect_mcp_tools(servers)
        servers.flat_map { |server| tools_from(server) }
      end

      # One server's tools, or [] (recorded and warned) when it cannot be reached.
      def tools_from(server)
        tools = server.tools
        @mcp_failures.delete(server.name)
        tools.each { |tool| @mcp_tool_owners[tool] = server }
        tools
      rescue *MCP::CONNECT_ERRORS => e
        record_mcp_failure(server, e)
        []
      end

      def record_mcp_failure(server, error)
        @mcp_failures[server.name] = error
        RobotLab.config.logger.warn(
          "Robot '#{@name}' could not reach MCP server '#{server.name}': #{error.class}: #{error.message}"
        )
      end

      # Whether +tool+ is an MCP tool its server declared deferred (offered to
      # the provider's tool search instead of the model's context).
      def deferred_mcp_tool?(tool)
        server = mcp_server_for(tool)
        return false unless server

        server.defers?(tool)
      end

      # Whether the chat currently holds MCP tools from an earlier run.
      def mcp_tools_attached?
        @chat.tools.each_value.any?(RubyLLM::MCP::Tool)
      end

      # Two tools with one name cannot both be offered; ruby_llm raises when
      # it builds the tool list, so catch it here with the fix spelled out.
      #
      # @param tools [Array<RubyLLM::Tool>]
      # @raise [MCPError]
      def check_unique_tool_names!(tools)
        duplicates = tools.group_by { |tool| tool.name.to_s }.select { |_, same| same.size > 1 }.keys
        return if duplicates.empty?

        raise MCPError, "Robot '#{@name}' has more than one tool named #{duplicates.join(', ')}. " \
                        'Give one of the MCP servers a prefix:, or rename the local tool.'
      end
    end
  end
end
