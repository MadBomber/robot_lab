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

  def test_close_when_connected_closes_client
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "https://example.com/mcp")
    transport.instance_variable_set(:@connected, true)
    closed = false
    fake_client = Object.new
    fake_client.define_singleton_method(:close) { closed = true }
    transport.instance_variable_set(:@client, fake_client)

    result = transport.close

    assert_equal transport, result
    assert closed
    refute transport.connected?
    assert_nil transport.instance_variable_get(:@client)
  end

  def test_send_request_with_fake_client
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "https://example.com/mcp")
    transport.instance_variable_set(:@connected, true)

    response_body = JSON.generate({ jsonrpc: "2.0", id: 1, result: { ok: true } })
    fake_response = Object.new
    fake_response.define_singleton_method(:read) { response_body }

    received_headers = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:post) do |_url, headers, _body|
      received_headers = headers
      fake_response
    end
    transport.instance_variable_set(:@client, fake_client)

    result = transport.send_request({ jsonrpc: "2.0", id: 1, method: "test" })

    assert_equal({ ok: true }, result[:result])
    assert_equal "application/json", received_headers["Content-Type"]
    assert_equal "application/json", received_headers["Accept"]
  end

  def test_send_request_includes_session_id_header
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(
      url: "https://example.com/mcp",
      session_id: "test-session-123"
    )
    transport.instance_variable_set(:@connected, true)

    response_body = JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
    fake_response = Object.new
    fake_response.define_singleton_method(:read) { response_body }

    received_headers = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:post) do |_url, headers, _body|
      received_headers = headers
      fake_response
    end
    transport.instance_variable_set(:@client, fake_client)

    transport.send_request({ jsonrpc: "2.0", id: 1, method: "test" })

    assert_equal "test-session-123", received_headers["X-Session-ID"]
  end

  def test_send_request_omits_session_id_header_when_nil
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "https://example.com/mcp")
    transport.instance_variable_set(:@connected, true)

    response_body = JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
    fake_response = Object.new
    fake_response.define_singleton_method(:read) { response_body }

    received_headers = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:post) do |_url, headers, _body|
      received_headers = headers
      fake_response
    end
    transport.instance_variable_set(:@client, fake_client)

    transport.send_request({ jsonrpc: "2.0", id: 1, method: "test" })

    refute received_headers.key?("X-Session-ID")
  end

  def test_send_request_includes_auth_header_from_auth_provider
    auth_provider = -> { "Bearer token123" }
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(
      url: "https://example.com/mcp",
      auth_provider: auth_provider
    )
    transport.instance_variable_set(:@connected, true)

    response_body = JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
    fake_response = Object.new
    fake_response.define_singleton_method(:read) { response_body }

    received_headers = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:post) do |_url, headers, _body|
      received_headers = headers
      fake_response
    end
    transport.instance_variable_set(:@client, fake_client)

    transport.send_request({ jsonrpc: "2.0", id: 1, method: "test" })

    assert_equal "Bearer token123", received_headers["Authorization"]
  end

  def test_send_request_no_auth_header_without_auth_provider
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "https://example.com/mcp")
    transport.instance_variable_set(:@connected, true)

    response_body = JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
    fake_response = Object.new
    fake_response.define_singleton_method(:read) { response_body }

    received_headers = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:post) do |_url, headers, _body|
      received_headers = headers
      fake_response
    end
    transport.instance_variable_set(:@client, fake_client)

    transport.send_request({ jsonrpc: "2.0", id: 1, method: "test" })

    refute received_headers.key?("Authorization")
  end

  def test_send_initialize_sends_initialize_method
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "https://example.com/mcp")
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
    assert_equal "2024-11-05", msg.dig(:params, :protocolVersion)
  end

  def test_connect_sets_connected_with_stubbed_initialize
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "http://localhost:8080/mcp")
    transport.define_singleton_method(:send_initialize) { nil }

    result = transport.connect

    assert_equal transport, result
    assert transport.connected?
    refute_nil transport.instance_variable_get(:@client)
  end

  def test_connect_sets_session_id_from_server_response
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(url: "http://localhost:8080/mcp")
    transport.define_singleton_method(:send_initialize) do
      { serverInfo: { sessionId: "server-generated-session" } }
    end

    transport.connect

    assert_equal "server-generated-session", transport.session_id
  end

  def test_connect_does_not_override_existing_session_id
    transport = RobotLab::MCP::Transports::StreamableHTTP.new(
      url: "http://localhost:8080/mcp",
      session_id: "existing-session"
    )
    transport.define_singleton_method(:send_initialize) do
      { serverInfo: { sessionId: "server-generated-session" } }
    end

    transport.connect

    assert_equal "existing-session", transport.session_id
  end
end
