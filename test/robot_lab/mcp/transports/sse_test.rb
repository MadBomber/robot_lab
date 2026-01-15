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
end
