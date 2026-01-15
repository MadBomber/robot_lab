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
end
