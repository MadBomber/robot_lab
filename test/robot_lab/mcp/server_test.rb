# frozen_string_literal: true

require 'test_helper'

class RobotLab::MCP::ServerTest < Minitest::Test
  def test_is_a_ruby_llm_mcp
    assert_operator RobotLab::MCP::Server, :<, RubyLLM::MCP
  end

  def test_description_macro_sets_and_reads
    klass = Class.new(RobotLab::MCP::Server) { description 'Files on disk' }
    assert_equal 'Files on disk', klass.description
  end

  def test_description_defaults_to_nil_on_class_and_empty_on_instance
    klass = Class.new(RobotLab::MCP::Server) { command 'echo' }
    assert_nil klass.description
    assert_equal '', klass.new.description
  end

  def test_description_is_inherited_and_overridable
    parent = Class.new(RobotLab::MCP::Server) { description 'parent' }
    child  = Class.new(parent)
    assert_equal 'parent', child.description
    child.description 'child'
    assert_equal 'child', child.description
    assert_equal 'parent', parent.description
  end

  def test_ruby_llm_settings_still_inherit
    parent = Class.new(RobotLab::MCP::Server) { command 'echo', 'hi' }
    child  = Class.new(parent)
    assert_equal %w[echo hi], child.command
  end

  def test_connected_flag_follows_tools_and_close
    transport = FakeMCPTransport.new(name: 'fake', tools: [fake_tool_def('echo')])
    server = fake_mcp_server(name: 'fake', transport: transport)
    refute server.connected?
    assert_equal ['echo'], server.tools.map(&:name)
    assert server.connected?
    server.close
    refute server.connected?
    assert_equal 1, transport.close_count
  end

  def test_tools_failure_leaves_server_disconnected
    transport = FakeMCPTransport.new(name: 'fake', fail_with: RubyLLM::MCP::Error.new('boom'))
    server = fake_mcp_server(name: 'fake', transport: transport)
    assert_raises(RubyLLM::MCP::Error) { server.tools }
    refute server.connected?
  end

  def test_full_ruby_llm_surface_through_the_fake
    transport = FakeMCPTransport.new(
      name: 'fake', instructions: 'Be careful',
      tools: [fake_tool_def('echo', properties: { 'text' => { 'type' => 'string' } })],
      resources: [{ 'uri' => 'file:///a.txt', 'name' => 'a' }],
      prompts: [{ 'name' => 'greet', 'arguments' => [] }]
    )
    server = fake_mcp_server(name: 'fake', transport: transport)

    assert_equal 'echo ok', server.call(:echo, text: 'hi').text
    assert_equal [['echo', { text: 'hi' }]], transport.calls
    assert_equal ['file:///a.txt'], server.resources.map(&:uri)
    assert_equal ['greet'], server.prompts.map(&:name)
    assert_equal 'Be careful', server.instructions
    assert_kind_of RubyLLM::MCP::Prompt, server.prompt('greet')
  end
end
