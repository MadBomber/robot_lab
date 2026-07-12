# frozen_string_literal: true

require 'test_helper'

class RobotLab::RobotTest < Minitest::Test
  # Initialization tests
  def test_initialization_with_required_params
    robot = RobotLab::Robot.new(
      name: 'test_robot',
      template: :assistant
    )

    assert_equal 'test_robot', robot.name
    assert_equal :assistant, robot.template
  end

  def test_initialization_converts_name_to_string
    robot = RobotLab::Robot.new(
      name: :my_robot,
      template: :assistant
    )

    assert_equal 'my_robot', robot.name
  end

  def test_initialization_with_description
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      description: 'A helpful assistant'
    )

    assert_equal 'A helpful assistant', robot.description
  end

  def test_initialization_with_context
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      context: { company: 'Acme' }
    )

    build_context = robot.instance_variable_get(:@build_context)
    assert_equal 'Acme', build_context[:company]
  end

  def test_initialization_with_local_tools
    tool = build_tool(name: 'calculator') { |input| input[:a] + input[:b] }

    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      local_tools: [tool]
    )

    assert_equal 1, robot.local_tools.size
    assert_equal tool, robot.local_tools.first
  end

  def test_initialization_wraps_single_tool_in_array
    tool = build_tool(name: 'calculator') { |input| input }

    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      local_tools: tool
    )

    assert robot.local_tools.is_a?(Array)
    assert_equal 1, robot.local_tools.size
  end

  def test_initialization_with_custom_model
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      model: 'claude-sonnet-4'
    )

    assert_includes robot.model, 'claude-sonnet-4'
  end

  def test_initialization_uses_default_model
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant
    )

    assert_includes robot.model, 'claude-sonnet-4'
  end

  # system_prompt tests
  def test_initialization_with_system_prompt_only
    robot = RobotLab::Robot.new(
      name: 'quick_bot',
      system_prompt: 'You are a helpful assistant.'
    )

    assert_equal 'quick_bot', robot.name
    assert_nil robot.template
    assert_equal 'You are a helpful assistant.', robot.system_prompt
  end

  def test_initialization_with_template_and_system_prompt
    robot = RobotLab::Robot.new(
      name: 'enhanced_bot',
      template: :assistant,
      system_prompt: 'Additional context for today.'
    )

    assert_equal :assistant, robot.template
    assert_equal 'Additional context for today.', robot.system_prompt
  end

  def test_initialization_allows_bare_robot
    robot = RobotLab::Robot.new(name: 'bare_bot')

    assert_equal 'bare_bot', robot.name
    assert_nil robot.template
    assert_nil robot.system_prompt
  end

  def test_to_h_includes_system_prompt
    robot = RobotLab::Robot.new(
      name: 'helper',
      system_prompt: 'You are helpful.'
    )

    hash = robot.to_h
    assert_equal 'You are helpful.', hash[:system_prompt]
  end

  def test_to_h_excludes_nil_system_prompt
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant
    )

    hash = robot.to_h
    refute hash.key?(:system_prompt)
  end

  def test_initialization_with_mcp_inherit
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      mcp: :inherit
    )

    assert_equal :inherit, robot.mcp_config
  end

  def test_initialization_with_mcp_none
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      mcp: :none
    )

    assert_equal :none, robot.mcp_config
  end

  def test_initialization_with_mcp_servers_legacy
    servers = [{ name: 'server1', command: 'npx server1' }]

    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      mcp_servers: servers
    )

    # mcp_servers takes precedence over mcp
    assert_equal servers, robot.mcp_config
  end

  def test_initialization_with_tools_config
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      tools: %w[search refund]
    )

    assert_equal %w[search refund], robot.tools_config
  end

  def test_initialization_with_on_tool_call_callback
    callback = ->(call) { call }

    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      on_tool_call: callback
    )

    assert_equal callback, robot.instance_variable_get(:@on_tool_call)
  end

  def test_initialization_with_on_tool_result_callback
    callback = ->(result) { result }

    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      on_tool_result: callback
    )

    assert_equal callback, robot.instance_variable_get(:@on_tool_result)
  end

  # Agent inheritance
  def test_robot_inherits_from_agent
    assert RobotLab::Robot < RubyLLM::Agent
  end

  # MCP state
  def test_mcp_clients_initially_empty
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant
    )

    assert_equal({}, robot.mcp_clients)
    assert_equal [], robot.mcp_tools
  end

  # Disconnect
  def test_disconnect_returns_self
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant
    )

    assert_equal robot, robot.disconnect
  end

  # Serialization
  def test_to_h_exports_robot_config
    tool = build_tool(name: 'search') { |i| i }

    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant,
      description: 'A helper robot',
      local_tools: [tool],
      mcp: :none,
      tools: %w[search]
    )

    hash = robot.to_h

    assert_equal 'helper', hash[:name]
    assert_equal 'A helper robot', hash[:description]
    assert_equal :assistant, hash[:template]
    assert_equal %w[search], hash[:local_tools]
    assert_equal :none, hash[:mcp_config]
    assert_equal %w[search], hash[:tools_config]
  end

  def test_to_h_includes_model
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant
    )

    hash = robot.to_h
    assert_includes hash[:model], 'claude-sonnet-4'
  end

  def test_to_h_excludes_nil_values
    robot = RobotLab::Robot.new(
      name: 'helper'
    )

    hash = robot.to_h

    refute hash.key?(:description)
  end

  def test_to_h_includes_mcp_servers
    robot = RobotLab::Robot.new(
      name: 'helper',
      template: :assistant
    )

    hash = robot.to_h

    # mcp_servers should be empty array when no MCP clients connected
    assert_equal [], hash[:mcp_servers]
  end

  # Context resolution
  def test_context_can_be_proc
    dynamic_context = lambda { |**_args|
      { timestamp: Time.now }
    }

    robot = RobotLab::Robot.new(
      name: 'helper',
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
    tool1 = build_tool(name: 'search') { |i| "found: #{i}" }
    tool2 = build_tool(name: 'calculate') { |i| i[:a] + i[:b] }
    tool3 = build_tool(name: 'format', &:to_s)

    robot = RobotLab::Robot.new(
      name: 'multi_tool_robot',
      template: :assistant,
      local_tools: [tool1, tool2, tool3]
    )

    assert_equal 3, robot.local_tools.size
    assert_equal %w[search calculate format], robot.local_tools.map(&:name)
  end

  # Private method: resolve_context
  def test_resolve_context_with_hash
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    result = robot.send(:resolve_context, { key: 'value' }, network: nil)

    assert_equal({ key: 'value' }, result)
  end

  def test_resolve_context_with_proc
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    context_proc = ->(network:) { { computed: 'data', has_network: !network.nil? } }
    result = robot.send(:resolve_context, context_proc, network: nil)

    assert_equal({ computed: 'data', has_network: false }, result)
  end

  def test_resolve_context_with_nil
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    result = robot.send(:resolve_context, nil, network: nil)

    assert_equal({}, result)
  end

  def test_resolve_context_with_invalid_type
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    result = robot.send(:resolve_context, 'invalid', network: nil)

    assert_equal({}, result)
  end

  # Bus integration tests

  def test_initialization_without_bus
    robot = RobotLab::Robot.new(name: 'no_bus', template: :assistant)

    assert_nil robot.bus
    assert_equal({}, robot.outbox)
  end

  def test_initialization_with_bus
    bus = TypedBus::MessageBus.new
    robot = RobotLab::Robot.new(name: 'bus_bot', template: :assistant, bus: bus)

    assert_equal bus, robot.bus
    assert bus.channel?(:bus_bot)
  end

  def test_bus_channel_is_typed
    bus = TypedBus::MessageBus.new
    RobotLab::Robot.new(name: 'typed_bot', template: :assistant, bus: bus)

    error = nil
    Async do
      bus.publish(:typed_bot, "not a RobotMessage")
    rescue ArgumentError => e
      error = e
    end

    assert_kind_of ArgumentError, error
    assert_match(/Expected RobotLab::RobotMessage/, error.message)
  end

  def test_send_message_increments_counter
    bus = TypedBus::MessageBus.new
    alice = RobotLab::Robot.new(name: 'alice', template: :assistant, bus: bus)
    bob = RobotLab::Robot.new(name: 'bob', template: :assistant, bus: bus)
    bob.on_message { |msg| }

    msg1 = alice.send_message(to: :bob, content: "first")
    msg2 = alice.send_message(to: :bob, content: "second")

    assert_equal 1, msg1.id
    assert_equal 2, msg2.id
  end

  def test_send_message_tracks_in_outbox
    bus = TypedBus::MessageBus.new
    alice = RobotLab::Robot.new(name: 'alice', template: :assistant, bus: bus)
    bob = RobotLab::Robot.new(name: 'bob', template: :assistant, bus: bus)
    bob.on_message { |msg| }

    msg = alice.send_message(to: :bob, content: "task")

    assert alice.outbox.key?(msg.key)
    assert_equal :sent, alice.outbox[msg.key][:status]
    assert_equal msg, alice.outbox[msg.key][:message]
    assert_equal [], alice.outbox[msg.key][:replies]
  end

  def test_send_message_without_bus_raises
    robot = RobotLab::Robot.new(name: 'no_bus', template: :assistant)

    assert_raises(RobotLab::BusError) do
      robot.send_message(to: :someone, content: "hello")
    end
  end

  def test_send_reply_without_bus_raises
    robot = RobotLab::Robot.new(name: 'no_bus', template: :assistant)

    assert_raises(RobotLab::BusError) do
      robot.send_reply(to: :someone, content: "reply", in_reply_to: "someone:1")
    end
  end

  def test_on_message_sets_custom_handler
    bus = TypedBus::MessageBus.new
    received = []
    bob = RobotLab::Robot.new(name: 'bob', template: :assistant, bus: bus)
    bob.on_message do |delivery, message|
      received << message
      delivery.ack!
    end

    alice = RobotLab::Robot.new(name: 'alice', template: :assistant, bus: bus)
    Async { alice.send_message(to: :bob, content: "hello from alice") }

    assert_equal 1, received.size
    assert_equal "hello from alice", received.first.content
    assert_equal "alice", received.first.from
  end

  def test_disconnect_with_bus
    bus = TypedBus::MessageBus.new
    robot = RobotLab::Robot.new(name: 'disc_bot', template: :assistant, bus: bus)

    result = robot.disconnect

    assert_equal robot, result
  end

  def test_to_h_includes_bus_flag
    bus = TypedBus::MessageBus.new
    robot = RobotLab::Robot.new(name: 'bus_bot', template: :assistant, bus: bus)

    hash = robot.to_h
    assert_equal true, hash[:bus]
  end

  def test_to_h_excludes_bus_when_nil
    robot = RobotLab::Robot.new(name: 'no_bus', template: :assistant)

    hash = robot.to_h
    refute hash.key?(:bus)
  end

  def test_on_message_auto_acks_with_single_arg_block
    bus = TypedBus::MessageBus.new
    received = []
    bob = RobotLab::Robot.new(name: 'bob', template: :assistant, bus: bus)
    bob.on_message do |message|
      received << message
    end

    alice = RobotLab::Robot.new(name: 'alice', template: :assistant, bus: bus)
    Async { alice.send_message(to: :bob, content: "auto-ack test") }

    assert_equal 1, received.size
    assert_equal "auto-ack test", received.first.content
  end

  def test_reply_convenience_method
    bus = TypedBus::MessageBus.new
    replies = []
    alice = RobotLab::Robot.new(name: 'alice', template: :assistant, bus: bus)
    alice.on_message do |message|
      replies << message
    end

    bob = RobotLab::Robot.new(name: 'bob', template: :assistant, bus: bus)
    bob.on_message do |message|
      bob.send_reply(to: message.from.to_sym, content: "got it", in_reply_to: message.key)
    end

    Async { alice.send_message(to: :bob, content: "hello") }

    assert_equal 1, replies.size
    assert_equal "got it", replies.first.content
    assert replies.first.reply?
  end

  def test_build_factory_with_bus
    bus = TypedBus::MessageBus.new
    robot = RobotLab.build(name: 'factory_bot', bus: bus)

    assert_equal bus, robot.bus
    assert bus.channel?(:factory_bot)
  end

  # Private method: normalize_tool_calls
  def test_normalize_tool_calls_with_nil
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    result = robot.send(:normalize_tool_calls, nil)

    assert_equal [], result
  end

  def test_normalize_tool_calls_with_empty_array
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    result = robot.send(:normalize_tool_calls, [])

    assert_equal [], result
  end

  def test_normalize_tool_calls_with_hash
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    tool_calls = [{ name: 'search', result: 'found' }]
    result = robot.send(:normalize_tool_calls, tool_calls)

    assert_equal 1, result.size
    assert result.first.is_a?(RobotLab::ToolResultMessage)
  end

  def test_normalize_tool_calls_preserves_non_hash_items
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    existing_message = RobotLab::ToolResultMessage.new(
      tool: { name: 'test' },
      content: 'result'
    )
    result = robot.send(:normalize_tool_calls, [existing_message])

    assert_equal [existing_message], result
  end

  # Private method: all_tools
  def test_all_tools_combines_local_and_mcp_tools
    tool = build_tool(name: 'local') { |i| i }
    robot = RobotLab::Robot.new(
      name: 'test',
      template: :assistant,
      local_tools: [tool]
    )

    # Simulate adding an MCP tool
    mcp_tool = build_tool(name: 'mcp_tool') { |i| i }
    robot.instance_variable_get(:@mcp_tools) << mcp_tool

    all = robot.send(:all_tools)
    assert_equal 2, all.size
    assert_includes all.map(&:name), 'local'
    assert_includes all.map(&:name), 'mcp_tool'
  end

  # Private method: filtered_tools
  def test_filtered_tools_returns_all_when_empty_whitelist
    tool1 = build_tool(name: 'tool1') { |i| i }
    tool2 = build_tool(name: 'tool2') { |i| i }
    robot = RobotLab::Robot.new(
      name: 'test',
      template: :assistant,
      local_tools: [tool1, tool2]
    )

    result = robot.send(:filtered_tools, [])
    assert_equal 2, result.size
  end

  def test_filtered_tools_filters_by_name
    tool1 = build_tool(name: 'search') { |i| i }
    tool2 = build_tool(name: 'delete') { |i| i }
    robot = RobotLab::Robot.new(
      name: 'test',
      template: :assistant,
      local_tools: [tool1, tool2]
    )

    result = robot.send(:filtered_tools, ['search'])
    assert_equal 1, result.size
    assert_equal 'search', result.first.name
  end

  # Private method: explicit_none_tools?
  def test_explicit_none_tools_detects_none_and_empty_array
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)

    assert robot.send(:explicit_none_tools?, :none)
    assert robot.send(:explicit_none_tools?, [])
    refute robot.send(:explicit_none_tools?, :inherit)
    refute robot.send(:explicit_none_tools?, nil)
    refute robot.send(:explicit_none_tools?, %w[search])
  end

  # Private method: prepare_tools — an explicit :none sends ZERO tools, even
  # though :none resolves to an empty allowlist (which filtered_tools treats as
  # "all"). This is what lets a relevance filter suppress the whole tool set.
  def test_prepare_tools_with_explicit_none_clears_the_chat_tools
    tool  = build_tool(name: 'search') { |i| i }
    robot = RobotLab::Robot.new(name: 'test', template: :assistant, local_tools: [tool])

    robot.send(:prepare_tools, message: 'hi', mcp: :none, tools: :none, network: nil, network_config: nil)

    assert_empty robot.chat.tools, 'an explicit :none must send zero tools'
  end

  def test_prepare_tools_with_inherit_uses_all_attached_tools
    tool  = build_tool(name: 'search') { |i| i }
    robot = RobotLab::Robot.new(name: 'test', template: :assistant, local_tools: [tool])

    robot.send(:prepare_tools, message: 'hi', mcp: :none, tools: :inherit, network: nil, network_config: nil)

    assert_equal %i[search], robot.chat.tools.keys
  end

  def test_prepare_tools_none_clears_tools_set_by_a_prior_turn
    tool  = build_tool(name: 'search') { |i| i }
    robot = RobotLab::Robot.new(name: 'test', template: :assistant, local_tools: [tool])

    robot.send(:prepare_tools, message: 'use search', mcp: :none, tools: :inherit, network: nil, network_config: nil)
    refute_empty robot.chat.tools

    robot.send(:prepare_tools, message: 'hi', mcp: :none, tools: :none, network: nil, network_config: nil)
    assert_empty robot.chat.tools, 'a later :none turn must clear tools a prior turn attached'
  end

  # Private method: cap_tools
  def test_cap_tools_returns_all_when_under_max
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    tools = Array.new(5) { |i| build_tool(name: "t#{i}") { |x| x } }
    assert_equal 5, robot.send(:cap_tools, tools).size
  end

  def test_cap_tools_trims_to_default_max
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    tools = Array.new(RobotLab::Robot::DEFAULT_MAX_TOOLS + 10) { |i| build_tool(name: "t#{i}") { |x| x } }
    result = robot.send(:cap_tools, tools)
    assert_equal RobotLab::Robot::DEFAULT_MAX_TOOLS, result.size
    assert_equal tools.first(RobotLab::Robot::DEFAULT_MAX_TOOLS), result
  end

  def test_cap_tools_respects_config_max_tools
    robot = RobotLab::Robot.new(
      name: 'test', template: :assistant,
      config: RobotLab::RunConfig.new(max_tools: 2)
    )
    tools = Array.new(5) { |i| build_tool(name: "t#{i}") { |x| x } }
    assert_equal 2, robot.send(:cap_tools, tools).size
  end

  def test_effective_max_tools_defaults_when_unset
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    assert_equal RobotLab::Robot::DEFAULT_MAX_TOOLS, robot.send(:effective_max_tools)
  end

  # Private method: ensure_mcp_clients
  def test_ensure_mcp_clients_with_empty_servers
    robot = RobotLab::Robot.new(name: 'test', template: :assistant)
    robot.send(:ensure_mcp_clients, [])

    # Should not modify mcp state
    refute robot.instance_variable_get(:@mcp_initialized)
  end

  # MCP hierarchy resolution
  def test_resolve_mcp_hierarchy_with_none
    robot = RobotLab::Robot.new(name: 'test', template: :assistant, mcp: :none)
    result = robot.send(:resolve_mcp_hierarchy, :none, network: nil)

    assert_equal [], result
  end

  def test_resolve_tools_hierarchy_with_none
    robot = RobotLab::Robot.new(name: 'test', template: :assistant, tools: :none)
    result = robot.send(:resolve_tools_hierarchy, :none, network: nil)

    assert_equal [], result
  end

  # Spawn tests
  # with_bus tests
  def test_with_bus_with_existing_bus
    bot = RobotLab::Robot.new(name: 'lonely', template: :assistant)
    bus = TypedBus::MessageBus.new

    assert_nil bot.bus

    bot.with_bus(bus)

    assert_equal bus, bot.bus
    assert bus.channel?(:lonely)
  end

  def test_with_bus_creates_new_bus
    bot = RobotLab::Robot.new(name: 'lonely', template: :assistant)

    bot.with_bus

    assert_instance_of TypedBus::MessageBus, bot.bus
    assert bot.bus.channel?(:lonely)
  end

  def test_with_bus_noop_when_already_on_same_bus
    bus = TypedBus::MessageBus.new
    bot = RobotLab::Robot.new(name: 'bot', template: :assistant, bus: bus)

    result = bot.with_bus(bus)

    assert_equal bot, result
    assert_equal bus, bot.bus
  end

  def test_with_bus_allows_switching_buses
    bus1 = TypedBus::MessageBus.new
    bus2 = TypedBus::MessageBus.new
    bot = RobotLab::Robot.new(name: 'bot', template: :assistant, bus: bus1)

    bot.with_bus(bus2)

    assert_equal bus2, bot.bus
    assert bus2.channel?(:bot)
  end

  def test_with_bus_enables_messaging
    bot1 = RobotLab::Robot.new(name: 'alice', template: :assistant)
    bot2 = RobotLab::Robot.new(name: 'bob', template: :assistant)
    received = []

    bus = TypedBus::MessageBus.new
    bot1.with_bus(bus)
    bot2.with_bus(bus)
    bot2.on_message { |msg| received << msg.content }

    Async { bot1.send_message(to: :bob, content: 'hello') }

    assert_equal ['hello'], received
  end

  def test_spawn_creates_robot_on_same_bus
    bus = TypedBus::MessageBus.new
    parent = RobotLab::Robot.new(name: 'parent', template: :assistant, bus: bus)

    child = parent.spawn(name: 'child', system_prompt: 'You are a helper.')

    assert_instance_of RobotLab::Robot, child
    assert_equal 'child', child.name
    assert_equal bus, child.bus
    assert bus.channel?(:child)
  end

  def test_spawn_without_bus_creates_one
    robot = RobotLab::Robot.new(name: 'no_bus', template: :assistant)

    assert_nil robot.bus

    child = robot.spawn(name: 'child', system_prompt: 'test')

    assert_instance_of TypedBus::MessageBus, robot.bus
    assert_equal robot.bus, child.bus
    assert robot.bus.channel?(:no_bus)
    assert robot.bus.channel?(:child)
  end

  def test_spawn_child_can_receive_messages
    bus = TypedBus::MessageBus.new
    parent = RobotLab::Robot.new(name: 'parent', template: :assistant, bus: bus)
    received = []

    child = parent.spawn(name: 'child', system_prompt: 'You are a helper.')
    child.on_message { |message| received << message }

    Async { parent.send_message(to: :child, content: 'hello child') }

    assert_equal 1, received.size
    assert_equal 'hello child', received.first.content
    assert_equal 'parent', received.first.from
  end

  def test_spawn_passes_options_through
    bus = TypedBus::MessageBus.new
    tool = build_tool(name: 'test_tool') { |i| i }
    parent = RobotLab::Robot.new(name: 'parent', template: :assistant, bus: bus)

    child = parent.spawn(name: 'tooled', system_prompt: 'test', local_tools: [tool])

    assert_equal 1, child.local_tools.size
    assert_equal 'test_tool', child.local_tools.first.name
  end

  def test_spawn_defaults_name_to_robot
    bot = RobotLab.build
    bot2 = bot.spawn(system_prompt: 'test')

    assert_equal 'robot', bot2.name
  end

  def test_spawn_inherits_parent_model
    parent = RobotLab.build(name: 'parent')
    child  = parent.spawn(name: 'child', system_prompt: 'test')

    refute_nil parent.model
    assert_equal parent.model, child.model
  end

  def test_inherited_llm_settings_includes_model_and_provider
    parent = RobotLab.build(name: 'parent')
    parent.define_singleton_method(:model) { 'qwen3.6:latest' }
    parent.define_singleton_method(:provider) { 'ollama' }

    assert_equal(
      { model: 'qwen3.6:latest', provider: 'ollama' },
      parent.send(:inherited_llm_settings)
    )
  end

  def test_inherited_llm_settings_omits_provider_when_absent
    parent = RobotLab.build(name: 'parent') # default robot has no provider

    refute parent.send(:inherited_llm_settings).key?(:provider)
  end

  # Frontmatter extras tests

  def test_frontmatter_tools_are_resolved
    # Define a tool class that frontmatter can reference
    unless defined?(::FrontmatterTestTool)
      Object.const_set(:FrontmatterTestTool, Class.new(RobotLab::Tool) do
        description "A test tool defined for frontmatter resolution"
        param :input, type: "string", desc: "Test input"
        define_method(:execute) { |input:| "test: #{input}" }
      end)
    end

    robot = RobotLab::Robot.new(name: 'robot', template: :frontmatter_tools_test)

    assert_equal 1, robot.local_tools.size
    assert_kind_of ::FrontmatterTestTool, robot.local_tools.first
  end

  def test_constructor_tools_override_frontmatter_tools
    unless defined?(::FrontmatterTestTool)
      Object.const_set(:FrontmatterTestTool, Class.new(RobotLab::Tool) do
        description "A test tool defined for frontmatter resolution"
        param :input, type: "string", desc: "Test input"
        define_method(:execute) { |input:| "test: #{input}" }
      end)
    end

    my_tool = build_tool(name: 'my_tool') { |i| i }
    robot = RobotLab::Robot.new(
      name: 'robot',
      template: :frontmatter_tools_test,
      local_tools: [my_tool]
    )

    assert_equal 1, robot.local_tools.size
    assert_equal 'my_tool', robot.local_tools.first.name
  end

  def test_frontmatter_unresolvable_tool_warns
    # Create a template referencing a non-existent tool
    template_path = File.join(ENV.fetch('ROBOT_LAB_TEMPLATE_PATH', nil), 'frontmatter_bad_tool_test.md')
    File.write(template_path, <<~MD)
      ---
      description: Template with bad tool reference
      tools:
        - NonExistentToolThatDoesNotExist
      ---
      Test robot.
    MD

    robot = RobotLab::Robot.new(name: 'robot', template: :frontmatter_bad_tool_test)

    assert_equal 0, robot.local_tools.size
  ensure
    File.delete(template_path) if template_path && File.exist?(template_path)
  end

  def test_frontmatter_mcp_config
    robot = RobotLab::Robot.new(name: 'robot', template: :frontmatter_mcp_test)

    assert_kind_of Array, robot.mcp_config
    assert_equal 1, robot.mcp_config.size
    assert_equal "test_server", robot.mcp_config.first[:name]
    assert_equal "stdio", robot.mcp_config.first[:transport]
  end

  def test_constructor_mcp_overrides_frontmatter_mcp
    custom_mcp = [{ name: 'custom_server', transport: 'stdio', command: 'test' }]
    robot = RobotLab::Robot.new(
      name: 'robot',
      template: :frontmatter_mcp_test,
      mcp: custom_mcp
    )

    assert_equal custom_mcp, robot.mcp_config
  end

  def test_frontmatter_name_overrides_default
    robot = RobotLab::Robot.new(name: 'robot', template: :frontmatter_named_test)

    assert_equal 'support_bot', robot.name
  end

  def test_constructor_name_overrides_frontmatter_name
    robot = RobotLab::Robot.new(name: 'my_custom_name', template: :frontmatter_named_test)

    assert_equal 'my_custom_name', robot.name
  end

  def test_frontmatter_description
    robot = RobotLab::Robot.new(name: 'robot', template: :frontmatter_named_test)

    assert_equal 'Test template with name in frontmatter', robot.description
  end

  def test_constructor_description_overrides_frontmatter
    robot = RobotLab::Robot.new(
      name: 'robot',
      template: :frontmatter_named_test,
      description: 'My custom description'
    )

    assert_equal 'My custom description', robot.description
  end

  def test_spawn_fan_out_with_same_name
    bus = TypedBus::MessageBus.new
    parent = RobotLab::Robot.new(name: 'parent', template: :assistant, bus: bus)
    received = []

    worker1 = parent.spawn(name: 'worker', system_prompt: 'test')
    worker1.on_message { |msg| received << "w1:#{msg.content}" }

    worker2 = parent.spawn(name: 'worker', system_prompt: 'test')
    worker2.on_message { |msg| received << "w2:#{msg.content}" }

    Async { parent.send_message(to: :worker, content: 'task') }

    assert_equal 2, received.size
    assert_includes received, 'w1:task'
    assert_includes received, 'w2:task'
  end

  # BusPoller serialization tests

  def test_bus_poller_initialized
    robot = RobotLab::Robot.new(name: 'bot', template: :assistant)

    # No bus poller created until a bus is assigned
    assert_nil robot.instance_variable_get(:@bus_poller)
    assert_equal :default, robot.instance_variable_get(:@bus_poller_group)
  end

  def test_bus_poller_queues_concurrent_deliveries
    bus = TypedBus::MessageBus.new
    order = []

    bot = RobotLab::Robot.new(name: 'bot', template: :assistant, bus: bus)
    bot.on_message do |message|
      order << "start:#{message.content}"
      # Simulate a second message arriving while processing the first.
      # BusPoller sees robot is busy and queues the second delivery.
      if message.content == "first"
        second = RobotLab::RobotMessage.build(id: 99, from: "sender", content: "second")
        bot.send(:enqueue_delivery,
                 TypedBus::Delivery.new(second, channel_name: :bot, subscriber_id: 0))
      end
      order << "end:#{message.content}"
    end

    sender = RobotLab::Robot.new(name: 'sender', template: :assistant, bus: bus)
    Async { sender.send_message(to: :bot, content: "first") }

    # BusPoller ensures sequential processing: first completes, then second
    assert_equal ["start:first", "end:first", "start:second", "end:second"], order
  end

  def test_bus_poller_drains_multiple_queued
    bus = TypedBus::MessageBus.new
    order = []

    bot = RobotLab::Robot.new(name: 'bot', template: :assistant, bus: bus)
    bot.on_message do |message|
      order << message.content
      # Queue two more messages during the first processing
      if message.content == "first"
        %w[second third].each_with_index do |content, i|
          msg = RobotLab::RobotMessage.build(id: 90 + i, from: "sender", content: content)
          bot.send(:enqueue_delivery,
                   TypedBus::Delivery.new(msg, channel_name: :bot, subscriber_id: 0))
        end
      end
    end

    sender = RobotLab::Robot.new(name: 'sender', template: :assistant, bus: bus)
    Async { sender.send_message(to: :bot, content: "first") }

    assert_equal %w[first second third], order
  end

  def test_bus_poller_resets_on_error
    bus = TypedBus::MessageBus.new
    bot = RobotLab::Robot.new(name: 'bot', template: :assistant, bus: bus)
    bot.on_message do |message|
      raise "boom" if message.content == "explode"
    end

    sender = RobotLab::Robot.new(name: 'sender', template: :assistant, bus: bus)

    # The error propagates as BusError, but the poller resets the busy flag
    begin
      Async { sender.send_message(to: :bot, content: "explode") }
    rescue RobotLab::BusError
      # expected
    end

    # Poller is reset — subsequent messages can still be processed
    received = []
    bot.on_message { |msg| received << msg.content }
    Async { sender.send_message(to: :bot, content: "after") }
    assert_equal ["after"], received
  end

  def test_bus_processing_guard_correlates_replies_when_queued
    bus = TypedBus::MessageBus.new
    alice = RobotLab::Robot.new(name: 'alice', template: :assistant, bus: bus)
    bob = RobotLab::Robot.new(name: 'bob', template: :assistant, bus: bus)

    # Alice needs an on_message handler to avoid triggering handle_message_via_llm
    alice_received = []
    alice.on_message { |message| alice_received << message }

    bob.on_message do |message|
      bob.send_reply(to: :alice, content: "reply to #{message.content}", in_reply_to: message.key)
    end

    msg = Async { alice.send_message(to: :bob, content: "hello") }.wait

    wait_until(timeout: 1) { alice.outbox[msg.key][:status] == :replied }

    assert_equal :replied, alice.outbox[msg.key][:status]
    assert_equal 1, alice.outbox[msg.key][:replies].size
    assert_equal "reply to hello", alice.outbox[msg.key][:replies].first.content
  end

  # === Skills tests ===

  def test_skills_single_symbol_accepted
    robot = RobotLab::Robot.new(name: 'bot', skills: :skill_a_test)

    assert_equal [:skill_a_test], robot.skills
  end

  def test_skills_array_accepted
    robot = RobotLab::Robot.new(name: 'bot', skills: %i[skill_a_test skill_b_test])

    assert_equal %i[skill_a_test skill_b_test], robot.skills
  end

  def test_skills_prepend_body_before_main
    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant,
      skills: [:skill_a_test]
    )

    instructions = system_instructions(robot)

    # Skill body should appear before main template body
    skill_pos = instructions.index("Skill A")
    main_pos = instructions.index("helpful assistant")
    assert skill_pos, "Skill A body not found in instructions"
    assert main_pos, "Main template body not found in instructions"
    assert skill_pos < main_pos, "Skill body should appear before main template body"
  end

  def test_skills_ordering_preserved
    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant,
      skills: %i[skill_a_test skill_b_test]
    )

    instructions = system_instructions(robot)

    pos_a = instructions.index("Skill A")
    pos_b = instructions.index("Skill B")
    assert pos_a, "Skill A body not found"
    assert pos_b, "Skill B body not found"
    assert pos_a < pos_b, "Skill A should appear before Skill B"
  end

  def test_skills_recursive_expansion
    robot = RobotLab::Robot.new(
      name: 'bot',
      skills: [:skill_nested_test]
    )

    instructions = system_instructions(robot)

    # Leaf should appear before nested (depth-first)
    leaf_pos = instructions.index("leaf skill")
    nested_pos = instructions.index("nested skill")
    assert leaf_pos, "Leaf skill body not found"
    assert nested_pos, "Nested skill body not found"
    assert leaf_pos < nested_pos, "Leaf should appear before nested (depth-first)"
  end

  def test_skills_cycle_detection_skips_and_warns
    # This should not raise or infinite loop
    robot = RobotLab::Robot.new(
      name: 'bot',
      skills: [:skill_cycle_a_test]
    )

    instructions = system_instructions(robot)

    # Both cycle templates should have their bodies present (first visit)
    assert_includes instructions, "cycle A"
    assert_includes instructions, "cycle B"
  end

  def test_skills_self_reference_skipped
    # Should not infinite loop
    robot = RobotLab::Robot.new(
      name: 'bot',
      skills: [:skill_self_ref_test]
    )

    instructions = system_instructions(robot)

    assert_includes instructions, "self-referencing"
  end

  def test_skills_main_template_excluded_from_skills
    # skill_refs_main_test has skills: [assistant], which is the main template
    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant,
      skills: [:skill_refs_main_test]
    )

    instructions = system_instructions(robot)

    # The main template body should appear only once (at the end)
    # skill_refs_main_test references :assistant but it's already the main template
    assert_includes instructions, "helpful assistant"
    assert_includes instructions, "skill that references"
  end

  def test_skills_config_cascade
    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant,
      skills: [:skill_config_test]
    )

    # Main template has no temperature override, so skill's 0.9 should be base.
    # But constructor didn't set temperature, so the accumulated config applies.
    # skill_config_test sets temperature: 0.9
    chat = robot.instance_variable_get(:@chat)
    temp = chat.instance_variable_get(:@temperature)
    assert_equal 0.9, temp
  end

  def test_skills_constructor_config_overrides_all
    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant,
      skills: [:skill_config_test],
      temperature: 0.3
    )

    chat = robot.instance_variable_get(:@chat)
    temp = chat.instance_variable_get(:@temperature)
    assert_equal 0.3, temp
  end

  def test_skills_description_cascade
    robot = RobotLab::Robot.new(
      name: 'robot',
      template: :assistant,
      skills: [:skill_description_test]
    )

    # Main template description ("Helpful assistant with tool access") overwrites
    # skill description because main template is processed last
    assert_equal "Helpful assistant with tool access", robot.description
  end

  def test_skills_constructor_description_overrides
    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant,
      skills: [:skill_description_test],
      description: 'My custom description'
    )

    assert_equal 'My custom description', robot.description
  end

  def test_skills_from_front_matter
    robot = RobotLab::Robot.new(
      name: 'robot',
      template: :template_with_skills_test
    )

    instructions = system_instructions(robot)

    assert_includes instructions, "Skill A"
    assert_includes instructions, "main template with skills from front matter"
  end

  def test_skills_constructor_and_frontmatter_combined
    robot = RobotLab::Robot.new(
      name: 'robot',
      template: :template_with_skills_test,
      skills: [:skill_b_test]
    )

    instructions = system_instructions(robot)

    # Constructor skill_b_test + front matter skill_a_test + main template
    assert_includes instructions, "Skill B"
    assert_includes instructions, "Skill A"
    assert_includes instructions, "main template with skills from front matter"
  end

  def test_skills_shared_context
    robot = RobotLab::Robot.new(
      name: 'robot',
      template: :parameterized_main_test,
      skills: [:skill_with_params_test],
      context: { company_name: "Acme Corp" }
    )

    instructions = system_instructions(robot)

    # Both skill and main template should render with the same context
    assert_includes instructions, "You work for Acme Corp"
    assert_includes instructions, "Welcome to Acme Corp support"
  end

  def test_skills_without_main_template
    robot = RobotLab::Robot.new(
      name: 'bot',
      skills: [:skill_a_test]
    )

    instructions = system_instructions(robot)

    assert_includes instructions, "Skill A"
    assert_nil robot.template
  end

  def test_no_skills_unchanged_behavior
    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant
    )

    assert_nil robot.skills
    assert_nil robot.instance_variable_get(:@expanded_skills)

    instructions = system_instructions(robot)
    assert_includes instructions, "helpful assistant"
  end

  def test_build_factory_passes_skills
    robot = RobotLab.build(
      name: 'bot',
      skills: %i[skill_a_test skill_b_test]
    )

    assert_equal %i[skill_a_test skill_b_test], robot.skills
    instructions = system_instructions(robot)
    assert_includes instructions, "Skill A"
    assert_includes instructions, "Skill B"
  end

  def test_to_h_includes_skills
    robot = RobotLab::Robot.new(
      name: 'bot',
      skills: [:skill_a_test]
    )

    hash = robot.to_h
    assert_equal [:skill_a_test], hash[:skills]
  end

  def test_to_h_excludes_nil_skills
    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant
    )

    hash = robot.to_h
    refute hash.key?(:skills)
  end

  # ── Streaming: on_content callback ──────────────────────────

  def test_on_content_stored_from_constructor
    callback = ->(chunk) { chunk }

    robot = RobotLab::Robot.new(
      name: 'streamer',
      template: :assistant,
      on_content: callback
    )

    assert_equal callback, robot.instance_variable_get(:@on_content)
  end

  def test_on_content_stored_via_config
    callback = ->(chunk) { chunk }
    config = RobotLab::RunConfig.new(on_content: callback)

    robot = RobotLab::Robot.new(
      name: 'streamer',
      template: :assistant,
      config: config
    )

    assert_equal callback, robot.instance_variable_get(:@on_content)
  end

  def test_on_content_constructor_overrides_config
    config_cb = ->(chunk) { "config: #{chunk}" }
    constructor_cb = ->(chunk) { "constructor: #{chunk}" }
    config = RobotLab::RunConfig.new(on_content: config_cb)

    robot = RobotLab::Robot.new(
      name: 'streamer',
      template: :assistant,
      on_content: constructor_cb,
      config: config
    )

    assert_equal constructor_cb, robot.instance_variable_get(:@on_content)
  end

  def test_on_content_nil_by_default
    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant
    )

    assert_nil robot.instance_variable_get(:@on_content)
  end

  def test_on_content_via_build_factory
    callback = ->(chunk) { chunk }

    robot = RobotLab.build(
      name: 'streamer',
      template: :assistant,
      on_content: callback
    )

    assert_equal callback, robot.instance_variable_get(:@on_content)
  end

  def test_effective_streaming_block_stored_only
    callback = ->(chunk) { chunk }

    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant,
      on_content: callback
    )

    result = robot.send(:effective_streaming_block, nil)
    assert_equal callback, result
  end

  def test_effective_streaming_block_runtime_only
    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant
    )

    runtime = ->(chunk) { chunk }
    result = robot.send(:effective_streaming_block, runtime)
    assert_equal runtime, result
  end

  def test_effective_streaming_block_neither
    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant
    )

    result = robot.send(:effective_streaming_block, nil)
    assert_nil result
  end

  def test_effective_streaming_block_both_fires_both
    stored_chunks = []
    runtime_chunks = []

    stored = ->(chunk) { stored_chunks << chunk }
    runtime = ->(chunk) { runtime_chunks << chunk }

    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant,
      on_content: stored
    )

    combined = robot.send(:effective_streaming_block, runtime)
    combined.call("hello")
    combined.call("world")

    assert_equal %w[hello world], stored_chunks
    assert_equal %w[hello world], runtime_chunks
  end

  def test_effective_streaming_block_both_stored_fires_first
    order = []

    stored = ->(_chunk) { order << :stored }
    runtime = ->(_chunk) { order << :runtime }

    robot = RobotLab::Robot.new(
      name: 'bot',
      template: :assistant,
      on_content: stored
    )

    combined = robot.send(:effective_streaming_block, runtime)
    combined.call("test")

    assert_equal %i[stored runtime], order
  end

  def test_on_content_in_run_config_fields
    assert_includes RobotLab::RunConfig::CALLBACK_FIELDS, :on_content
    assert_includes RobotLab::RunConfig::FIELDS, :on_content
  end

  def test_on_content_not_serializable
    assert_includes RobotLab::RunConfig::NON_SERIALIZABLE_FIELDS, :on_content
  end

  # =========================================================================
  # Token tracking
  # =========================================================================

  def test_robot_starts_with_zero_token_totals
    robot = build_robot(name: "bot", system_prompt: "test")
    assert_equal 0, robot.total_input_tokens
    assert_equal 0, robot.total_output_tokens
  end

  def test_reset_token_totals
    robot = build_robot(name: "bot", system_prompt: "test")
    robot.instance_variable_set(:@total_input_tokens, 500)
    robot.instance_variable_set(:@total_output_tokens, 200)
    robot.reset_token_totals
    assert_equal 0, robot.total_input_tokens
    assert_equal 0, robot.total_output_tokens
  end

  def test_run_accumulates_tokens_from_response
    robot = build_robot(name: "bot", system_prompt: "test")
    tokens = RubyLLM::Tokens.new(input: 100, output: 50)
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "hello", tool_calls: nil, stop_reason: "end_turn", tokens: tokens
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    robot.run("test")

    assert_equal 100, robot.total_input_tokens
    assert_equal 50, robot.total_output_tokens
  end

  def test_run_accumulates_tokens_across_multiple_runs
    robot = build_robot(name: "bot", system_prompt: "test")
    tokens = RubyLLM::Tokens.new(input: 100, output: 50)
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "hello", tool_calls: nil, stop_reason: "end_turn", tokens: tokens
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    robot.run("first")
    robot.run("second")

    assert_equal 200, robot.total_input_tokens
    assert_equal 100, robot.total_output_tokens
  end

  # =========================================================================
  # Budget ledger
  # =========================================================================

  def test_budget_ledger_nil_when_no_budget_configured
    robot = build_robot(name: "bot", system_prompt: "test")
    assert_nil robot.budget_ledger
  end

  def test_budget_ledger_present_when_token_budget_configured
    robot = build_robot(name: "bot", system_prompt: "test", token_budget: 1_000)
    assert_instance_of RobotLab::Budget::Ledger, robot.budget_ledger
    assert_equal 1_000, robot.budget_ledger.limits[:tokens]
  end

  def test_budget_ledger_present_when_cost_budget_configured
    robot = build_robot(name: "bot", system_prompt: "test", cost_budget: 0.5)
    assert_instance_of RobotLab::Budget::Ledger, robot.budget_ledger
    assert_in_delta 0.5, robot.budget_ledger.limits[:cost]
  end

  def test_budget_ledger_reconciles_tokens_after_run
    robot = build_robot(name: "bot", system_prompt: "test", token_budget: 1_000)
    tokens = RubyLLM::Tokens.new(input: 60, output: 40)
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "hello", tool_calls: nil, stop_reason: "end_turn", tokens: tokens
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    robot.run("test")

    assert_equal 100, robot.budget_ledger.consumed[:tokens]
  end

  def test_result_includes_per_run_tokens
    robot = build_robot(name: "bot", system_prompt: "test")
    tokens = RubyLLM::Tokens.new(input: 75, output: 30)
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: tokens
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    result = robot.run("test")

    assert_equal 75, result.input_tokens
    assert_equal 30, result.output_tokens
  end

  # =========================================================================
  # Tool loop circuit breaker
  # =========================================================================

  def test_circuit_breaker_raises_when_limit_exceeded
    robot = build_robot(name: "bot", system_prompt: "test", max_tool_rounds: 2)
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "done", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)

    # Stub ask to fire the tool_call hook 3 times (exceeds max of 2)
    chat.define_singleton_method(:ask) do |_msg = nil, **_kw, &_b|
      3.times { @on[:tool_call]&.call(Object.new) }
      fake_response
    end

    assert_raises(RobotLab::ToolLoopError) { robot.run("test") }
  end

  def test_circuit_breaker_does_not_raise_at_limit
    robot = build_robot(name: "bot", system_prompt: "test", max_tool_rounds: 3)
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "done", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)

    chat.define_singleton_method(:ask) do |_msg = nil, **_kw, &_b|
      3.times { @on[:tool_call]&.call(Object.new) }
      fake_response
    end

    result = robot.run("test")
    assert_equal "done", result.reply
  end

  def test_circuit_breaker_restores_original_callback_after_run
    called = []
    user_cb = ->(tc) { called << tc }
    robot = build_robot(name: "bot", system_prompt: "test",
                        max_tool_rounds: 5, on_tool_call: user_cb)
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    robot.run("test")

    # After run, the chat's on_tool_call should be the original user callback
    assert_equal user_cb, chat.instance_variable_get(:@on)[:tool_call]
  end

  def test_no_circuit_breaker_when_max_tool_rounds_not_set
    robot = build_robot(name: "bot", system_prompt: "test")
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    # Should not raise even with no limit configured
    result = robot.run("test")
    assert_equal "ok", result.reply
  end

  # =========================================================================
  # Learning accumulation
  # =========================================================================

  def test_robot_starts_with_empty_learnings
    robot = build_robot(name: "bot", system_prompt: "test")
    assert_empty robot.learnings
  end

  def test_learn_adds_insight
    robot = build_robot(name: "bot", system_prompt: "test")
    robot.learn("Always check the cache first")
    assert_includes robot.learnings, "Always check the cache first"
  end

  def test_learn_returns_self_for_chaining
    robot = build_robot(name: "bot", system_prompt: "test")
    result = robot.learn("insight one")
    assert_equal robot, result
  end

  def test_learn_deduplicates_exact_match
    robot = build_robot(name: "bot", system_prompt: "test")
    robot.learn("check the cache")
    robot.learn("check the cache")
    assert_equal 1, robot.learnings.size
  end

  def test_learn_deduplicates_when_new_is_substring_of_existing
    robot = build_robot(name: "bot", system_prompt: "test")
    robot.learn("always check the cache before fetching")
    robot.learn("check the cache")  # shorter, already covered
    assert_equal 1, robot.learnings.size
    assert_includes robot.learnings, "always check the cache before fetching"
  end

  def test_learn_replaces_existing_when_new_is_superset
    robot = build_robot(name: "bot", system_prompt: "test")
    robot.learn("check the cache")
    robot.learn("always check the cache before fetching")  # supersedes
    assert_equal 1, robot.learnings.size
    assert_includes robot.learnings, "always check the cache before fetching"
  end

  def test_learn_ignores_empty_string
    robot = build_robot(name: "bot", system_prompt: "test")
    robot.learn("")
    robot.learn("   ")
    assert_empty robot.learnings
  end

  def test_learnings_injected_into_run_message
    robot = build_robot(name: "bot", system_prompt: "test")
    robot.learn("always be concise")

    received_message = nil
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) do |msg = nil, **_kw, &_b|
      received_message = msg
      fake_response
    end

    robot.run("do the task")

    assert_includes received_message, "LEARNINGS FROM PREVIOUS RUNS:"
    assert_includes received_message, "always be concise"
    assert_includes received_message, "do the task"
  end

  def test_no_learnings_injection_when_learnings_empty
    robot = build_robot(name: "bot", system_prompt: "test")

    received_message = nil
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) do |msg = nil, **_kw, &_b|
      received_message = msg
      fake_response
    end

    robot.run("do the task")

    assert_equal "do the task", received_message
  end

  def test_learnings_persisted_to_memory
    robot = build_robot(name: "bot", system_prompt: "test")
    robot.learn("retry on transient errors")
    stored = robot.memory.get(:learnings)
    assert_equal ["retry on transient errors"], stored
  end

  # =========================================================================
  # Robot#update method
  # =========================================================================

  def test_update_returns_self
    robot = build_robot(name: "bot", template: :assistant)
    result = robot.update
    assert_equal robot, result
  end

  def test_update_with_template_changes_template
    robot = build_robot(name: "bot", template: :assistant)
    robot.update(template: :helper)
    assert_equal :helper, robot.template
  end

  def test_update_with_system_prompt
    robot = build_robot(name: "bot", template: :assistant)
    robot.update(system_prompt: "New instructions.")
    # System instructions should contain the new prompt
    instructions = system_instructions(robot)
    assert_includes instructions.to_s, "New instructions."
  end

  def test_update_with_model
    robot = build_robot(name: "bot", template: :assistant)
    robot.update(model: "claude-sonnet-4")
    assert_includes robot.model, "claude-sonnet-4"
  end

  def test_update_with_temperature
    robot = build_robot(name: "bot", template: :assistant)
    robot.update(temperature: 0.5)
    chat = robot.instance_variable_get(:@chat)
    assert_equal 0.5, chat.instance_variable_get(:@temperature)
  end

  # =========================================================================
  # Robot#run with Memory parameter
  # =========================================================================

  def test_run_with_memory_object_uses_provided_memory
    robot = build_robot(name: "bot", system_prompt: "test")
    custom_memory = RobotLab::Memory.new

    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    robot.run("test", memory: custom_memory)
    # No assertion needed; just verify it doesn't raise
    pass
  end

  def test_run_with_hash_memory_merges_into_memory
    robot = build_robot(name: "bot", system_prompt: "test")

    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    # Memory merged from a hash: the value should be in robot's memory after run
    robot.run("test", memory: { extra_key: "extra_value" })
    assert_equal "extra_value", robot.memory.get(:extra_key)
  end

  # =========================================================================
  # Robot#with_template
  # =========================================================================

  def test_with_template_changes_template
    robot = build_robot(name: "bot", template: :assistant)
    robot.with_template(:helper)
    assert_equal :helper, robot.template
  end

  def test_with_template_returns_self
    robot = build_robot(name: "bot", template: :assistant)
    result = robot.with_template(:helper)
    assert_equal robot, result
  end

  # =========================================================================
  # RobotLab module methods
  # =========================================================================

  def test_configure_yields_config
    yielded = nil
    RobotLab.configure { |c| yielded = c }
    assert_equal RobotLab.config, yielded
  end

  def test_create_memory_returns_memory_instance
    memory = RobotLab.create_memory
    assert_instance_of RobotLab::Memory, memory
  end

  def test_create_memory_with_data
    memory = RobotLab.create_memory(data: { key: "value" })
    assert_equal "value", memory.data[:key]
  end

  def test_create_memory_with_cache_disabled
    memory = RobotLab.create_memory(enable_cache: false)
    assert_nil memory.cache
  end

  def test_create_network_returns_network_instance
    network = RobotLab.create_network(name: "test_net")
    assert_instance_of RobotLab::Network, network
  end

  def test_create_network_with_block
    robot = build_robot(name: "r1", system_prompt: "test")
    r = robot
    network = RobotLab.create_network(name: "block_net") do
      task :r1, r, depends_on: :none
    end
    assert_equal 1, network.robots.size
  end

  # =========================================================================
  # chat_provider, inject_mcp!, clear_messages, replace_messages
  # =========================================================================

  def test_chat_provider_returns_provider_or_nil
    robot = build_robot(name: "bot", template: :assistant)
    # May return nil or a provider string — just ensure it doesn't raise
    result = robot.chat_provider
    assert result.nil? || result.is_a?(String)
  end

  def test_inject_mcp_sets_clients_and_tools
    robot = build_robot(name: "bot", template: :assistant)
    mock_client = Object.new
    mock_tool = build_tool(name: "injected_tool") { |i| i }

    robot.inject_mcp!(clients: { "test_server" => mock_client }, tools: [mock_tool])

    assert_equal({ "test_server" => mock_client }, robot.mcp_clients)
    assert_equal [mock_tool], robot.mcp_tools
    assert robot.instance_variable_get(:@mcp_initialized)
  end

  def test_inject_mcp_returns_self
    robot = build_robot(name: "bot", template: :assistant)
    result = robot.inject_mcp!(clients: {}, tools: [])
    assert_equal robot, result
  end

  def test_clear_messages_removes_non_system
    robot = build_robot(name: "bot", system_prompt: "Be helpful.")
    chat = robot.instance_variable_get(:@chat)
    # Add a user message
    msg = Struct.new(:role, :content).new(:user, "hello")
    chat.instance_variable_get(:@messages) << msg

    robot.clear_messages
    # After clear, only system message should remain
    messages = chat.instance_variable_get(:@messages)
    assert(messages.all? { |m| m.role.to_s == "system" })
  end

  def test_clear_messages_without_keep_system_removes_all
    robot = build_robot(name: "bot", system_prompt: "Be helpful.")
    robot.clear_messages(keep_system: false)
    chat = robot.instance_variable_get(:@chat)
    messages = chat.instance_variable_get(:@messages)
    assert_empty messages
  end

  def test_replace_messages_sets_messages
    robot = build_robot(name: "bot", system_prompt: "test")
    new_messages = []
    robot.replace_messages(new_messages)
    chat = robot.instance_variable_get(:@chat)
    assert_equal new_messages, chat.instance_variable_get(:@messages)
  end

  def test_messages_delegates_to_chat
    robot = build_robot(name: "bot", system_prompt: "test")
    result = robot.messages
    assert result.is_a?(Array)
  end

  def test_reset_memory_returns_self
    robot = build_robot(name: "bot", system_prompt: "test")
    result = robot.reset_memory
    assert_equal robot, result
  end

  def test_failed_mcp_server_names_empty_by_default
    robot = build_robot(name: "bot", template: :assistant)
    assert_equal [], robot.failed_mcp_server_names
  end

  def test_mcp_client_returns_nil_for_unknown_server
    robot = build_robot(name: "bot", template: :assistant)
    assert_nil robot.mcp_client("nonexistent_server")
  end

  def test_failed_mcp_server_names_with_failed_configs
    robot = build_robot(name: "bot", template: :assistant)
    robot.instance_variable_set(:@failed_mcp_configs, { "dead_server" => { name: "dead_server" } })
    assert_equal ["dead_server"], robot.failed_mcp_server_names
  end

  def test_connect_mcp_returns_self
    robot = build_robot(name: "bot", template: :assistant)
    result = robot.connect_mcp!
    assert_equal robot, result
  end

  def test_with_temperature_delegator_updates_chat
    robot = build_robot(name: "bot", template: :assistant)
    result = robot.with_temperature(0.7)
    # Returns self for chaining
    assert_equal robot, result
    chat = robot.instance_variable_get(:@chat)
    assert_equal 0.7, chat.instance_variable_get(:@temperature)
  end

  def test_update_with_extra_kwargs
    robot = build_robot(name: "bot", template: :assistant)
    # This tests the kwargs.each branch in update
    # with_temperature should be callable via kwargs
    robot.update(temperature: 0.4)
    chat = robot.instance_variable_get(:@chat)
    assert_equal 0.4, chat.instance_variable_get(:@temperature)
  end

  def test_extract_run_context_with_string_value
    robot = build_robot(name: "bot", template: :assistant)
    result = ::SimpleFlow::Result.new("string message", context: {})
    context = robot.send(:extract_run_context, result)
    assert_equal "string message", context[:message]
  end

  def test_extract_run_context_with_robot_result_value
    robot = build_robot(name: "bot", template: :assistant)
    robot_result = RobotLab::RobotResult.new(
      robot_name: "prior",
      output: [RobotLab::TextMessage.new(role: "assistant", content: "prior output")]
    )
    result = ::SimpleFlow::Result.new(robot_result, context: {})
    context = robot.send(:extract_run_context, result)
    assert_equal "prior output", context[:message]
  end

  def test_extract_run_context_with_hash_value
    robot = build_robot(name: "bot", template: :assistant)
    result = ::SimpleFlow::Result.new({ message: "hash message", extra: "data" }, context: {})
    context = robot.send(:extract_run_context, result)
    assert_equal "hash message", context[:message]
  end

  def test_extract_run_context_with_other_value
    robot = build_robot(name: "bot", template: :assistant)
    result = ::SimpleFlow::Result.new(42, context: {})
    context = robot.send(:extract_run_context, result)
    assert_equal "42", context[:message]
  end

  def test_build_result_with_no_content_returns_empty_output
    robot = build_robot(name: "bot", template: :assistant)
    # Response with nil content should produce empty output
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: nil, tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    result = robot.run("test")
    assert_empty result.output
  end

  def test_result_text_prefers_response_content
    robot = build_robot(name: "bot", template: :assistant)
    response = Data.define(:content).new(content: "direct reply")
    assert_equal "direct reply", robot.send(:result_text, response)
  end

  def test_result_text_falls_back_to_last_assistant_text_on_tool_call_finish
    robot = build_robot(name: "bot", template: :assistant)
    msg = Struct.new(:role, :content).new(:assistant, "remembered reply")
    robot.instance_variable_get(:@chat).define_singleton_method(:messages) { [msg] }
    response = Data.define(:content).new(content: nil)
    assert_equal "remembered reply", robot.send(:result_text, response)
  end

  def test_result_text_returns_nil_when_no_text_anywhere
    robot = build_robot(name: "bot", template: :assistant)
    robot.instance_variable_get(:@chat).define_singleton_method(:messages) { [] }
    response = Data.define(:content).new(content: nil)
    assert_nil robot.send(:result_text, response)
  end

  def test_result_text_does_not_return_previous_turn_content
    # Regression: thinking-mode models (e.g. qwen3 via Ollama) can produce an
    # empty response.content when all generated text lands in <think> tags.
    # Without the current-turn scope, rfind returns the PREVIOUS turn's assistant
    # message, causing every subsequent turn to echo turn 1's answer.
    robot = build_robot(name: "bot", template: :assistant)
    msg_class = Struct.new(:role, :content)
    prior_user = msg_class.new(:user, "turn 1 question")
    prior_asst = msg_class.new(:assistant, "turn 1 answer")
    cur_user   = msg_class.new(:user, "turn 2 question")
    cur_asst   = msg_class.new(:assistant, nil) # thinking-mode: content is nil
    robot.instance_variable_get(:@chat).define_singleton_method(:messages) do
      [prior_user, prior_asst, cur_user, cur_asst]
    end
    response = Data.define(:content).new(content: nil)
    assert_nil robot.send(:result_text, response)
  end

  def test_result_text_falls_back_to_thinking_when_content_nil
    # qwen3 on Ollama routes all output to reasoning_content (chunk.thinking),
    # leaving response.content nil. response.thinking is a RubyLLM::Thinking
    # object with a .text method. result_text must surface .text so the user
    # sees a response instead of a blank or the object's inspect string.
    robot = build_robot(name: "bot", template: :assistant)
    robot.instance_variable_get(:@chat).define_singleton_method(:messages) { [] }
    thinking_obj = Struct.new(:text).new("my reasoning")
    response = Data.define(:content, :thinking).new(content: nil, thinking: thinking_obj)
    assert_equal "my reasoning", robot.send(:result_text, response)
  end

  def test_tools_filter_rejects_tool_instances
    error = assert_raises(ArgumentError) do
      RobotLab::Robot.new(name: "bot", template: :assistant, tools: [RobotLab::Tool.new])
    end
    assert_match(/local_tools:/, error.message)
  end

  def test_tools_filter_accepts_names_symbols_and_none
    RobotLab::Robot.new(name: "n1", template: :assistant, tools: %w[read write])
    RobotLab::Robot.new(name: "n2", template: :assistant, tools: [:read])
    RobotLab::Robot.new(name: "n3", template: :assistant, tools: :none)
    pass
  end

  # =========================================================================
  # Template with required params (rerender_template path)
  # =========================================================================

  def test_template_with_required_params_rerenders_at_run_time
    # parameterized_main_test.md has required param company_name: null
    robot = RobotLab::Robot.new(
      name: "param_bot",
      template: :parameterized_main_test
    )

    received_message = nil
    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) do |msg = nil, **_kw, &_b|
      received_message = msg
      fake_response
    end

    robot.run("test", company_name: "Acme Corp")

    # The template should be re-rendered with the provided context
    instructions = system_instructions(robot)
    assert_includes instructions, "Acme Corp"
  end

  def test_skills_rerender_at_run_time_with_params
    # skill_with_params_test.md has company_name param; parameterized_main_test has company_name: null
    robot = RobotLab::Robot.new(
      name: "param_skill_bot",
      template: :parameterized_main_test,
      skills: [:skill_with_params_test]
    )

    fake_response = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| fake_response }

    # Run with context param — this will trigger rerender_template with expanded_skills
    robot.run("test", company_name: "TestCo")

    instructions = system_instructions(robot)
    assert_includes instructions, "TestCo"
  end

  def test_skill_with_robot_name_sets_robot_name
    # skill_with_robot_name_test.md has robot_name in frontmatter
    # accumulate_extras line 201 + apply_accumulated_extras line 223
    robot = RobotLab::Robot.new(
      name: "robot",
      skills: [:skill_with_robot_name_test]
    )
    # name from skill frontmatter should apply because @name_from_constructor is false
    assert_equal "skill_named_bot", robot.name
  end

  def test_skill_with_robot_name_does_not_override_constructor_name
    # apply_accumulated_extras: skips robot_name when @name_from_constructor is true
    robot = RobotLab::Robot.new(
      name: "my_custom_name",
      skills: [:skill_with_robot_name_test]
    )
    assert_equal "my_custom_name", robot.name
  end

  def test_skill_with_tools_sets_local_tools
    # accumulate_extras line 209 + apply_accumulated_extras line 231
    unless defined?(::FrontmatterTestTool)
      Object.const_set(:FrontmatterTestTool, Class.new(RobotLab::Tool) do
        description "A frontmatter test tool"
        def execute = "ok"
      end)
    end

    robot = RobotLab::Robot.new(
      name: "robot",
      skills: [:skill_with_tools_test]
    )
    assert_equal 1, robot.local_tools.size
  end

  def test_skill_with_mcp_sets_mcp_config
    # accumulate_extras line 213 + apply_accumulated_extras line 235
    robot = RobotLab::Robot.new(
      name: "robot",
      skills: [:skill_with_mcp_test]
    )
    mcp_config = robot.instance_variable_get(:@mcp_config)
    assert_kind_of Array, mcp_config
    assert_equal 1, mcp_config.size
    assert_equal "skill_server", mcp_config.first[:name]
  end

  def test_resolve_frontmatter_tools_with_class
    # resolve_frontmatter_tools line 290: when Class => name.new
    unless defined?(::FrontmatterTestTool)
      Object.const_set(:FrontmatterTestTool, Class.new(RobotLab::Tool) do
        description "A frontmatter test tool"
        def execute = "ok"
      end)
    end

    robot = RobotLab::Robot.new(name: "robot", template: :assistant)
    result = robot.send(:resolve_frontmatter_tools, [::FrontmatterTestTool])
    assert_equal 1, result.size
    assert_instance_of ::FrontmatterTestTool, result.first
  end

  def test_resolve_frontmatter_tools_with_instance
    # resolve_frontmatter_tools line 292: else branch (instance passed directly)
    unless defined?(::FrontmatterTestTool)
      Object.const_set(:FrontmatterTestTool, Class.new(RobotLab::Tool) do
        description "A frontmatter test tool"
        def execute = "ok"
      end)
    end

    tool_instance = ::FrontmatterTestTool.new
    robot = RobotLab::Robot.new(name: "robot", template: :assistant)
    result = robot.send(:resolve_frontmatter_tools, [tool_instance])
    assert_equal 1, result.size
    assert_equal tool_instance, result.first
  end

  def test_update_with_non_standard_kwargs_calls_chat_method
    # robot.rb lines 379-381: kwargs.each block for non-explicit params
    robot = build_robot(name: "bot", template: :assistant)
    chat = robot.instance_variable_get(:@chat)
    # with_top_p should exist as a chat method (dynamically delegated)
    if chat.respond_to?(:with_top_p)
      robot.update(top_p: 0.9)
      assert_equal 0.9, chat.instance_variable_get(:@top_p)
    else
      # Fallback: test that update returns self with unknown kwargs (no raise)
      result = robot.update(nonexistent_param: "value")
      assert_equal robot, result
    end
  end

  def test_provider_sets_chat_kwargs
    # robot.rb lines 211-212: provider branch sets chat_kwargs when @provider is set
    # Configure fake ollama endpoint so RubyLLM doesn't raise on missing config
    RubyLLM.configure { |c| c.ollama_api_base = "http://localhost:11434" }
    robot = RobotLab::Robot.new(
      name: "local_bot",
      provider: "ollama",
      model: "llama3.2"
    )
    provider = robot.instance_variable_get(:@provider)
    assert_equal "ollama", provider
  ensure
    RubyLLM.configure { |c| c.ollama_api_base = nil }
  end

  def test_ensure_mcp_clients_with_failing_server_stores_failed_config
    # mcp_management.rb lines 34, 36, 42-50, 55-56, 58, 62-68
    robot = build_robot(name: "bot", template: :assistant)
    failing_config = [{ name: "bad_server", transport: { type: "stdio", command: "nonexistent-xyz" } }]
    robot.send(:ensure_mcp_clients, failing_config)
    # Failed connection should be stored
    assert_equal ["bad_server"], robot.failed_mcp_server_names
  end

  def test_ensure_mcp_clients_second_call_retries_failed
    # mcp_management.rb lines 36-39: second call with already-initialized retries failed servers
    robot = build_robot(name: "bot", template: :assistant)
    failing_config = [{ name: "bad_server", transport: { type: "stdio", command: "nonexistent-xyz" } }]
    robot.send(:ensure_mcp_clients, failing_config)
    # Second call with same config should hit the retry path (line 36-38)
    robot.send(:ensure_mcp_clients, failing_config)
    assert_equal ["bad_server"], robot.failed_mcp_server_names
  end

  def test_ensure_mcp_clients_success_path
    # mcp_management.rb lines 59-61, 113-115, 117, 122, 124, 127: success path when client connects
    robot = build_robot(name: "bot", template: :assistant)
    server_config = { name: "ok_server", transport: { type: "stdio", command: "nonexistent" } }

    # Build a mock client that reports connected and has tools
    tool_defs = [
      { name: "search", description: "Search tool", inputSchema: { type: "object", properties: {} } }
    ]
    mock_client = Object.new
    mock_client.define_singleton_method(:connect) {}
    mock_client.define_singleton_method(:connected?) { true }
    mock_client.define_singleton_method(:list_tools) { tool_defs }
    mock_client.define_singleton_method(:server) do
      s = Object.new
      s.define_singleton_method(:name) { "ok_server" }
      s
    end

    # Stub MCP::Client.new to return our mock
    RobotLab::MCP::Client.define_singleton_method(:new) { |*_args, **_kwargs| mock_client }

    robot.send(:ensure_mcp_clients, [server_config])

    # The client should be registered in @mcp_clients
    clients = robot.instance_variable_get(:@mcp_clients)
    assert_equal mock_client, clients["ok_server"]
    # Tools should be discovered
    mcp_tools = robot.instance_variable_get(:@mcp_tools)
    assert_equal 1, mcp_tools.size

    # Call the discovered tool to cover mcp_management.rb line 122 (the call_tool block)
    mock_client.define_singleton_method(:call_tool) { |_name, _args| "tool_result" }
    result = mcp_tools.first.execute
    assert_equal "tool_result", result
  ensure
    # Restore MCP::Client.new
    RobotLab::MCP::Client.singleton_class.remove_method(:new) rescue nil
  end

  def test_ensure_mcp_clients_exception_path
    # mcp_management.rb lines 70-72: rescue StandardError in init_mcp_client
    robot = build_robot(name: "bot", template: :assistant)
    # Pass invalid transport type to trigger exception in MCP::Client.new
    invalid_config = [{ name: "bad_server", transport: { type: "invalid_transport_xyz" } }]
    # This should not raise, just store the failure
    robot.send(:ensure_mcp_clients, invalid_config)
    assert_equal ["bad_server"], robot.failed_mcp_server_names
  end

  def test_retry_failed_servers_success_path
    # mcp_management.rb lines 95-98: retry succeeds and registers client
    robot = build_robot(name: "bot", template: :assistant)
    failing_config = [{ name: "retry_server", transport: { type: "stdio", command: "nonexistent-xyz" } }]

    # First call: fails and records
    robot.send(:ensure_mcp_clients, failing_config)
    assert_equal ["retry_server"], robot.failed_mcp_server_names

    # Build a mock client that reports connected for the retry
    tool_defs = [{ name: "retry_tool", description: "Retry tool", inputSchema: { type: "object", properties: {} } }]
    mock_client = Object.new
    mock_client.define_singleton_method(:connect) {}
    mock_client.define_singleton_method(:connected?) { true }
    mock_client.define_singleton_method(:list_tools) { tool_defs }
    mock_client.define_singleton_method(:server) do
      s = Object.new
      s.define_singleton_method(:name) { "retry_server" }
      s
    end

    RobotLab::MCP::Client.define_singleton_method(:new) { |*_args, **_kwargs| mock_client }
    # Second call: should hit retry path and succeed
    robot.send(:ensure_mcp_clients, failing_config)
    # After successful retry, not in failed list anymore
    assert_equal [], robot.failed_mcp_server_names
    # Tool should be discovered from the retry
    mcp_tools = robot.instance_variable_get(:@mcp_tools)
    assert_equal 1, mcp_tools.size
  ensure
    RobotLab::MCP::Client.singleton_class.remove_method(:new) rescue nil
  end

  def test_retry_failed_servers_exception_path
    # mcp_management.rb lines 103-105: rescue in retry_failed_servers when retry itself fails
    robot = build_robot(name: "bot", template: :assistant)
    failing_config = [{ name: "retry_fail_server", transport: { type: "stdio", command: "nonexistent-xyz" } }]

    # First call: fails and records as failed
    robot.send(:ensure_mcp_clients, failing_config)
    assert_equal ["retry_fail_server"], robot.failed_mcp_server_names

    # Make MCP::Client.new raise during retry
    RobotLab::MCP::Client.define_singleton_method(:new) do |*_args, **_kwargs|
      raise StandardError, "retry connection error"
    end

    # Second call: retry path should rescue and log warn
    robot.send(:ensure_mcp_clients, failing_config)
    # Server remains in failed list since retry failed
    assert_equal ["retry_fail_server"], robot.failed_mcp_server_names
  ensure
    RobotLab::MCP::Client.singleton_class.remove_method(:new) rescue nil
  end

  def test_extract_server_name_with_mcp_server_object
    # mcp_management.rb line 138: MCP::Server branch in extract_server_name
    robot = build_robot(name: "bot", template: :assistant)
    server = RobotLab::MCP::Server.new(
      name: "my_mcp_server",
      transport: { type: "stdio", command: "echo" }
    )
    name = robot.send(:extract_server_name, server)
    assert_equal "my_mcp_server", name
  end

  def test_extract_server_name_with_other_type
    # mcp_management.rb line 140: else branch in extract_server_name
    robot = build_robot(name: "bot", template: :assistant)
    # Pass an object that isn't a Hash or MCP::Server
    custom = Object.new
    custom.define_singleton_method(:to_s) { "custom_server" }
    name = robot.send(:extract_server_name, custom)
    assert_equal "custom_server", name
  end

  def test_chat_provider_returns_nil_on_error
    # robot.rb line 525: rescue branch in chat_provider
    robot = build_robot(name: "bot", template: :assistant)
    chat = robot.instance_variable_get(:@chat)
    # Override model to raise an error when accessed
    chat.define_singleton_method(:model) { raise StandardError, "model error" }
    result = robot.send(:chat_provider)
    assert_nil result
  end

  def test_default_handler_is_no_op
    # Default @message_handler is a no-op lambda. A robot joined to a bus
    # without on_message set should ack messages silently, not trigger LLM.
    bus = TypedBus::MessageBus.new
    llm_called = false

    alice = RobotLab::Robot.new(name: "alice", template: :assistant, bus: bus)

    # bob has NO on_message set — default handler should ack and do nothing
    bob = RobotLab::Robot.new(name: "bob", template: :assistant, bus: bus)
    bob_chat = bob.instance_variable_get(:@chat)
    bob_chat.define_singleton_method(:ask) { |*| llm_called = true }

    Async { alice.send_message(to: :bob, content: "hello bob") }

    sleep 0.2
    refute llm_called, "default handler must not trigger LLM"
  end

  # =========================================================================
  # Structured Delegation
  # =========================================================================

  def fake_response_for(robot, content)
    resp = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: content, tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    chat = robot.instance_variable_get(:@chat)
    chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| resp }
    resp
  end

  def test_delegate_returns_robot_result
    delegator = build_robot(name: "manager", template: :assistant)
    worker    = build_robot(name: "worker",  template: :assistant)
    fake_response_for(worker, "task done")

    result = delegator.delegate(to: worker, task: "do the thing")

    assert_kind_of RobotLab::RobotResult, result
    assert_equal "task done", result.reply
  end

  def test_delegate_sets_delegated_by
    delegator = build_robot(name: "manager", template: :assistant)
    worker    = build_robot(name: "worker",  template: :assistant)
    fake_response_for(worker, "done")

    result = delegator.delegate(to: worker, task: "summarize")

    assert_equal "manager", result.delegated_by
  end

  def test_delegate_sets_robot_name_to_delegatee
    delegator = build_robot(name: "manager", template: :assistant)
    worker    = build_robot(name: "specialist", template: :assistant)
    fake_response_for(worker, "analysis complete")

    result = delegator.delegate(to: worker, task: "analyze")

    assert_equal "specialist", result.robot_name
  end

  def test_delegate_records_duration
    delegator = build_robot(name: "manager", template: :assistant)
    worker    = build_robot(name: "worker",  template: :assistant)
    fake_response_for(worker, "done")

    result = delegator.delegate(to: worker, task: "work")

    assert_kind_of Float, result.duration
    assert_operator result.duration, :>=, 0.0
  end

  def test_delegate_forwards_kwargs_to_run
    delegator = build_robot(name: "manager",  template: :assistant)
    worker    = build_robot(name: "templated", template: :parameterized_main_test)

    received = nil
    resp = Data.define(:content, :tool_calls, :stop_reason, :tokens).new(
      content: "ok", tool_calls: nil, stop_reason: "end_turn", tokens: nil
    )
    worker_chat = worker.instance_variable_get(:@chat)
    worker_chat.define_singleton_method(:ask) do |msg = nil, **_kw, &_b|
      received = msg
      resp
    end

    delegator.delegate(to: worker, task: "hello", company_name: "Acme")

    refute_nil received
  end

  def test_delegated_by_nil_on_direct_run
    robot = build_robot(name: "solo", template: :assistant)
    fake_response_for(robot, "direct")

    result = robot.run("question")

    assert_nil result.delegated_by
  end

  # -----------------------------------------------------------------------
  # Async delegation
  # -----------------------------------------------------------------------

  def test_async_delegate_returns_delegation_future
    delegator = build_robot(name: "manager",  template: :assistant)
    worker    = build_robot(name: "worker",   template: :assistant)
    fake_response_for(worker, "async done")

    future = delegator.delegate(to: worker, task: "work", async: true)

    assert_kind_of RobotLab::DelegationFuture, future
  end

  def test_async_delegate_future_resolves_with_result
    delegator = build_robot(name: "manager", template: :assistant)
    worker    = build_robot(name: "worker",  template: :assistant)
    fake_response_for(worker, "async answer")

    future = delegator.delegate(to: worker, task: "async task", async: true)
    result = future.value(timeout: 5)

    assert_kind_of RobotLab::RobotResult, result
    assert_equal "async answer", result.reply
  end

  def test_async_delegate_sets_delegated_by
    delegator = build_robot(name: "manager", template: :assistant)
    worker    = build_robot(name: "worker",  template: :assistant)
    fake_response_for(worker, "done")

    future = delegator.delegate(to: worker, task: "task", async: true)
    result = future.value(timeout: 5)

    assert_equal "manager", result.delegated_by
  end

  def test_async_delegate_sets_robot_name
    delegator = build_robot(name: "manager",    template: :assistant)
    worker    = build_robot(name: "specialist", template: :assistant)
    fake_response_for(worker, "done")

    future = delegator.delegate(to: worker, task: "task", async: true)
    result = future.value(timeout: 5)

    assert_equal "specialist", result.robot_name
  end

  def test_async_delegate_records_duration
    delegator = build_robot(name: "manager", template: :assistant)
    worker    = build_robot(name: "worker",  template: :assistant)
    fake_response_for(worker, "done")

    future = delegator.delegate(to: worker, task: "task", async: true)
    result = future.value(timeout: 5)

    assert_kind_of Float, result.duration
    assert_operator result.duration, :>=, 0.0
  end

  def test_async_delegate_future_resolved_predicate
    delegator = build_robot(name: "manager", template: :assistant)
    worker    = build_robot(name: "worker",  template: :assistant)
    fake_response_for(worker, "done")

    future = delegator.delegate(to: worker, task: "task", async: true)

    refute future.resolved?  # likely not done yet
    future.value(timeout: 5)
    assert future.resolved?
  end

  def test_async_delegate_future_carries_robot_name_before_resolution
    delegator = build_robot(name: "manager",    template: :assistant)
    worker    = build_robot(name: "specialist", template: :assistant)

    # Don't stub — future is checked before it resolves
    future = delegator.delegate(to: worker, task: "task", async: true)

    assert_equal "specialist", future.robot_name
    assert_equal "manager",    future.delegated_by
  end

  def test_async_delegate_fan_out_two_specialists
    delegator   = build_robot(name: "manager",    template: :assistant)
    summarizer  = build_robot(name: "summarizer", template: :assistant)
    analyst     = build_robot(name: "analyst",    template: :assistant)

    fake_response_for(summarizer, "brief summary")
    fake_response_for(analyst,    "key metric")

    f1 = delegator.delegate(to: summarizer, task: "summarize", async: true)
    f2 = delegator.delegate(to: analyst,    task: "analyze",   async: true)

    r1 = f1.value(timeout: 5)
    r2 = f2.value(timeout: 5)

    assert_equal "brief summary", r1.reply
    assert_equal "key metric",    r2.reply
    assert_equal "manager", r1.delegated_by
    assert_equal "manager", r2.delegated_by
  end

  def test_async_delegate_future_rejects_on_error
    delegator = build_robot(name: "manager", template: :assistant)
    worker    = build_robot(name: "worker",  template: :assistant)

    worker_chat = worker.instance_variable_get(:@chat)
    worker_chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| raise "boom" }

    future = delegator.delegate(to: worker, task: "task", async: true)

    assert_raises(RuntimeError) { future.value(timeout: 5) }
  end

  def test_async_delegate_future_timeout_raises_delegation_timeout
    delegator = build_robot(name: "manager", template: :assistant)
    worker    = build_robot(name: "worker",  template: :assistant)

    worker_chat = worker.instance_variable_get(:@chat)
    worker_chat.define_singleton_method(:ask) { |_msg = nil, **_kw, &_b| sleep 10 }

    future = delegator.delegate(to: worker, task: "task", async: true)

    assert_raises(RobotLab::DelegationFuture::DelegationTimeout) { future.value(timeout: 0.05) }
  end

  # Private method: expand_skills_with_catalog
  def test_expand_skills_stores_agent_skill_in_pending_when_catalog_hit
    fixtures = File.expand_path("../fixtures/skills", __dir__)
    catalog  = RobotLab::AgentSkillCatalog.new(fixtures)

    robot = build_robot(name: "bot")
    robot.instance_variable_set(:@pending_agent_skills, [])
    robot.instance_variable_set(:@agent_skill_store, FakeSkillStore.new)

    robot.send(:expand_skills_with_catalog, [:test_skill], Set.new, catalog)

    pending = robot.instance_variable_get(:@pending_agent_skills)
    assert_equal 1, pending.length
    assert_equal "test_skill", pending.first.name
  end

  # Integration tests for AgentSkills support
  def test_skills_param_handles_mixed_pm_and_agentskill_formats
    # Exercises the skills: constructor param with both a PM template (skill_leaf_test)
    # and an AgentSkill (test_skill). Temporarily swap the catalog singleton to point
    # at test fixtures so the test doesn't depend on ~/.prompts/skills/.
    fixtures = File.expand_path("../fixtures/skills", __dir__)
    catalog  = RobotLab::AgentSkillCatalog.new(fixtures)
    RobotLab::AgentSkillCatalog.instance_variable_set(:@instance, catalog)

    begin
      robot = build_robot(name: "bot", skills: %i[skill_leaf_test test_skill])

      expanded = robot.instance_variable_get(:@expanded_skills)
      pending  = robot.instance_variable_get(:@pending_agent_skills)

      refute_nil expanded, "Expected @expanded_skills to be populated"
      assert_includes expanded, :skill_leaf_test
      assert_equal 1, pending.length
      assert_equal "test_skill", pending.first.name
    ensure
      RobotLab::AgentSkillCatalog.reset!
    end
  end

  def test_restore_after_agent_skills_leaves_tool_count_unchanged
    fixtures = File.expand_path("../fixtures/skills", __dir__)
    skill    = RobotLab::AgentSkill.new(File.join(fixtures, "scripted_skill", "SKILL.md"))

    robot = build_robot(name: "bot", system_prompt: "You are helpful.")
    robot.instance_variable_set(:@pending_agent_skills, [skill])
    store = FakeSkillStore.new
    store.store(skill.name.to_sym, skill.description)
    robot.instance_variable_set(:@agent_skill_store, store)

    initial_tool_count = robot.local_tools.length

    # Inject empty list then restore; tool count must be unchanged
    robot.send(:inject_agent_skills, [])
    robot.send(:restore_after_agent_skills)

    assert_equal initial_tool_count, robot.local_tools.length
  end

  def test_expand_skills_uses_pm_template_when_not_in_catalog
    # Use a fixture catalog that does not contain :skill_leaf_test to guarantee
    # the PM fallback path is exercised regardless of ~/.prompts/skills/ contents.
    fixtures = File.expand_path("../fixtures/skills", __dir__)
    catalog  = RobotLab::AgentSkillCatalog.new(fixtures)

    robot  = build_robot(name: "bot")
    result = robot.send(:expand_skills_with_catalog, [:skill_leaf_test], Set.new, catalog)
    assert_includes result, :skill_leaf_test
  end

  # ── auto_compact ─────────────────────────────────────────────

  def test_maybe_compact_skips_when_none
    called = false
    robot  = build_robot(name: "bot", system_prompt: "hi", config: RobotLab::RunConfig.new(auto_compact: :none))
    robot.define_singleton_method(:compress_history) { called = true }
    robot.send(:maybe_compact)
    refute called
  end

  def test_maybe_compact_skips_when_nil
    called = false
    robot  = build_robot(name: "bot", system_prompt: "hi")
    robot.define_singleton_method(:compress_history) { called = true }
    robot.send(:maybe_compact)
    refute called
  end

  def test_maybe_compact_skips_when_no_messages
    called = false
    robot  = build_robot(name: "bot", system_prompt: "hi",
                         config: RobotLab::RunConfig.new(auto_compact: :context_window))
    robot.define_singleton_method(:compress_history) { called = true }
    robot.send(:maybe_compact)
    refute called
  end

  def test_maybe_compact_calls_proc_with_robot
    received = nil
    my_proc  = ->(r) { received = r }
    robot    = build_robot(name: "bot", system_prompt: "hi", config: RobotLab::RunConfig.new(auto_compact: my_proc))
    fake_msg = Struct.new(:content).new("hello world")
    robot.instance_variable_get(:@chat).instance_variable_set(:@messages, [fake_msg])
    robot.send(:maybe_compact)
    assert_same robot, received
  end

  def test_maybe_compact_proc_owns_compaction_decision
    call_count = 0
    my_proc    = ->(_r) { call_count += 1 }
    robot      = build_robot(name: "bot", system_prompt: "hi", config: RobotLab::RunConfig.new(auto_compact: my_proc))
    fake_msg   = Struct.new(:content).new("hello world")
    robot.instance_variable_get(:@chat).instance_variable_set(:@messages, [fake_msg])
    robot.send(:maybe_compact)
    robot.send(:maybe_compact)
    assert_equal 2, call_count
  end

  def test_compact_if_over_context_window_triggers_compress_when_over_threshold
    called = false
    robot  = build_robot(name: "bot", system_prompt: "hi",
                         config: RobotLab::RunConfig.new(auto_compact: :context_window, compact_threshold: 0.0))
    robot.define_singleton_method(:compress_history) { called = true }
    # threshold=0.0 means any non-negative token count triggers compaction
    fake_msg = Struct.new(:content).new("x")
    robot.instance_variable_get(:@chat).instance_variable_set(:@messages, [fake_msg])
    robot.send(:compact_if_over_context_window)
    assert called
  end

  def test_compact_if_over_context_window_skips_when_under_threshold
    called = false
    robot  = build_robot(name: "bot", system_prompt: "hi",
                         config: RobotLab::RunConfig.new(auto_compact: :context_window, compact_threshold: 0.99))
    robot.define_singleton_method(:compress_history) { called = true }
    fake_msg = Struct.new(:content).new("x")
    robot.instance_variable_get(:@chat).instance_variable_set(:@messages, [fake_msg])
    robot.send(:compact_if_over_context_window)
    refute called
  end

  def test_compact_if_over_context_window_logs_and_skips_on_dependency_error
    log_output = StringIO.new
    RobotLab.config.logger = Logger.new(log_output)

    robot = build_robot(name: "dep-bot", system_prompt: "hi",
                        config: RobotLab::RunConfig.new(auto_compact: :context_window, compact_threshold: 0.0))
    robot.define_singleton_method(:compress_history) { raise RobotLab::DependencyError, "classifier gem missing" }
    fake_msg = Struct.new(:content).new("x")
    robot.instance_variable_get(:@chat).instance_variable_set(:@messages, [fake_msg])

    robot.send(:compact_if_over_context_window)

    RobotLab.config.logger = Logger.new(nil)
    assert_match(/auto_compact/, log_output.string)
  end
end
