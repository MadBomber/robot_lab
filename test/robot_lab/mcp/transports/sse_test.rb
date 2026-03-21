# frozen_string_literal: true

require "test_helper"

class RobotLab::MCP::Transports::SSETest < Minitest::Test
  def test_initialization_stores_config
    config = { url: "http://localhost:8080/sse" }
    transport = RobotLab::MCP::Transports::SSE.new(config)

    assert_equal "http://localhost:8080/sse", transport.config[:url]
  end

  def test_connected_returns_false_initially
    transport = RobotLab::MCP::Transports::SSE.new(url: "http://localhost:8080/sse")

    refute transport.connected?
  end

  def test_send_request_raises_when_not_connected
    transport = RobotLab::MCP::Transports::SSE.new(url: "http://localhost:8080/sse")

    assert_raises(RobotLab::MCPError) do
      transport.send_request({ method: "test" })
    end
  end

  def test_close_returns_self_when_not_connected
    transport = RobotLab::MCP::Transports::SSE.new(url: "http://localhost:8080/sse")

    result = transport.close

    assert_equal transport, result
    refute transport.connected?
  end

  def test_connect_returns_self_when_already_connected
    transport = RobotLab::MCP::Transports::SSE.new(url: "http://localhost:8080/sse")
    transport.instance_variable_set(:@connected, true)

    result = transport.connect

    assert_equal transport, result
  end

  def test_close_when_connected_disconnects
    # transports/sse.rb lines 83-85: close body when connected
    transport = RobotLab::MCP::Transports::SSE.new(url: "http://localhost:8080/sse")
    transport.instance_variable_set(:@connected, true)
    transport.instance_variable_set(:@client, nil)

    result = transport.close

    assert_equal transport, result
    refute transport.connected?
    assert_nil transport.instance_variable_get(:@client)
  end

  def test_close_when_connected_calls_client_close
    transport = RobotLab::MCP::Transports::SSE.new(url: "http://localhost:8080/sse")
    transport.instance_variable_set(:@connected, true)
    closed = false
    fake_client = Object.new
    fake_client.define_singleton_method(:close) { closed = true }
    transport.instance_variable_set(:@client, fake_client)

    transport.close

    assert closed
    refute transport.connected?
    assert_nil transport.instance_variable_get(:@client)
  end

  def test_send_request_with_fake_client
    transport = RobotLab::MCP::Transports::SSE.new(url: "http://localhost:8080/sse")
    transport.instance_variable_set(:@connected, true)

    response_body = JSON.generate({ jsonrpc: "2.0", id: 1, result: { ok: true } })
    fake_response = Object.new
    fake_response.define_singleton_method(:read) { response_body }

    fake_client = Object.new
    fake_client.define_singleton_method(:post) { |*| fake_response }
    transport.instance_variable_set(:@client, fake_client)

    result = transport.send_request({ jsonrpc: "2.0", id: 1, method: "test" })

    assert_equal({ ok: true }, result[:result])
  end

  def test_send_initialize_sends_initialize_method
    transport = RobotLab::MCP::Transports::SSE.new(url: "http://localhost:8080/sse")
    transport.instance_variable_set(:@connected, true)

    response_body = JSON.generate({ jsonrpc: "2.0", id: 0, result: { protocolVersion: "2024-11-05" } })
    fake_response = Object.new
    fake_response.define_singleton_method(:read) { response_body }

    received_body = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:post) do |_url, _headers, body|
      received_body = body
      fake_response
    end
    transport.instance_variable_set(:@client, fake_client)

    transport.send(:send_initialize)

    msg = JSON.parse(received_body.first, symbolize_names: true)
    assert_equal "initialize", msg[:method]
    assert_equal "2.0", msg[:jsonrpc]
  end

  def test_connect_sets_connected_with_stubbed_initialize
    transport = RobotLab::MCP::Transports::SSE.new(url: "http://localhost:8080/sse")
    transport.define_singleton_method(:send_initialize) { nil }

    result = transport.connect

    assert_equal transport, result
    assert transport.connected?
    refute_nil transport.instance_variable_get(:@client)
  end
end
