# frozen_string_literal: true

require "test_helper"

class RobotLab::MCP::Transports::WebSocketTest < Minitest::Test
  def test_initialization_stores_config
    config = { url: "ws://localhost:8080" }
    transport = RobotLab::MCP::Transports::WebSocket.new(config)

    assert_equal "ws://localhost:8080", transport.config[:url]
  end

  def test_connected_returns_false_initially
    transport = RobotLab::MCP::Transports::WebSocket.new(url: "ws://localhost:8080")

    refute transport.connected?
  end

  def test_send_request_raises_when_not_connected
    transport = RobotLab::MCP::Transports::WebSocket.new(url: "ws://localhost:8080")

    assert_raises(RobotLab::MCPError) do
      transport.send_request({ method: "test" })
    end
  end

  def test_close_returns_self_when_not_connected
    transport = RobotLab::MCP::Transports::WebSocket.new(url: "ws://localhost:8080")

    result = transport.close

    assert_equal transport, result
    refute transport.connected?
  end

  def test_connect_returns_self_when_already_connected
    transport = RobotLab::MCP::Transports::WebSocket.new(url: "ws://localhost:8080")
    transport.instance_variable_set(:@connected, true)

    result = transport.connect

    assert_equal transport, result
  end

  def test_close_when_connected_disconnects
    # transports/websocket.rb lines 74-76, 78: close body when connected
    transport = RobotLab::MCP::Transports::WebSocket.new(url: "ws://localhost:8080")
    transport.instance_variable_set(:@connected, true)
    transport.instance_variable_set(:@connection, nil)

    result = transport.close

    assert_equal transport, result
    refute transport.connected?
    assert_nil transport.instance_variable_get(:@connection)
  end

  def test_close_when_connected_calls_connection_close
    transport = RobotLab::MCP::Transports::WebSocket.new(url: "ws://localhost:8080")
    transport.instance_variable_set(:@connected, true)
    closed = false
    fake_conn = Object.new
    fake_conn.define_singleton_method(:close) { closed = true }
    transport.instance_variable_set(:@connection, fake_conn)

    transport.close

    assert closed
    refute transport.connected?
    assert_nil transport.instance_variable_get(:@connection)
  end

  def test_send_request_with_fake_connection
    transport = RobotLab::MCP::Transports::WebSocket.new(url: "ws://localhost:8080")
    transport.instance_variable_set(:@connected, true)

    response_json = JSON.generate({ jsonrpc: "2.0", id: 1, result: { ok: true } })
    fake_conn = Object.new
    fake_conn.define_singleton_method(:write) { |_| nil }
    fake_conn.define_singleton_method(:flush) { nil }
    fake_conn.define_singleton_method(:read) { response_json }
    transport.instance_variable_set(:@connection, fake_conn)

    result = transport.send_request({ jsonrpc: "2.0", id: 1, method: "test" })

    assert_equal({ ok: true }, result[:result])
  end

  def test_send_request_writes_json_to_connection
    transport = RobotLab::MCP::Transports::WebSocket.new(url: "ws://localhost:8080")
    transport.instance_variable_set(:@connected, true)

    response_json = JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
    written_messages = []
    fake_conn = Object.new
    fake_conn.define_singleton_method(:write) { |msg| written_messages << msg }
    fake_conn.define_singleton_method(:flush) { nil }
    fake_conn.define_singleton_method(:read) { response_json }
    transport.instance_variable_set(:@connection, fake_conn)

    transport.send_request({ jsonrpc: "2.0", id: 1, method: "tools/list" })

    assert_equal 1, written_messages.size
    msg = JSON.parse(written_messages.first, symbolize_names: true)
    assert_equal "tools/list", msg[:method]
  end

  def test_send_initialize_sends_initialize_method
    transport = RobotLab::MCP::Transports::WebSocket.new(url: "ws://localhost:8080")
    transport.instance_variable_set(:@connected, true)

    response_json = JSON.generate({ jsonrpc: "2.0", id: 0, result: { protocolVersion: "2024-11-05" } })
    written_messages = []
    fake_conn = Object.new
    fake_conn.define_singleton_method(:write) { |msg| written_messages << msg }
    fake_conn.define_singleton_method(:flush) { nil }
    fake_conn.define_singleton_method(:read) { response_json }
    transport.instance_variable_set(:@connection, fake_conn)

    transport.send(:send_initialize)

    assert_equal 1, written_messages.size
    msg = JSON.parse(written_messages.first, symbolize_names: true)
    assert_equal "initialize", msg[:method]
    assert_equal "2024-11-05", msg.dig(:params, :protocolVersion)
  end

  def test_connect_sets_connected_with_stubbed_ws_client
    require "async/websocket/client"
    require "async/http/endpoint"

    response_json = JSON.generate({ jsonrpc: "2.0", id: 0, result: {} })
    fake_conn = Object.new
    fake_conn.define_singleton_method(:write) { |_| nil }
    fake_conn.define_singleton_method(:flush) { nil }
    fake_conn.define_singleton_method(:read) { response_json }

    original_connect = Async::WebSocket::Client.method(:connect)
    Async::WebSocket::Client.define_singleton_method(:connect) { |_endpoint| fake_conn }

    transport = RobotLab::MCP::Transports::WebSocket.new(url: "ws://localhost:8080")
    transport.define_singleton_method(:send_initialize) { nil }

    result = transport.connect

    assert_equal transport, result
    assert transport.connected?
    assert_equal fake_conn, transport.instance_variable_get(:@connection)
  ensure
    Async::WebSocket::Client.define_singleton_method(:connect) do |*args, &block|
      original_connect.call(*args, &block)
    end
  end
end
