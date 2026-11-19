# frozen_string_literal: true

require 'test_helper'

# Robot + RubyLLM::MCP end to end, over the in-process FakeMCPTransport:
# per-run attach/detach, allowlists and caps across local and MCP tools,
# connection failures, discovery, the :tool_call hook bridge, approvals,
# input requests, tasks, and MCP prompts.
class RobotLab::Robot::MCPIntegrationTest < Minitest::Test
  class ObservingToolHook < RobotLab::Hook
    self.namespace = :global
    class << self
      attr_accessor :events

      def around_tool_call(ctx, &)
        events << [ctx.tool_name, ctx.mcp?, ctx.mcp_server&.name]
        yield
      end
    end
  end

  def setup
    RobotLab.clear_hooks!
    ObservingToolHook.events = []
  end

  def teardown
    RobotLab.clear_hooks!
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  def fake(name = 'fake', tools: ['echo'], **config)
    transport = FakeMCPTransport.new(name: name, tools: tools.map { |t| t.is_a?(Hash) ? t : fake_tool_def(t) })
    [fake_mcp_server(name: name, transport: transport, **config), transport]
  end

  def text_message(text)
    RubyLLM::Message.new(role: :assistant, content: text)
  end

  def tool_call_message(name, id: 'call_1', **arguments)
    RubyLLM::Message.new(role: :assistant, content: "calling #{name}",
                         tool_calls: { id => RubyLLM::ToolCall.new(id: id, name: name, arguments: arguments) })
  end

  # Replace the model with a script of assistant messages.
  def script_generation(robot, *responses)
    queue = responses.dup
    robot.chat.define_singleton_method(:generate) do |&_block|
      message = queue.shift or raise 'no scripted response left'
      add_message(message)
    end
  end

  def robot_with(servers, **)
    build_robot(name: 'bot', template: :assistant, mcp: servers, **).tap { |r| script_generation(r, text_message('done')) }
  end

  def tool_keys(robot)
    robot.chat.tools.keys
  end

  def tool_messages(robot)
    robot.chat.messages.select { |m| m.role == :tool }
  end

  # The params of the last tools/call the transport saw (arguments plus any input answers).
  def last_call_params(transport)
    transport.requests.select { |m| m[:method] == 'tools/call' }.last[:params]
  end

  # ── per-run attach / detach ──────────────────────────────────────────────

  def test_run_with_mcp_inherit_attaches_mcp_tools_beside_local_ones
    server, = fake
    robot = robot_with([server], local_tools: [build_tool(name: 'local') { |i| i }])

    robot.run('hi', mcp: :inherit, tools: :inherit)
    assert_equal %i[local echo], tool_keys(robot)
    assert server.connected?
  end

  def test_default_run_sends_no_tools
    server, transport = fake
    robot = robot_with([server])

    robot.run('hi')
    assert_empty tool_keys(robot)
    assert_empty transport.requests, 'no server should be contacted when no run selects it'
  end

  def test_mcp_none_on_a_later_run_detaches_mcp_tools_but_keeps_the_server
    server, transport = fake
    robot = robot_with([server], local_tools: [build_tool(name: 'local') { |i| i }])
    script_generation(robot, text_message('one'), text_message('two'), text_message('three'))

    robot.run('hi', mcp: :inherit, tools: :inherit)
    assert_equal %i[local echo], tool_keys(robot)

    robot.run('hi', mcp: :none, tools: :inherit)
    assert_equal %i[local], tool_keys(robot)
    assert_equal ['fake'], robot.mcp.names
    assert_equal 0, transport.close_count

    robot.run('hi', mcp: :none, tools: :none)
    assert_empty tool_keys(robot)
  end

  def test_runtime_mcp_array_registers_and_uses_servers_first_seen_at_run_time
    server, = fake('late')
    robot = robot_with(:none)

    robot.run('hi', mcp: [server], tools: :inherit)
    assert_equal %i[echo], tool_keys(robot)
    assert_equal ['late'], robot.mcp.names
  end

  def test_hash_spec_builds_one_server_across_runs
    transport = FakeMCPTransport.new(name: 'fs', tools: [fake_tool_def('read')])
    robot = robot_with([{ name: 'fs', transport: transport }])
    script_generation(robot, text_message('one'), text_message('two'))

    2.times { robot.run('hi', mcp: :inherit, tools: :inherit) }
    assert_equal(1, transport.requests.count { |m| m[:method] == 'initialize' })
    assert_equal %i[read], tool_keys(robot)
  end

  # ── allowlist, cap, uniqueness, deferral ─────────────────────────────────

  def test_tools_allowlist_filters_across_local_and_mcp_tools
    server, = fake(tools: %w[echo shout])
    robot = robot_with([server], local_tools: [build_tool(name: 'local') { |i| i }])

    robot.run('hi', mcp: :inherit, tools: %w[shout local])
    assert_equal %i[local shout], tool_keys(robot)
  end

  def test_max_tools_caps_mcp_tools_too
    server, = fake(tools: %w[a b c])
    robot = robot_with([server], config: RobotLab::RunConfig.new(max_tools: 2))

    robot.run('hi', mcp: :inherit, tools: :inherit)
    assert_equal 2, tool_keys(robot).size
  end

  def test_duplicate_tool_names_raise_with_the_fix_spelled_out
    server, = fake
    robot = robot_with([server], local_tools: [build_tool(name: 'echo') { |i| i }])

    error = assert_raises(RobotLab::MCPError) { robot.run('hi', mcp: :inherit, tools: :inherit) }
    assert_match(/more than one tool named echo/, error.message)
    assert_match(/prefix:/, error.message)
  end

  def test_prefix_resolves_duplicate_names
    server, = fake(prefix: 'fake')
    robot = robot_with([server], local_tools: [build_tool(name: 'echo') { |i| i }])

    robot.run('hi', mcp: :inherit, tools: :inherit)
    assert_equal %i[echo fake_echo], tool_keys(robot)
  end

  def test_deferred_mcp_tools_are_attached_deferred
    server, = fake(tools: %w[echo search], defer: ['search'])
    robot = robot_with([server])

    robot.run('hi', mcp: :inherit, tools: :inherit)
    assert_equal %i[echo search], tool_keys(robot)
    assert_equal %i[search], robot.chat.deferred_tools.keys
  end

  # ── failures, connect, disconnect ────────────────────────────────────────

  def test_unreachable_server_is_recorded_skipped_and_retried_next_run
    server, transport = fake('bad')
    transport.fail_with = Errno::ENOENT.new('no such server')
    robot = robot_with([server], local_tools: [build_tool(name: 'local') { |i| i }])
    script_generation(robot, text_message('one'), text_message('two'))

    robot.run('hi', mcp: :inherit, tools: :inherit)
    assert_equal %i[local], tool_keys(robot)
    assert_equal ['bad'], robot.failed_mcp_server_names
    assert_kind_of Errno::ENOENT, robot.mcp_failures['bad']

    transport.fail_with = nil
    robot.run('hi', mcp: :inherit, tools: :inherit)
    assert_equal %i[local echo], tool_keys(robot)
    assert_empty robot.failed_mcp_server_names
  end

  def test_connect_mcp_connects_build_time_servers_eagerly
    good, = fake('good')
    bad, bad_transport = fake('bad')
    bad_transport.fail_with = RubyLLM::MCP::Error.new('refused')
    robot = build_robot(name: 'bot', template: :assistant, mcp: [good, bad])

    assert_same robot, robot.connect_mcp!
    assert good.connected?
    assert_equal ['bad'], robot.failed_mcp_server_names
    assert_equal %w[good bad], robot.mcp.names
  end

  def test_mcp_tools_lists_tools_of_every_registered_server
    a, = fake('a', tools: ['one'])
    b, = fake('b', tools: ['two'])
    robot = build_robot(name: 'bot', template: :assistant).with_mcp(a, b)

    assert_equal %w[one two], robot.mcp_tools.map(&:name)
    assert_same a, robot.mcp_server_for(robot.mcp_tools.first)
    assert_nil robot.mcp_server_for(build_tool(name: 'local') { |i| i })
  end

  def test_disconnect_closes_servers_and_keeps_them_registered
    server, transport = fake
    robot = robot_with([server])
    robot.connect_mcp!

    assert_same robot, robot.disconnect
    assert_equal 1, transport.close_count
    refute server.connected?
    assert_equal ['fake'], robot.mcp.names

    robot.run('hi', mcp: :inherit, tools: :inherit)
    assert server.connected?, 'the next use reconnects'
  end

  def test_to_h_reports_server_names_and_failures
    good, = fake('good')
    bad, bad_transport = fake('bad')
    bad_transport.fail_with = IOError.new('closed')
    robot = build_robot(name: 'bot', template: :assistant, mcp: [good, bad]).connect_mcp!

    hash = robot.to_h
    assert_equal %w[good bad], hash[:mcp_servers]
    assert_equal ['bad'], hash[:mcp_failed]
    refute hash.key?(:mcp_tools)
  end

  # ── discovery ────────────────────────────────────────────────────────────

  def test_mcp_discovery_selects_servers_per_message
    fs,   = fake('filesystem', tools: ['read_file'], description: 'Read, write, and search local files and directories')
    brew, = fake('brew', tools: ['install'], description: 'Install, update, and manage macOS packages via Homebrew')
    robot = build_robot(name: 'bot', template: :assistant, mcp: [fs, brew], mcp_discovery: true)
    script_generation(robot, text_message('one'), text_message('two'))

    robot.run('install imagemagick via homebrew', mcp: :inherit, tools: :inherit)
    assert_equal %i[install], tool_keys(robot)

    robot.run('read my config file', mcp: :inherit, tools: :inherit)
    assert_equal %i[read_file], tool_keys(robot)
  end

  # ── hook bridge ──────────────────────────────────────────────────────────

  def test_tool_call_hooks_see_mcp_tool_calls_with_their_server
    server, transport = fake
    robot = build_robot(name: 'bot', template: :assistant, mcp: [server])
    script_generation(robot, tool_call_message('echo', text: 'hi'), text_message('done'))
    RobotLab.on(ObservingToolHook)

    result = robot.run('hi', mcp: :inherit, tools: :inherit)

    assert_equal [['echo', true, 'fake']], ObservingToolHook.events
    assert_equal ['echo'], transport.calls.map(&:first)
    assert_equal({ 'text' => 'hi' }, transport.calls.first.last.transform_keys(&:to_s))
    assert_equal 'echo ok', tool_messages(robot).first.content.to_s
    assert_equal 'done', result.output.last.content
  end

  def test_local_robot_lab_tools_run_their_hooks_once
    tool  = build_tool(name: 'local') { |_args| 'local ok' }
    robot = build_robot(name: 'bot', template: :assistant, local_tools: [tool])
    script_generation(robot, tool_call_message('local'), text_message('done'))
    RobotLab.on(ObservingToolHook)

    robot.run('hi', tools: :inherit)

    assert_equal [['local', false, nil]], ObservingToolHook.events
  end

  def test_mcp_error_mid_call_becomes_an_error_result
    server, transport = fake
    robot = build_robot(name: 'bot', template: :assistant, mcp: [server])
    script_generation(robot, tool_call_message('echo'), text_message('done'))
    robot.connect_mcp!
    transport.fail_with = RubyLLM::MCP::Error.new('server went away')

    robot.run('hi', mcp: :inherit, tools: :inherit)

    assert_match(/echo: server went away/, tool_messages(robot).first.content.to_s)
  end

  # ── approvals ────────────────────────────────────────────────────────────

  def test_tool_calls_requiring_approval_are_denied_by_default
    server, transport = fake(requires_approval: true)
    robot = build_robot(name: 'bot', template: :assistant, mcp: [server])
    script_generation(robot, tool_call_message('echo'), text_message('done'))

    result = robot.run('hi', mcp: :inherit, tools: :inherit)

    assert_empty transport.calls
    assert_match(/denied the echo tool call/, tool_messages(robot).first.content.to_s)
    assert_equal 'done', result.output.last.content
    refute robot.chat.waiting?
  end

  def test_tool_approval_approve_lets_them_run
    server, transport = fake(requires_approval: true)
    robot = build_robot(name: 'bot', template: :assistant, mcp: [server], tool_approval: :approve)
    script_generation(robot, tool_call_message('echo'), text_message('done'))

    robot.run('hi', mcp: :inherit, tools: :inherit)

    assert_equal ['echo'], transport.calls.map(&:first)
    assert_equal 'echo ok', tool_messages(robot).first.content.to_s
  end

  def test_on_tool_approval_decides_per_call
    server, transport = fake(tools: %w[echo shout], requires_approval: true)
    asked = []
    robot = build_robot(name: 'bot', template: :assistant, mcp: [server],
                        on_tool_approval: lambda { |call|
                          asked << call.name
                          call.name == 'shout'
                        })
    script_generation(robot, tool_call_message('echo', id: 'c1'), tool_call_message('shout', id: 'c2'), text_message('done'))

    robot.run('hi', mcp: :inherit, tools: :inherit)

    assert_equal %w[echo shout], asked
    assert_equal ['shout'], transport.calls.map(&:first)
    assert_match(/denied the echo tool call/, tool_messages(robot).first.content.to_s)
  end

  def test_tool_approval_comes_through_run_config
    server, transport = fake(requires_approval: true)
    robot = build_robot(name: 'bot', template: :assistant, mcp: [server],
                        config: RobotLab::RunConfig.new(tool_approval: :approve))
    script_generation(robot, tool_call_message('echo'), text_message('done'))

    robot.run('hi', mcp: :inherit, tools: :inherit)
    assert_equal ['echo'], transport.calls.map(&:first)
  end

  # ── input requests (elicitation) ─────────────────────────────────────────

  INPUT_REQUIRED = {
    'resultType' => 'input_required',
    'requestState' => 'state-1',
    'inputRequests' => {
      'env' => { 'method' => 'elicitation/create',
                 'params' => { 'message' => 'Which environment?',
                               'requestedSchema' => { 'type' => 'object',
                                                      'properties' => { 'environment' => { 'type' => 'string' } } } } }
    }
  }.freeze

  def asking_server
    server, transport = fake(tools: ['deploy'])
    transport.tool_results['deploy'] = lambda do |params|
      params[:inputResponses] ? { 'content' => [{ 'type' => 'text', 'text' => "deployed #{params[:inputResponses]}" }] } : INPUT_REQUIRED
    end
    [server, transport]
  end

  def test_on_input_request_answers_an_mcp_input_request
    server, transport = asking_server
    seen = []
    robot = build_robot(name: 'bot', template: :assistant, mcp: [server],
                        on_input_request: lambda { |req|
                          seen << req.message
                          { environment: 'staging' }
                        })
    script_generation(robot, tool_call_message('deploy'), text_message('done'))

    robot.run('hi', mcp: :inherit, tools: :inherit)

    assert_equal ['Which environment?'], seen
    answers = last_call_params(transport)
    assert_equal 'state-1', answers[:requestState]
    assert_equal({ 'action' => 'accept', 'content' => { 'environment' => 'staging' } },
                 answers[:inputResponses]['env'].transform_keys(&:to_s))
    assert_match(/deployed/, tool_messages(robot).first.content.to_s)
    refute robot.chat.waiting?
  end

  def test_input_requests_are_declined_without_a_handler
    server, transport = asking_server
    robot = build_robot(name: 'bot', template: :assistant, mcp: [server])
    script_generation(robot, tool_call_message('deploy'), text_message('done'))

    robot.run('hi', mcp: :inherit, tools: :inherit)

    assert_equal({ 'action' => 'decline' }, last_call_params(transport)[:inputResponses]['env'].transform_keys(&:to_s))
    refute robot.chat.waiting?
  end

  def test_settle_input_request_accepts_a_url_request_with_true
    robot = build_robot(name: 'bot', template: :assistant, on_input_request: ->(_req) { true })
    answered = []
    robot.chat.define_singleton_method(:answer) { |request, **values| answered << [request, values] }
    request = RubyLLM::MCP::InputRequest.new('k', { 'mode' => 'url', 'url' => 'https://example.com/auth' })

    robot.send(:settle_input_request, request)
    assert_equal [[request, {}]], answered
  end

  # ── tasks ────────────────────────────────────────────────────────────────

  def test_wait_for_mcp_tasks_sleeps_one_interval_and_gives_up_past_the_deadline
    robot = build_robot(name: 'bot', template: :assistant)
    task  = Struct.new(:poll_interval, :tool_call).new(0, RubyLLM::ToolCall.new(id: 't', name: 'render'))
    robot.chat.define_singleton_method(:pending_tasks) { [task] }

    deadline = robot.send(:wait_for_mcp_tasks, nil)
    assert_kind_of Float, deadline
    error = assert_raises(RobotLab::MCPError) { robot.send(:wait_for_mcp_tasks, 0.0) }
    assert error.retryable
    assert_match(/render/, error.message)
  end

  def test_wait_for_mcp_tasks_is_a_no_op_without_tasks
    robot = build_robot(name: 'bot', template: :assistant)
    assert_nil robot.send(:wait_for_mcp_tasks, nil)
  end

  # ── prompts ──────────────────────────────────────────────────────────────

  def test_run_accepts_an_mcp_prompt
    transport = FakeMCPTransport.new(name: 'p', tools: [], prompts: [{ 'name' => 'greet', 'arguments' => [] }])
    server = fake_mcp_server(name: 'p', transport: transport)
    robot = build_robot(name: 'bot', template: :assistant, mcp: [server])
    robot.learn('be brief')
    script_generation(robot, text_message('hello back'))

    result = robot.run(server.prompt('greet'), mcp: :inherit, tools: :inherit)

    assert_equal 'hello back', result.output.last.content
    assert(robot.chat.messages.any? { |m| m.role == :user && m.content.to_s.include?('prompt greet') })
  end

  def test_discovery_query_joins_prompt_messages
    transport = FakeMCPTransport.new(name: 'p', prompts: [{ 'name' => 'greet', 'arguments' => [] }])
    server = fake_mcp_server(name: 'p', transport: transport)
    robot  = build_robot(name: 'bot', template: :assistant)

    assert_equal 'prompt greet', robot.send(:discovery_query, server.prompt('greet'))
    assert_equal 'plain', robot.send(:discovery_query, 'plain')
  end
end
