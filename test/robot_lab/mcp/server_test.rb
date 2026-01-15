# frozen_string_literal: true

require "test_helper"

class RobotLab::MCP::ServerTest < Minitest::Test
  # Initialization tests
  def test_initialization_with_stdio_transport
    server = RobotLab::MCP::Server.new(
      name: "filesystem",
      transport: { type: "stdio", command: "mcp-server-filesystem" }
    )

    assert_equal "filesystem", server.name
    assert_equal "stdio", server.transport_type
    assert_equal "mcp-server-filesystem", server.transport[:command]
  end

  def test_initialization_with_websocket_transport
    server = RobotLab::MCP::Server.new(
      name: "neon",
      transport: { type: "ws", url: "ws://localhost:8080" }
    )

    assert_equal "neon", server.name
    assert_equal "ws", server.transport_type
    assert_equal "ws://localhost:8080", server.transport[:url]
  end

  def test_initialization_with_sse_transport
    server = RobotLab::MCP::Server.new(
      name: "api",
      transport: { type: "sse", url: "http://localhost:3000/sse" }
    )

    assert_equal "sse", server.transport_type
  end

  def test_initialization_with_http_transport
    server = RobotLab::MCP::Server.new(
      name: "http_server",
      transport: { type: "http", url: "http://localhost:3000" }
    )

    assert_equal "http", server.transport_type
  end

  def test_initialization_with_streamable_http_transport
    server = RobotLab::MCP::Server.new(
      name: "stream",
      transport: { type: "streamable-http", url: "http://localhost:3000/stream" }
    )

    assert_equal "streamable-http", server.transport_type
  end

  def test_initialization_normalizes_name_to_string
    server = RobotLab::MCP::Server.new(
      name: :symbol_name,
      transport: { type: "stdio", command: "cmd" }
    )

    assert_equal "symbol_name", server.name
  end

  def test_initialization_normalizes_transport_type_to_lowercase
    server = RobotLab::MCP::Server.new(
      name: "test",
      transport: { type: "STDIO", command: "cmd" }
    )

    assert_equal "stdio", server.transport_type
  end

  def test_initialization_normalizes_string_keys_to_symbols
    server = RobotLab::MCP::Server.new(
      name: "test",
      transport: { "type" => "stdio", "command" => "my-cmd", "args" => ["--flag"] }
    )

    assert_equal "stdio", server.transport_type
    assert_equal "my-cmd", server.transport[:command]
    assert_equal ["--flag"], server.transport[:args]
  end

  # Validation tests
  def test_raises_for_invalid_transport_type
    error = assert_raises(ArgumentError) do
      RobotLab::MCP::Server.new(
        name: "test",
        transport: { type: "invalid", url: "http://localhost" }
      )
    end

    assert_includes error.message, "Invalid transport type: invalid"
    assert_includes error.message, "Must be one of:"
  end

  def test_raises_for_stdio_without_command
    error = assert_raises(ArgumentError) do
      RobotLab::MCP::Server.new(
        name: "test",
        transport: { type: "stdio" }
      )
    end

    assert_includes error.message, "StdIO transport requires :command"
  end

  def test_raises_for_websocket_without_url
    error = assert_raises(ArgumentError) do
      RobotLab::MCP::Server.new(
        name: "test",
        transport: { type: "ws" }
      )
    end

    assert_includes error.message, "Transport requires :url"
  end

  def test_raises_for_sse_without_url
    error = assert_raises(ArgumentError) do
      RobotLab::MCP::Server.new(
        name: "test",
        transport: { type: "sse" }
      )
    end

    assert_includes error.message, "Transport requires :url"
  end

  def test_raises_for_http_without_url
    error = assert_raises(ArgumentError) do
      RobotLab::MCP::Server.new(
        name: "test",
        transport: { type: "http" }
      )
    end

    assert_includes error.message, "Transport requires :url"
  end

  # Valid transport types
  def test_valid_transport_types_constant
    expected = %w[stdio sse ws websocket streamable-http http]
    assert_equal expected, RobotLab::MCP::Server::VALID_TRANSPORT_TYPES
  end

  def test_all_valid_transport_types_are_accepted
    %w[stdio sse ws websocket streamable-http http].each do |type|
      transport = if type == "stdio"
                    { type: type, command: "test-cmd" }
                  else
                    { type: type, url: "http://test" }
                  end

      server = RobotLab::MCP::Server.new(name: "test", transport: transport)
      assert_equal type, server.transport_type
    end
  end

  # Serialization
  def test_to_h_exports_server_config
    server = RobotLab::MCP::Server.new(
      name: "filesystem",
      transport: { type: "stdio", command: "mcp-fs", args: ["--root", "/data"] }
    )

    hash = server.to_h

    assert_equal "filesystem", hash[:name]
    assert_equal "stdio", hash[:transport][:type]
    assert_equal "mcp-fs", hash[:transport][:command]
    assert_equal ["--root", "/data"], hash[:transport][:args]
  end

  # Transport with args
  def test_stdio_transport_with_args
    server = RobotLab::MCP::Server.new(
      name: "fs",
      transport: {
        type: "stdio",
        command: "mcp-server-filesystem",
        args: ["--root", "/data", "--readonly"]
      }
    )

    assert_equal ["--root", "/data", "--readonly"], server.transport[:args]
  end

  # Transport type accessor
  def test_transport_type_accessor
    server = RobotLab::MCP::Server.new(
      name: "test",
      transport: { type: "websocket", url: "ws://localhost" }
    )

    assert_equal "websocket", server.transport_type
  end
end
