# frozen_string_literal: true

require "test_helper"

class RobotLab::MCP::ConnectionPollerTest < Minitest::Test
  def setup
    @poller = RobotLab::MCP::ConnectionPoller.new
  end

  def teardown
    @poller.stop(timeout: 1) rescue nil
  end

  # Lifecycle
  def test_not_running_before_start
    refute @poller.running?
  end

  def test_running_after_start
    @poller.start
    assert @poller.running?
  end

  def test_start_returns_self
    assert_same @poller, @poller.start
  end

  def test_stop_returns_self
    @poller.start
    assert_same @poller, @poller.stop
  end

  def test_not_running_after_stop
    @poller.start
    @poller.stop
    refute @poller.running?
  end

  def test_start_idempotent
    @poller.start
    @poller.start
    assert @poller.running?
  end

  def test_stop_when_not_running_returns_self
    assert_same @poller, @poller.stop
  end

  # Register / unregister — non-stdio clients are ignored
  def test_register_ignores_non_stdio_client
    client = Object.new
    client.define_singleton_method(:transport) { nil }
    @poller.start
    @poller.register(client)  # should not raise

    assert_equal 0, @poller.instance_variable_get(:@clients).size
  end

  def test_register_ignores_client_without_transport_method
    client = Object.new
    @poller.start
    @poller.register(client)  # should not raise

    assert_equal 0, @poller.instance_variable_get(:@clients).size
  end

  def test_unregister_ignores_non_stdio_client
    client = Object.new
    client.define_singleton_method(:transport) { nil }
    @poller.start
    @poller.unregister(client)  # should not raise
  end

  # send_request tests use two separate pipe pairs:
  #   stdin_r/stdin_w  — send_request writes the message to stdin_w (stdin_r ignored)
  #   stdout_r/stdout_w — poller reads from stdout_r; test writes response to stdout_w
  # This avoids the request looping back to the poller via the same pipe.
  # stdio_client? is bypassed by injecting directly into @clients.

  def test_send_request_returns_response_from_queue
    @poller.start

    stdin_r,  stdin_w  = IO.pipe   # send_request writes here; we discard stdin_r
    stdout_r, stdout_w = IO.pipe   # poller reads from stdout_r; test writes to stdout_w

    transport = build_pipe_transport(stdout_r, stdin_w)
    client    = build_mock_stdio_client(transport)

    @poller.instance_variable_get(:@clients)[stdout_r] = { client: client, queue: nil }

    response = { jsonrpc: "2.0", id: 1, result: { tools: [] } }

    # Simulate the server writing its response after a short delay
    Thread.new do
      sleep 0.05
      stdout_w.puts(response.to_json)
    end

    result = @poller.send_request(client, { jsonrpc: "2.0", id: 1, method: "tools/list" }, timeout: 2)

    assert_equal response, result
  ensure
    [stdin_r, stdin_w, stdout_r, stdout_w].each { |io| io.close rescue nil }
  end

  def test_send_request_raises_on_timeout
    @poller.start

    stdin_r,  stdin_w  = IO.pipe
    stdout_r, stdout_w = IO.pipe

    transport = build_pipe_transport(stdout_r, stdin_w)
    client    = build_mock_stdio_client(transport)

    @poller.instance_variable_get(:@clients)[stdout_r] = { client: client, queue: nil }

    # Nothing written to stdout_w — should time out
    assert_raises(RobotLab::MCPError) do
      @poller.send_request(client, { jsonrpc: "2.0", id: 1, method: "tools/list" }, timeout: 0.05)
    end
  ensure
    [stdin_r, stdin_w, stdout_r, stdout_w].each { |io| io.close rescue nil }
  end

  def test_stop_cancels_pending_requests
    @poller.start

    stdin_r,  stdin_w  = IO.pipe
    stdout_r, stdout_w = IO.pipe

    transport = build_pipe_transport(stdout_r, stdin_w)
    client    = build_mock_stdio_client(transport)

    @poller.instance_variable_get(:@clients)[stdout_r] = { client: client, queue: nil }

    error_holder = nil
    thr = Thread.new do
      @poller.send_request(client, { jsonrpc: "2.0", id: 1, method: "tools/list" }, timeout: 5)
    rescue RobotLab::MCPError => e
      error_holder = e
    end

    sleep 0.05
    @poller.stop(timeout: 1)
    thr.join(2)

    assert_instance_of RobotLab::MCPError, error_holder
  ensure
    [stdin_r, stdin_w, stdout_r, stdout_w].each { |io| io.close rescue nil }
  end

  private

  def build_pipe_transport(stdout_io, stdin_io)
    transport = Object.new
    transport.define_singleton_method(:stdout) { stdout_io }
    transport.define_singleton_method(:stdin)  { stdin_io }
    transport
  end

  def build_mock_stdio_client(transport)
    client = Object.new
    client.define_singleton_method(:transport) { transport }
    client.define_singleton_method(:respond_to?) do |m, *|
      m == :transport ? true : super(m)
    end
    client
  end
end
