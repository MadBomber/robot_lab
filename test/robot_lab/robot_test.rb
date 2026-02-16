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
    tool3 = build_tool(name: 'format') { |i| i.to_s }

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
      begin
        bus.publish(:typed_bot, "not a RobotMessage")
      rescue ArgumentError => e
        error = e
      end
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
      bob.reply(message, "got it")
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


  # Frontmatter extras tests

  def test_frontmatter_tools_are_resolved
    # Define a tool class that frontmatter can reference
    Object.const_set(:FrontmatterTestTool, Class.new(RobotLab::Tool) {
      description "A test tool defined for frontmatter resolution"
      param :input, type: "string", desc: "Test input"
      define_method(:execute) { |input:| "test: #{input}" }
    }) unless defined?(::FrontmatterTestTool)

    robot = RobotLab::Robot.new(name: 'robot', template: :frontmatter_tools_test)

    assert_equal 1, robot.local_tools.size
    assert_kind_of ::FrontmatterTestTool, robot.local_tools.first
  end


  def test_constructor_tools_override_frontmatter_tools
    Object.const_set(:FrontmatterTestTool, Class.new(RobotLab::Tool) {
      description "A test tool defined for frontmatter resolution"
      param :input, type: "string", desc: "Test input"
      define_method(:execute) { |input:| "test: #{input}" }
    }) unless defined?(::FrontmatterTestTool)

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
    template_path = File.join(ENV['ROBOT_LAB_TEMPLATE_PATH'], 'frontmatter_bad_tool_test.md')
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
end
