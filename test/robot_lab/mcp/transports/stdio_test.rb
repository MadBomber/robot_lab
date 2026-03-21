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

  def test_close_when_connected_cleans_up
    # transports/stdio.rb lines 112-113: close body when connected
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")
    transport.instance_variable_set(:@connected, true)
    transport.instance_variable_set(:@stdin, nil)
    transport.instance_variable_set(:@stdout, nil)
    transport.instance_variable_set(:@stderr, nil)
    transport.instance_variable_set(:@wait_thread, nil)

    result = transport.close

    assert_equal transport, result
    refute transport.instance_variable_get(:@connected)
  end

  def test_send_request_raises_on_io_error
    # transports/stdio.rb lines 102-103: rescue Errno::EPIPE, IOError
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")
    transport.instance_variable_set(:@connected, true)
    transport.instance_variable_set(:@timeout, 5)

    fake_stdin = Object.new
    fake_stdin.define_singleton_method(:puts) { |_| raise IOError, "pipe broken" }
    fake_stdin.define_singleton_method(:flush) {}
    transport.instance_variable_set(:@stdin, fake_stdin)

    error = assert_raises(RobotLab::MCPError) do
      transport.send_request({ method: "test" })
    end
    assert_includes error.message, "MCP server connection lost"
    refute transport.instance_variable_get(:@connected)
  end

  def test_send_request_returns_parsed_response
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")
    transport.instance_variable_set(:@connected, true)
    transport.instance_variable_set(:@timeout, 5)

    response_json = JSON.generate({ jsonrpc: "2.0", id: 1, result: { tools: [] } })
    fake_stdin = StringIO.new
    fake_stdout = StringIO.new(response_json + "\n")
    transport.instance_variable_set(:@stdin, fake_stdin)
    transport.instance_variable_set(:@stdout, fake_stdout)

    result = transport.send_request({ jsonrpc: "2.0", id: 1, method: "tools/list" })

    assert_equal({ tools: [] }, result[:result])
  end

  def test_send_request_skips_notifications_and_returns_next
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")
    transport.instance_variable_set(:@connected, true)
    transport.instance_variable_set(:@timeout, 5)

    notification = JSON.generate({ jsonrpc: "2.0", method: "notifications/something" })
    response = JSON.generate({ jsonrpc: "2.0", id: 1, result: { ok: true } })
    fake_stdin = StringIO.new
    fake_stdout = StringIO.new(notification + "\n" + response + "\n")
    transport.instance_variable_set(:@stdin, fake_stdin)
    transport.instance_variable_set(:@stdout, fake_stdout)

    result = transport.send_request({ jsonrpc: "2.0", id: 1, method: "test" })

    assert_equal({ ok: true }, result[:result])
  end

  def test_send_request_raises_on_eof
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")
    transport.instance_variable_set(:@connected, true)
    transport.instance_variable_set(:@timeout, 5)

    fake_stdin = StringIO.new
    fake_stdout = StringIO.new  # empty — gets returns nil on EOF
    transport.instance_variable_set(:@stdin, fake_stdin)
    transport.instance_variable_set(:@stdout, fake_stdout)

    error = assert_raises(RobotLab::MCPError) do
      transport.send_request({ method: "test" })
    end
    assert_includes error.message, "EOF"
  end

  def test_send_request_raises_on_timeout
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")
    transport.instance_variable_set(:@connected, true)
    transport.instance_variable_set(:@timeout, 5)

    fake_stdin = StringIO.new
    fake_stdout = Object.new
    fake_stdout.define_singleton_method(:gets) { raise Timeout::Error }
    transport.instance_variable_set(:@stdin, fake_stdin)
    transport.instance_variable_set(:@stdout, fake_stdout)

    error = assert_raises(RobotLab::MCPError) do
      transport.send_request({ method: "test" })
    end
    assert_includes error.message, "did not respond within"
  end

  def test_connected_returns_true_with_alive_thread
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")
    transport.instance_variable_set(:@connected, true)
    fake_thread = Thread.new { sleep(10) }
    transport.instance_variable_set(:@wait_thread, fake_thread)

    assert transport.connected?
  ensure
    fake_thread&.kill
  end

  def test_connected_returns_false_with_dead_thread
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")
    transport.instance_variable_set(:@connected, true)
    fake_thread = Thread.new {}
    fake_thread.join
    transport.instance_variable_set(:@wait_thread, fake_thread)

    refute transport.connected?
  end

  def test_close_cleans_up_io_objects
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")
    transport.instance_variable_set(:@connected, true)
    transport.instance_variable_set(:@stdin, StringIO.new)
    transport.instance_variable_set(:@stdout, StringIO.new)
    transport.instance_variable_set(:@stderr, StringIO.new)
    transport.instance_variable_set(:@wait_thread, nil)

    result = transport.close

    assert_equal transport, result
    refute transport.connected?
    assert_nil transport.instance_variable_get(:@stdin)
    assert_nil transport.instance_variable_get(:@stdout)
    assert_nil transport.instance_variable_get(:@stderr)
  end

  def test_send_initialize_sends_init_and_notification
    transport = RobotLab::MCP::Transports::Stdio.new(command: "test")
    transport.instance_variable_set(:@connected, true)
    transport.instance_variable_set(:@timeout, 5)

    init_response = JSON.generate({ jsonrpc: "2.0", id: 0, result: { protocolVersion: "2024-11-05" } })
    fake_stdin = StringIO.new
    fake_stdout = StringIO.new(init_response + "\n")
    transport.instance_variable_set(:@stdin, fake_stdin)
    transport.instance_variable_set(:@stdout, fake_stdout)

    transport.send(:send_initialize)

    written = fake_stdin.string
    assert_includes written, '"method":"initialize"'
    assert_includes written, '"notifications/initialized"'
  end

  def test_connect_raises_mcp_error_on_enoent
    transport = RobotLab::MCP::Transports::Stdio.new(command: "this_command_does_not_exist_xyz_abc")

    error = assert_raises(RobotLab::MCPError) do
      transport.connect
    end
    assert_includes error.message, "not found"
    refute transport.connected?
  end

  def test_connect_happy_path_with_real_process
    # Use 'cat' which stays alive and echoes stdin; stub send_initialize to skip handshake
    transport = RobotLab::MCP::Transports::Stdio.new(command: "cat")
    transport.define_singleton_method(:send_initialize) { nil }

    result = transport.connect

    assert_equal transport, result
    assert transport.connected?
    refute_nil transport.instance_variable_get(:@stdin)
    refute_nil transport.instance_variable_get(:@stdout)
  ensure
    transport.close rescue nil
  end

  def test_connect_raises_on_timeout_during_initialize
    transport = RobotLab::MCP::Transports::Stdio.new(command: "cat")
    transport.define_singleton_method(:send_initialize) { raise Timeout::Error }

    error = assert_raises(RobotLab::MCPError) do
      transport.connect
    end
    assert_includes error.message, "did not respond within"
    refute transport.connected?
  end
end
