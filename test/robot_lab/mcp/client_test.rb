# frozen_string_literal: true

require "test_helper"

# Mock transport for testing MCP client without actual connections
class MockTransport
  attr_reader :connected, :requests

  def initialize(responses: {})
    @connected = false
    @responses = responses
    @requests = []
  end

  def connect
    @connected = true
  end

  def close
    @connected = false
  end

  def send_request(message)
    @requests << message
    method = message[:method]
    @responses[method] || { result: {} }
  end
end

class RobotLab::MCP::ClientTest < Minitest::Test
  # Initialization tests
  def test_initialization_with_server_object
    server = RobotLab::MCP::Server.new(
      name: "test",
      transport: { type: "stdio", command: "test-cmd" }
    )
    client = RobotLab::MCP::Client.new(server)

    assert_equal server, client.server
    refute client.connected?
  end

  def test_initialization_with_hash_config
    client = RobotLab::MCP::Client.new(
      name: "test",
      transport: { type: "stdio", command: "test-cmd" }
    )

    assert_equal "test", client.server.name
    assert_equal "stdio", client.server.transport_type
    refute client.connected?
  end

  def test_initialization_with_string_keys
    client = RobotLab::MCP::Client.new(
      "name" => "test",
      "transport" => { "type" => "stdio", "command" => "cmd" }
    )

    assert_equal "test", client.server.name
  end

  def test_initialization_with_invalid_config_raises
    assert_raises(ArgumentError) do
      RobotLab::MCP::Client.new("invalid")
    end
  end

  # Connection tests
  def test_connect_returns_self
    client = build_mock_client
    result = client.connect

    assert_same client, result
  end

  def test_connect_sets_connected_true
    client = build_mock_client
    client.connect

    assert client.connected?
  end

  def test_connect_already_connected_returns_early
    client = build_mock_client
    client.connect

    # Verify second connect doesn't try to reconnect
    client.connect
    assert client.connected?
  end

  # Disconnect tests
  def test_disconnect_returns_self
    client = build_mock_client
    client.connect
    result = client.disconnect

    assert_same client, result
  end

  def test_disconnect_sets_connected_false
    client = build_mock_client
    client.connect
    client.disconnect

    refute client.connected?
  end

  def test_disconnect_when_not_connected_returns_early
    client = build_mock_client
    result = client.disconnect

    assert_same client, result
    refute client.connected?
  end

  # Connected? tests
  def test_connected_initially_false
    client = build_mock_client
    refute client.connected?
  end

  # Ensure connected tests
  def test_list_tools_when_not_connected_raises
    client = build_mock_client

    error = assert_raises(RobotLab::MCPError) do
      client.list_tools
    end

    assert_includes error.message, "Not connected to MCP server"
  end

  def test_call_tool_when_not_connected_raises
    client = build_mock_client

    error = assert_raises(RobotLab::MCPError) do
      client.call_tool("test", {})
    end

    assert_includes error.message, "Not connected to MCP server"
  end

  def test_list_resources_when_not_connected_raises
    client = build_mock_client

    assert_raises(RobotLab::MCPError) do
      client.list_resources
    end
  end

  def test_read_resource_when_not_connected_raises
    client = build_mock_client

    assert_raises(RobotLab::MCPError) do
      client.read_resource("test://uri")
    end
  end

  def test_list_prompts_when_not_connected_raises
    client = build_mock_client

    assert_raises(RobotLab::MCPError) do
      client.list_prompts
    end
  end

  def test_get_prompt_when_not_connected_raises
    client = build_mock_client

    assert_raises(RobotLab::MCPError) do
      client.get_prompt("test")
    end
  end

  # List tools tests
  def test_list_tools_returns_tools_array
    tools = [{ name: "search", description: "Search tool" }]
    client = build_mock_client(responses: {
      "tools/list" => { result: { tools: tools } }
    })
    client.connect

    result = client.list_tools

    assert_equal tools, result
  end

  def test_list_tools_returns_empty_array_when_no_tools
    client = build_mock_client(responses: {
      "tools/list" => { result: {} }
    })
    client.connect

    result = client.list_tools

    assert_equal [], result
  end

  # Call tool tests
  def test_call_tool_sends_correct_request
    client = build_mock_client(responses: {
      "tools/call" => { result: { content: "result" } }
    })
    client.connect
    transport = client.instance_variable_get(:@transport)

    client.call_tool("search", { query: "test" })

    request = transport.requests.last
    assert_equal "tools/call", request[:method]
    assert_equal "search", request[:params][:name]
    assert_equal({ query: "test" }, request[:params][:arguments])
  end

  def test_call_tool_returns_content
    client = build_mock_client(responses: {
      "tools/call" => { result: { content: "tool result" } }
    })
    client.connect

    result = client.call_tool("test", {})

    assert_equal "tool result", result
  end

  def test_call_tool_returns_full_response_when_no_content
    client = build_mock_client(responses: {
      "tools/call" => { result: { data: "raw data" } }
    })
    client.connect

    result = client.call_tool("test", {})

    assert_equal({ data: "raw data" }, result)
  end

  # List resources tests
  def test_list_resources_returns_resources_array
    resources = [{ uri: "file:///test.txt" }]
    client = build_mock_client(responses: {
      "resources/list" => { result: { resources: resources } }
    })
    client.connect

    result = client.list_resources

    assert_equal resources, result
  end

  # Read resource tests
  def test_read_resource_sends_correct_request
    client = build_mock_client(responses: {
      "resources/read" => { result: { contents: "file content" } }
    })
    client.connect
    transport = client.instance_variable_get(:@transport)

    client.read_resource("file:///test.txt")

    request = transport.requests.last
    assert_equal "resources/read", request[:method]
    assert_equal "file:///test.txt", request[:params][:uri]
  end

  # List prompts tests
  def test_list_prompts_returns_prompts_array
    prompts = [{ name: "greeting" }]
    client = build_mock_client(responses: {
      "prompts/list" => { result: { prompts: prompts } }
    })
    client.connect

    result = client.list_prompts

    assert_equal prompts, result
  end

  # Get prompt tests
  def test_get_prompt_sends_correct_request
    client = build_mock_client(responses: {
      "prompts/get" => { result: { messages: [] } }
    })
    client.connect
    transport = client.instance_variable_get(:@transport)

    client.get_prompt("greeting", { name: "Alice" })

    request = transport.requests.last
    assert_equal "prompts/get", request[:method]
    assert_equal "greeting", request[:params][:name]
    assert_equal({ name: "Alice" }, request[:params][:arguments])
  end

  # Serialization tests
  def test_to_h_exports_client_state
    client = build_mock_client
    client.connect

    hash = client.to_h

    assert hash[:server].is_a?(Hash)
    assert hash[:connected]
  end

  def test_to_h_when_disconnected
    client = build_mock_client
    hash = client.to_h

    refute hash[:connected]
  end

  # Request ID tests
  def test_request_id_increments
    client = build_mock_client(responses: {
      "tools/list" => { result: { tools: [] } },
      "resources/list" => { result: { resources: [] } }
    })
    client.connect
    transport = client.instance_variable_get(:@transport)

    client.list_tools
    client.list_resources

    assert_equal 1, transport.requests[0][:id]
    assert_equal 2, transport.requests[1][:id]
  end

  # Parse response tests
  def test_parse_response_handles_string_json
    client = build_mock_client
    result = client.send(:parse_response, '{"result": {"key": "value"}}')

    assert_equal({ key: "value" }, result)
  end

  def test_parse_response_handles_hash_with_result
    client = build_mock_client
    result = client.send(:parse_response, { result: { key: "value" } })

    assert_equal({ key: "value" }, result)
  end

  def test_parse_response_handles_hash_without_result
    client = build_mock_client
    result = client.send(:parse_response, { key: "value" })

    assert_equal({ key: "value" }, result)
  end

  def test_parse_response_handles_invalid_json
    client = build_mock_client
    result = client.send(:parse_response, "not valid json")

    assert_equal({ raw: "not valid json" }, result)
  end

  private

  def build_mock_client(responses: {})
    client = RobotLab::MCP::Client.new(
      name: "test",
      transport: { type: "stdio", command: "test-cmd" }
    )

    # Replace the transport creation with our mock
    transport = MockTransport.new(responses: responses)
    client.instance_variable_set(:@transport, transport)

    # Override connect to use the mock transport
    client.define_singleton_method(:connect) do
      return self if @connected

      @transport.connect
      @connected = true
      self
    end

    client
  end
end
