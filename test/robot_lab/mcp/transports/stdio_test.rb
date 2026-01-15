# frozen_string_literal: true

require "test_helper"

class RobotLab::MCP::Transports::StdioTest < Minitest::Test
  def test_initialization_stores_config
    config = { command: "mcp-server", args: ["--help"], env: { "DEBUG" => "1" } }
    transport = RobotLab::MCP::Transports::Stdio.new(config)

    assert_equal "mcp-server", transport.config[:command]
    assert_equal ["--help"], transport.config[:args]
    assert_equal({ "DEBUG" => "1" }, transport.config[:env])
  end

  def test_initialization_defaults
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")

    refute transport.connected?
  end

  def test_connected_returns_false_initially
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")

    refute transport.connected?
  end

  def test_send_request_raises_when_not_connected
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")

    assert_raises(RobotLab::MCPError) do
      transport.send_request({ method: "test" })
    end
  end

  def test_close_returns_self_when_not_connected
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")

    result = transport.close

    assert_equal transport, result
    refute transport.connected?
  end
end
