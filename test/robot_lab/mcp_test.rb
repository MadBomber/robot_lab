# frozen_string_literal: true

require 'test_helper'
require 'stringio'

# RobotLab::MCP factory: config Hash -> RubyLLM::MCP subclass/instance.
class RobotLab::MCPTest < Minitest::Test
  MCP = RobotLab::MCP

  def stdio(**extra)
    { name: 'fs', transport: { type: 'stdio', command: 'npx', args: ['-y', 'server-fs', '.'] } }.merge(extra)
  end

  def http(**extra)
    { name: 'linear', transport: { type: 'streamable-http', url: 'https://mcp.linear.app/mcp' } }.merge(extra)
  end

  # ── build ────────────────────────────────────────────────────────────────

  def test_build_from_hash_returns_a_server_instance
    server = MCP.build(stdio)
    assert_kind_of RubyLLM::MCP, server
    assert_kind_of MCP::Server, server
    assert_equal 'fs', server.name
  end

  def test_build_passes_an_instance_through
    server = MCP.build(stdio)
    assert_same server, MCP.build(server)
  end

  def test_build_instantiates_a_ruby_llm_mcp_subclass
    klass = Class.new(RubyLLM::MCP) { command 'echo' }
    klass.default_name = 'echo'
    server = MCP.build(klass)
    assert_instance_of klass, server
    assert_equal 'echo', server.name
  end

  def test_build_rejects_a_class_that_is_not_an_mcp
    error = assert_raises(RobotLab::MCPError) { MCP.build(String) }
    assert_match(/not a RubyLLM::MCP subclass/, error.message)
  end

  def test_build_rejects_other_objects
    error = assert_raises(RobotLab::MCPError) { MCP.build(42) }
    assert_match(/Cannot build an MCP server from Integer/, error.message)
  end

  # ── define: names and description ────────────────────────────────────────

  def test_define_requires_a_name
    error = assert_raises(RobotLab::MCPError) { MCP.define(transport: { command: 'echo' }) }
    assert_match(/no name/, error.message)
  end

  def test_define_rejects_a_blank_name
    assert_raises(RobotLab::MCPError) { MCP.define(name: '  ', transport: { command: 'echo' }) }
  end

  def test_define_accepts_string_keys
    klass = MCP.define('name' => 'fs', 'description' => 'files', 'transport' => { 'type' => 'stdio', 'command' => 'echo' })
    assert_equal 'fs', klass.default_name
    assert_equal 'files', klass.description
    assert_equal ['echo'], klass.command
  end

  def test_define_sets_description_on_the_class_and_instance
    klass = MCP.define(stdio(description: 'Local files'))
    assert_equal 'Local files', klass.description
    assert_equal 'Local files', klass.new.description
  end

  def test_define_returns_a_server_subclass
    assert_operator MCP.define(stdio), :<, MCP::Server
  end

  # ── define: stdio ────────────────────────────────────────────────────────

  def test_stdio_command_and_args_become_one_argv
    klass = MCP.define(stdio)
    assert_equal %w[npx -y server-fs .], klass.command
  end

  def test_stdio_command_may_be_an_array
    klass = MCP.define(name: 'x', transport: { command: %w[uvx mcp-server-git], args: ['--verbose'] })
    assert_equal %w[uvx mcp-server-git --verbose], klass.command
  end

  def test_stdio_env_and_directory
    klass = MCP.define(name: 'x', transport: { command: 'echo', env: { 'TOKEN' => 'abc' }, cwd: '/tmp' })
    assert_equal({ TOKEN: 'abc' }, klass.env)
    assert_equal '/tmp', klass.directory
  end

  def test_stdio_directory_key_wins_over_cwd
    klass = MCP.define(name: 'x', transport: { command: 'echo', directory: '/a', cwd: '/b' })
    assert_equal '/a', klass.directory
  end

  def test_stdio_type_is_inferred_from_command
    klass = MCP.define(name: 'x', transport: { command: 'echo' })
    assert_equal ['echo'], klass.command
    assert_nil klass.url
  end

  def test_stdio_without_command_raises
    error = assert_raises(RobotLab::MCPError) { MCP.define(name: 'x', transport: { type: 'stdio' }) }
    assert_match(/no command/, error.message)
  end

  def test_flat_shape_without_transport_key
    klass = MCP.define(name: 'x', command: 'echo', args: ['hi'], env: { A: '1' }, directory: '/tmp')
    assert_equal %w[echo hi], klass.command
    assert_equal({ A: '1' }, klass.env)
    assert_equal '/tmp', klass.directory
  end

  def test_flat_transport_string_names_the_type
    klass = MCP.define(name: 'x', transport: 'stdio', command: 'echo')
    assert_equal ['echo'], klass.command
  end

  def test_nested_transport_keys_win_over_flat_ones
    klass = MCP.define(name: 'x', command: 'outer', transport: { command: 'inner' })
    assert_equal ['inner'], klass.command
  end

  # ── define: streamable http ──────────────────────────────────────────────

  def test_http_url
    klass = MCP.define(http)
    assert_equal 'https://mcp.linear.app/mcp', klass.url
    assert_nil klass.command
  end

  def test_http_type_aliases
    MCP::HTTP_TYPES.each do |type|
      klass = MCP.define(name: 'x', transport: { type: type, url: 'https://example.com/mcp' })
      assert_equal 'https://example.com/mcp', klass.url, "type #{type}"
    end
  end

  def test_http_type_is_inferred_from_url
    klass = MCP.define(name: 'x', url: 'https://example.com/mcp')
    assert_equal 'https://example.com/mcp', klass.url
  end

  def test_http_headers_and_bearer_token
    klass = MCP.define(http(transport: { url: 'https://e.com/mcp', headers: { 'X-Team' => 'core' }, bearer_token: 'tok' }))
    assert_equal({ 'X-Team' => 'core' }, klass.headers)
    assert_equal 'tok', klass.bearer_token
  end

  def test_http_oauth_true_enables_defaults
    klass = MCP.define(http(transport: { url: 'https://e.com/mcp', oauth: true }))
    refute_nil klass.oauth_settings
  end

  def test_http_oauth_hash_passes_settings
    klass = MCP.define(http(transport: { url: 'https://e.com/mcp', oauth: { 'scopes' => ['read'] } }))
    assert_equal ['read'], klass.oauth_settings[:scopes]
  end

  def test_http_oauth_string_grant_from_yaml_is_accepted
    oauth = { 'grant' => 'client_credentials', 'client_id' => 'reports' }
    klass = MCP.define(http(transport: { url: 'https://e.com/mcp', oauth: oauth }))
    assert_equal :client_credentials, klass.oauth_settings[:grant]
  end

  def test_oauth_settings_leaves_symbol_grant_and_other_values_alone
    settings = MCP.oauth_settings(grant: :jwt_bearer, 'owner' => 'ci')
    assert_equal({ grant: :jwt_bearer, owner: 'ci' }, settings)
  end

  def test_http_oauth_unknown_string_grant_still_raises
    oauth = { 'grant' => 'password' }
    assert_raises(ArgumentError) { MCP.define(http(transport: { url: 'https://e.com/mcp', oauth: oauth })) }
  end

  def test_http_without_url_raises
    error = assert_raises(RobotLab::MCPError) { MCP.define(name: 'x', transport: { type: 'http' }) }
    assert_match(/no url/, error.message)
  end

  # ── define: unsupported / unknown / missing transports ───────────────────

  def test_sse_and_websocket_raise_with_guidance
    MCP::UNSUPPORTED_TYPES.each do |type|
      error = assert_raises(RobotLab::MCPError) { MCP.define(name: 'x', transport: { type: type, url: 'https://e.com' }) }
      assert_match(/ruby_llm 2.1 does not provide/, error.message, type)
      assert_match(/Streamable HTTP/, error.message)
    end
  end

  def test_unknown_transport_type_raises
    error = assert_raises(RobotLab::MCPError) { MCP.define(name: 'x', transport: { type: 'carrier-pigeon' }) }
    assert_match(/Unknown MCP transport type 'carrier-pigeon'/, error.message)
  end

  def test_missing_transport_entirely_raises
    error = assert_raises(RobotLab::MCPError) { MCP.define(name: 'x') }
    assert_match(/needs a command \(stdio\) or a url/, error.message)
  end

  def test_transport_object_is_installed_directly
    transport = FakeMCPTransport.new(name: 'fake', tools: [fake_tool_def('echo')])
    klass = MCP.define(name: 'fake', transport: transport)
    assert_same transport, klass.transport
    assert_equal ['echo'], klass.new.tools.map(&:name)
  end

  # ── define: tool shaping and behaviour ───────────────────────────────────

  def test_timeout_in_seconds
    assert_in_delta 30.0, MCP.define(stdio(timeout: 30)).timeout
  end

  def test_timeout_in_milliseconds_is_converted
    assert_in_delta 15.0, MCP.define(stdio(timeout: 15_000)).timeout
  end

  def test_timeout_defaults_to_ruby_llm_when_absent
    assert_nil MCP.define(stdio).timeout
  end

  def test_only_except_and_prefix
    klass = MCP.define(stdio(only: %w[read_file], except: ['rm'], prefix: 'fs'))
    assert_equal ['read_file'], klass.only
    assert_equal ['rm'], klass.except
    assert_equal 'fs', klass.prefix
  end

  def test_only_accepts_a_single_name
    assert_equal ['read_file'], MCP.define(stdio(only: 'read_file')).only
  end

  def test_requires_approval_variants
    assert_equal [[]], MCP.define(stdio(requires_approval: true)).approvals.map(&:first)
    assert_equal %w[rm mv], MCP.define(stdio(requires_approval: %w[rm mv])).approvals.first.first
    assert_equal 1, MCP.define(stdio(requires_approval: { if: :destructive? })).approvals.size
    assert_empty MCP.define(stdio(requires_approval: false)).approvals
  end

  def test_defer_variants
    assert_equal [[]], MCP.define(stdio(defer: true)).deferrals
    assert_equal [%w[search]], MCP.define(stdio(defer: 'search')).deferrals
    assert_empty MCP.define(stdio(defer: false)).deferrals
  end

  def test_log_level_and_input_requests
    klass = MCP.define(stdio(log_level: 'debug', input_requests: ['form']))
    assert_equal :debug, klass.log_level
    assert_equal [:form], klass.input_requests
  end

  def test_input_requests_false_disables_them
    assert_empty MCP.define(stdio(input_requests: false)).input_requests
  end

  def test_extensions_as_list_and_hash
    assert_includes MCP.define(stdio(extensions: ['tasks'])).extensions.keys, 'io.modelcontextprotocol/tasks'
    assert_includes MCP.define(stdio(extensions: { 'tasks' => {} })).extensions.keys, 'io.modelcontextprotocol/tasks'
    assert_includes MCP.define(stdio(extensions: ['com.example/x'])).extensions.keys, 'com.example/x'
  end

  def test_ignored_and_unknown_keys_do_not_raise
    klass = MCP.define(stdio(topics: ['files'], independent: true, group: 'dev', session_id: 's', auth_provider: 'x',
                             something_new: 1))
    assert_equal 'fs', klass.default_name
  end

  def test_unknown_keys_are_logged_at_debug
    io       = StringIO.new
    previous = RobotLab.config.logger
    RobotLab.config.logger = Logger.new(io).tap { |l| l.level = Logger::DEBUG }
    MCP.define(stdio(something_new: 1, topics: ['x']))
    assert_match(/MCP server 'fs': ignoring unknown keys something_new/, io.string)
    refute_match(/topics/, io.string)
  ensure
    RobotLab.config.logger = previous
  end

  # ── name_of / seconds ────────────────────────────────────────────────────

  def test_name_of_hash_instance_and_class
    klass = MCP.define(stdio)
    assert_equal 'fs', MCP.name_of(stdio)
    assert_equal 'fs', MCP.name_of({ 'name' => 'fs' })
    assert_equal 'fs', MCP.name_of(klass)
    assert_equal 'fs', MCP.name_of(klass.new)
    assert_equal 'sym', MCP.name_of(name: :sym)
  end

  def test_name_of_raises_without_a_name
    assert_raises(RobotLab::MCPError) { MCP.name_of({}) }
  end

  def test_seconds
    assert_in_delta 5.0,  MCP.seconds(5)
    assert_in_delta 5.0,  MCP.seconds(5000)
    assert_in_delta 1.0,  MCP.seconds(0.2)
    assert_in_delta 2.5,  MCP.seconds('2500')
    assert_in_delta 999.0, MCP.seconds(999)
  end

  # ── constants ────────────────────────────────────────────────────────────

  def test_connect_errors_cover_ruby_llm_and_os_failures
    assert_includes MCP::CONNECT_ERRORS, RubyLLM::Error
    assert_includes MCP::CONNECT_ERRORS, RubyLLM::ConfigurationError
    assert_includes MCP::CONNECT_ERRORS, SystemCallError
    assert(MCP::CONNECT_ERRORS.any? { |klass| klass >= RubyLLM::MCP::Error })
  end
end
