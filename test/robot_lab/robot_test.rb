# frozen_string_literal: true

require "test_helper"

class RobotLab::RobotTest < Minitest::Test
  # Initialization tests
  def test_initialization_with_required_params
    robot = RobotLab::Robot.new(
      name: "test_robot",
      template: :assistant
    )

    assert_equal "test_robot", robot.name
    assert_equal :assistant, robot.template
  end

  def test_initialization_converts_name_to_string
    robot = RobotLab::Robot.new(
      name: :my_robot,
      template: :assistant
    )

    assert_equal "my_robot", robot.name
  end

  def test_initialization_with_description
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      description: "A helpful assistant"
    )

    assert_equal "A helpful assistant", robot.description
  end

  def test_initialization_with_context
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      context: { company: "Acme" }
    )

    build_context = robot.instance_variable_get(:@build_context)
    assert_equal "Acme", build_context[:company]
  end

  def test_initialization_with_local_tools
    tool = build_tool(name: "calculator") { |input| input[:a] + input[:b] }

    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      local_tools: [tool]
    )

    assert_equal 1, robot.local_tools.size
    assert_equal tool, robot.local_tools.first
  end

  def test_initialization_wraps_single_tool_in_array
    tool = build_tool(name: "calculator") { |input| input }

    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      local_tools: tool
    )

    assert robot.local_tools.is_a?(Array)
    assert_equal 1, robot.local_tools.size
  end

  def test_initialization_with_custom_model
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      model: "gpt-4"
    )

    assert_equal "gpt-4", robot.model
  end

  def test_initialization_uses_default_model
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant
    )

    assert_equal RobotLab.config.ruby_llm.model, robot.model
  end

  # system_prompt tests
  def test_initialization_with_system_prompt_only
    robot = RobotLab::Robot.new(
      name: "quick_bot",
      system_prompt: "You are a helpful assistant."
    )

    assert_equal "quick_bot", robot.name
    assert_nil robot.template
    assert_equal "You are a helpful assistant.", robot.system_prompt
  end

  def test_initialization_with_template_and_system_prompt
    robot = RobotLab::Robot.new(
      name: "enhanced_bot",
      template: :assistant,
      system_prompt: "Additional context for today."
    )

    assert_equal :assistant, robot.template
    assert_equal "Additional context for today.", robot.system_prompt
  end

  def test_initialization_raises_without_template_or_system_prompt
    error = assert_raises(ArgumentError) do
      RobotLab::Robot.new(name: "incomplete_bot")
    end

    assert_equal "Must provide either template or system_prompt", error.message
  end

  def test_to_h_includes_system_prompt
    robot = RobotLab::Robot.new(
      name: "helper",
      system_prompt: "You are helpful."
    )

    hash = robot.to_h
    assert_equal "You are helpful.", hash[:system_prompt]
  end

  def test_to_h_excludes_nil_system_prompt
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant
    )

    hash = robot.to_h
    refute hash.key?(:system_prompt)
  end

  def test_initialization_with_mcp_inherit
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      mcp: :inherit
    )

    assert_equal :inherit, robot.mcp_config
  end

  def test_initialization_with_mcp_none
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      mcp: :none
    )

    assert_equal :none, robot.mcp_config
  end

  def test_initialization_with_mcp_servers_legacy
    servers = [{ name: "server1", command: "npx server1" }]

    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      mcp_servers: servers
    )

    # mcp_servers takes precedence over mcp
    assert_equal servers, robot.mcp_config
  end

  def test_initialization_with_tools_config
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      tools: %w[search refund]
    )

    assert_equal %w[search refund], robot.tools_config
  end

  def test_initialization_with_on_tool_call_callback
    callback = ->(call) { call }

    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      on_tool_call: callback
    )

    assert_equal callback, robot.instance_variable_get(:@on_tool_call)
  end

  def test_initialization_with_on_tool_result_callback
    callback = ->(result) { result }

    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      on_tool_result: callback
    )

    assert_equal callback, robot.instance_variable_get(:@on_tool_result)
  end

  # Tools accessor
  def test_tools_alias_returns_local_tools
    tool = build_tool(name: "calc") { |i| i }

    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      local_tools: [tool]
    )

    assert_equal robot.local_tools, robot.tools
  end

  # MCP state
  def test_mcp_clients_initially_empty
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant
    )

    assert_equal({}, robot.mcp_clients)
    assert_equal [], robot.mcp_tools
  end

  # Disconnect
  def test_disconnect_returns_self
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant
    )

    assert_equal robot, robot.disconnect
  end

  # Serialization
  def test_to_h_exports_robot_config
    tool = build_tool(name: "search") { |i| i }

    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      description: "A helper robot",
      local_tools: [tool],
      mcp: :none,
      tools: %w[search]
    )

    hash = robot.to_h

    assert_equal "helper", hash[:name]
    assert_equal "A helper robot", hash[:description]
    assert_equal :assistant, hash[:template]
    assert_equal %w[search], hash[:local_tools]
    assert_equal :none, hash[:mcp_config]
    assert_equal %w[search], hash[:tools_config]
  end

  def test_to_h_with_string_model
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      model: "claude-3-opus"
    )

    hash = robot.to_h
    assert_equal "claude-3-opus", hash[:model]
  end

  def test_to_h_excludes_nil_values
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant
    )

    hash = robot.to_h

    refute hash.key?(:description)
  end

  def test_to_h_includes_mcp_servers
    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant
    )

    hash = robot.to_h

    # mcp_servers should be empty array when no MCP clients connected
    assert_equal [], hash[:mcp_servers]
  end

  # Context resolution
  def test_context_can_be_proc
    dynamic_context = ->(**_args) {
      { timestamp: Time.now }
    }

    robot = RobotLab::Robot.new(
      name: "helper",
      template: :assistant,
      context: dynamic_context
    )

    build_context = robot.instance_variable_get(:@build_context)
    assert build_context.is_a?(Proc)
  end

  # Template validation
  def test_different_templates
    %i[assistant helper classifier billing technical].each do |template|
      robot = RobotLab::Robot.new(
        name: "test_#{template}",
        template: template
      )

      assert_equal template, robot.template
    end
  end

  # Multiple tools
  def test_initialization_with_multiple_tools
    tool1 = build_tool(name: "search") { |i| "found: #{i}" }
    tool2 = build_tool(name: "calculate") { |i| i[:a] + i[:b] }
    tool3 = build_tool(name: "format") { |i| i.to_s }

    robot = RobotLab::Robot.new(
      name: "multi_tool_robot",
      template: :assistant,
      local_tools: [tool1, tool2, tool3]
    )

    assert_equal 3, robot.local_tools.size
    assert_equal %w[search calculate format], robot.local_tools.map(&:name)
  end

  # Private method: resolve_context
  def test_resolve_context_with_hash
    robot = RobotLab::Robot.new(name: "test", template: :assistant)
    result = robot.send(:resolve_context, { key: "value" }, network: nil)

    assert_equal({ key: "value" }, result)
  end

  def test_resolve_context_with_proc
    robot = RobotLab::Robot.new(name: "test", template: :assistant)
    context_proc = ->(network:) { { computed: "data", has_network: !network.nil? } }
    result = robot.send(:resolve_context, context_proc, network: nil)

    assert_equal({ computed: "data", has_network: false }, result)
  end

  def test_resolve_context_with_nil
    robot = RobotLab::Robot.new(name: "test", template: :assistant)
    result = robot.send(:resolve_context, nil, network: nil)

    assert_equal({}, result)
  end

  def test_resolve_context_with_invalid_type
    robot = RobotLab::Robot.new(name: "test", template: :assistant)
    result = robot.send(:resolve_context, "invalid", network: nil)

    assert_equal({}, result)
  end

  # Private method: normalize_tool_calls
  def test_normalize_tool_calls_with_nil
    robot = RobotLab::Robot.new(name: "test", template: :assistant)
    result = robot.send(:normalize_tool_calls, nil)

    assert_equal [], result
  end

  def test_normalize_tool_calls_with_empty_array
    robot = RobotLab::Robot.new(name: "test", template: :assistant)
    result = robot.send(:normalize_tool_calls, [])

    assert_equal [], result
  end

  def test_normalize_tool_calls_with_hash
    robot = RobotLab::Robot.new(name: "test", template: :assistant)
    tool_calls = [{ name: "search", result: "found" }]
    result = robot.send(:normalize_tool_calls, tool_calls)

    assert_equal 1, result.size
    assert result.first.is_a?(RobotLab::ToolResultMessage)
  end

  def test_normalize_tool_calls_preserves_non_hash_items
    robot = RobotLab::Robot.new(name: "test", template: :assistant)
    existing_message = RobotLab::ToolResultMessage.new(
      tool: { name: "test" },
      content: "result"
    )
    result = robot.send(:normalize_tool_calls, [existing_message])

    assert_equal [existing_message], result
  end

  # Private method: all_tools
  def test_all_tools_combines_local_and_mcp_tools
    tool = build_tool(name: "local") { |i| i }
    robot = RobotLab::Robot.new(
      name: "test",
      template: :assistant,
      local_tools: [tool]
    )

    # Simulate adding an MCP tool
    mcp_tool = build_tool(name: "mcp_tool") { |i| i }
    robot.instance_variable_get(:@mcp_tools) << mcp_tool

    all = robot.send(:all_tools)
    assert_equal 2, all.size
    assert_includes all.map(&:name), "local"
    assert_includes all.map(&:name), "mcp_tool"
  end

  # Private method: filtered_tools
  def test_filtered_tools_returns_all_when_empty_whitelist
    tool1 = build_tool(name: "tool1") { |i| i }
    tool2 = build_tool(name: "tool2") { |i| i }
    robot = RobotLab::Robot.new(
      name: "test",
      template: :assistant,
      local_tools: [tool1, tool2]
    )

    result = robot.send(:filtered_tools, [])
    assert_equal 2, result.size
  end

  def test_filtered_tools_filters_by_name
    tool1 = build_tool(name: "search") { |i| i }
    tool2 = build_tool(name: "delete") { |i| i }
    robot = RobotLab::Robot.new(
      name: "test",
      template: :assistant,
      local_tools: [tool1, tool2]
    )

    result = robot.send(:filtered_tools, ["search"])
    assert_equal 1, result.size
    assert_equal "search", result.first.name
  end

  # Private method: ensure_mcp_clients
  def test_ensure_mcp_clients_with_empty_servers
    robot = RobotLab::Robot.new(name: "test", template: :assistant)
    robot.send(:ensure_mcp_clients, [])

    # Should not modify mcp state
    refute robot.instance_variable_get(:@mcp_initialized)
  end

  # MCP hierarchy resolution
  def test_resolve_mcp_hierarchy_with_none
    robot = RobotLab::Robot.new(name: "test", template: :assistant, mcp: :none)
    result = robot.send(:resolve_mcp_hierarchy, :none, network: nil)

    assert_equal [], result
  end

  def test_resolve_tools_hierarchy_with_none
    robot = RobotLab::Robot.new(name: "test", template: :assistant, tools: :none)
    result = robot.send(:resolve_tools_hierarchy, :none, network: nil)

    assert_equal [], result
  end
end
