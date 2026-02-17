# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    # MCP client lifecycle and hierarchical tool/MCP resolution.
    #
    # Expects the including class to provide:
    #   @mcp_config, @tools_config, @mcp_clients, @mcp_tools,
    #   @mcp_initialized, @name, @chat, @local_tools
    module MCPManagement
      private

      # Resolve MCP hierarchy: runtime -> robot build -> network -> config
      def resolve_mcp_hierarchy(runtime_value, network: nil, network_config: nil)
        parent_value = network_config&.mcp || network&.network&.mcp || RobotLab.config.mcp
        build_resolved = ToolConfig.resolve_mcp(@mcp_config, parent_value: parent_value)
        ToolConfig.resolve_mcp(runtime_value, parent_value: build_resolved)
      end


      # Resolve tools hierarchy: runtime -> robot build -> network -> config
      def resolve_tools_hierarchy(runtime_value, network: nil, network_config: nil)
        parent_value = network_config&.tools || network&.network&.tools || RobotLab.config.tools
        build_resolved = ToolConfig.resolve_tools(@tools_config, parent_value: parent_value)
        ToolConfig.resolve_tools(runtime_value, parent_value: build_resolved)
      end


      # Ensure MCP clients are initialized for the given server configs
      def ensure_mcp_clients(mcp_servers)
        return if mcp_servers.empty?

        needed_servers = mcp_servers.map { |s| s.is_a?(Hash) ? s[:name] : s.to_s }.compact
        return if @mcp_initialized && (@mcp_clients.keys.sort == needed_servers.sort)

        disconnect if @mcp_initialized

        @mcp_clients = {}
        @mcp_tools = []

        mcp_servers.each do |server_config|
          init_mcp_client(server_config)
        end

        @mcp_initialized = true
      end


      def init_mcp_client(server_config)
        client = MCP::Client.new(server_config)
        client.connect

        if client.connected?
          server_name = client.server.name
          @mcp_clients[server_name] = client
          discover_mcp_tools(client, server_name)
        else
          RobotLab.config.logger.warn(
            "Robot '#{@name}' failed to connect to MCP server: #{server_config[:name] || server_config}"
          )
        end
      end


      def discover_mcp_tools(client, server_name)
        tools = client.list_tools

        tools.each do |tool_def|
          tool_name = tool_def[:name]
          mcp_client = client

          tool = Tool.create(
            name: tool_name,
            description: tool_def[:description],
            parameters: tool_def[:inputSchema],
            mcp: server_name
          ) { |args| mcp_client.call_tool(tool_name, args) }

          @mcp_tools << tool
        end

        RobotLab.config.logger.info(
          "Robot '#{@name}' discovered #{tools.size} tools from MCP server '#{server_name}'"
        )
      end
    end
  end
end
