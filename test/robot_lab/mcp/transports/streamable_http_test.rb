# frozen_string_literal: true

require "test_helper"

class RobotLab::MCP::Transports::StreamableHTTPTest < Minitest::Test
  def test_initialization_stores_config
    config = { url: "https://server.example.com/mcp", session_id: "abc123" }
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(config)

    assert_equal "https://server.example.com/mcp", transport.config[:url]
    assert_equal "abc123", transport.session_id
  end

  def test_initialization_without_session_id
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "https://example.com/mcp")

    assert_nil transport.session_id
  end

  def test_connected_returns_false_initially
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "https://example.com/mcp")

    refute transport.connected?
  end

  def test_send_request_raises_when_not_connected
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "https://example.com/mcp")

    assert_raises(RobotLab::MCPError) do
      transport.send_request({ method: "test" })
    end
  end

  def test_close_returns_self_when_not_connected
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "https://example.com/mcp")

    result = transport.close

    assert_equal transport, result
    refute transport.connected?
  end

  def test_connect_returns_self_when_already_connected
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "https://example.com/mcp")
    transport.instance_variable_set(:@connected, true)

    result = transport.connect

    assert_equal transport, result
  end

  def test_session_id_accessor
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(
      url: "https://example.com/mcp",
      session_id: "session-xyz"
    )

    assert_equal "session-xyz", transport.session_id
  end

  def test_session_id_initially_nil
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "https://example.com/mcp")

    assert_nil transport.session_id
  end
end
