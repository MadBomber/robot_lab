# frozen_string_literal: true

require 'test_helper'

class RobotLab::MCP::RegistryTest < Minitest::Test
  def setup
    @registry = RobotLab::MCP::Registry.new
  end

  def spec(name = 'fs', **extra)
    { name: name, transport: { type: 'stdio', command: 'echo' } }.merge(extra)
  end

  def test_starts_empty
    assert @registry.empty?
    assert_equal 0, @registry.size
    assert_equal [], @registry.names
    assert_nil @registry['fs']
  end

  def test_add_hash_builds_a_server
    server = @registry.add(spec)
    assert_kind_of RubyLLM::MCP, server
    assert_same server, @registry['fs']
    assert_same server, @registry[:fs]
    assert @registry.key?('fs')
    assert_equal ['fs'], @registry.names
  end

  def test_add_same_hash_again_returns_the_existing_server
    first  = @registry.add(spec)
    second = @registry.add(spec)
    assert_same first, second
    assert_equal 1, @registry.size
  end

  def test_add_different_hash_under_same_name_replaces_and_closes_the_old
    transport = FakeMCPTransport.new(name: 'fs')
    old = @registry.add(name: 'fs', transport: transport)
    old.tools
    new = @registry.add(spec('fs', timeout: 5))
    refute_same old, new
    assert_equal 1, transport.close_count
    assert_same new, @registry['fs']
  end

  def test_add_instance_registers_it_as_is
    server = fake_mcp_server(name: 'fake')
    assert_same server, @registry.add(server)
    assert_same server, @registry.add(server)
    assert_equal ['fake'], @registry.names
  end

  def test_add_different_instance_with_same_name_replaces
    transport = FakeMCPTransport.new(name: 'fake')
    first  = fake_mcp_server(name: 'fake', transport: transport)
    second = fake_mcp_server(name: 'fake')
    @registry.add(first).tools
    assert_same second, @registry.add(second)
    assert_equal 1, transport.close_count
  end

  def test_add_class_instantiates_once
    klass = RobotLab::MCP.define(spec('cls'))
    first = @registry.add(klass)
    assert_instance_of klass, first
    assert_same first, @registry.add(klass)
  end

  def test_add_raises_for_nameless_spec
    assert_raises(RobotLab::MCPError) { @registry.add({}) }
    assert @registry.empty?
  end

  def test_each_and_enumerable
    a = @registry.add(spec('a'))
    b = @registry.add(spec('b'))
    assert_equal [a, b], @registry.to_a
    assert_equal %w[a b], @registry.map(&:name)
  end

  def test_delete_closes_and_removes
    transport = FakeMCPTransport.new(name: 'fake')
    server = @registry.add(fake_mcp_server(name: 'fake', transport: transport))
    server.tools
    assert_same server, @registry.delete('fake')
    assert_equal 1, transport.close_count
    refute @registry.key?('fake')
    assert_nil @registry.delete('fake')
  end

  def test_delete_never_connected_server_is_safe
    @registry.add(spec)
    assert_kind_of RubyLLM::MCP, @registry.delete('fs')
    assert @registry.empty?
  end

  def test_delete_forgets_the_spec_so_readding_rebuilds
    first = @registry.add(spec)
    @registry.delete(:fs)
    refute_same first, @registry.add(spec)
  end

  def test_clear_closes_everything
    transports = %w[a b].map { |n| FakeMCPTransport.new(name: n) }
    transports.each { |t| @registry.add(fake_mcp_server(name: t.name, transport: t)).tools }
    assert_same @registry, @registry.clear
    assert @registry.empty?
    assert_equal [1, 1], transports.map(&:close_count)
  end
end
