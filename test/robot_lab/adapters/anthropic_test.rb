# frozen_string_literal: true

require "test_helper"

class RobotLab::Adapters::AnthropicTest < Minitest::Test
  def setup
    @adapter = RobotLab::Adapters::Anthropic.new
  end

  def test_initialization_sets_anthropic_provider
    assert_equal :anthropic, @adapter.provider
  end

  # format_messages tests
  def test_format_messages_excludes_system_messages
    system_msg = RobotLab::TextMessage.new(role: "system", content: "System")
    user_msg = RobotLab::TextMessage.new(role: "user", content: "Hello")

    result = @adapter.format_messages([system_msg, user_msg])

    assert_equal 1, result.size
    assert_equal "user", result[0][:role]
  end

  def test_format_messages_text_message
    msg = RobotLab::TextMessage.new(role: "user", content: "Hello Claude")

    result = @adapter.format_messages([msg])

    assert_equal 1, result.size
    assert_equal "user", result[0][:role]
    assert_equal "Hello Claude", result[0][:content]
  end

  def test_format_messages_assistant_message
    msg = RobotLab::TextMessage.new(role: "assistant", content: "Hi there!")

    result = @adapter.format_messages([msg])

    assert_equal "assistant", result[0][:role]
    assert_equal "Hi there!", result[0][:content]
  end

  def test_format_messages_tool_call_message
    tool = RobotLab::ToolMessage.new(id: "tool_1", name: "search", input: { query: "test" })
    msg = RobotLab::ToolCallMessage.new(role: "assistant", tools: [tool])

    result = @adapter.format_messages([msg])

    assert_equal "assistant", result[0][:role]
    assert result[0][:content].is_a?(Array)
    assert_equal "tool_use", result[0][:content][0][:type]
    assert_equal "tool_1", result[0][:content][0][:id]
    assert_equal "search", result[0][:content][0][:name]
  end

  def test_format_messages_tool_result_message
    tool = RobotLab::ToolMessage.new(id: "tool_1", name: "search", input: {})
    msg = RobotLab::ToolResultMessage.new(tool: tool, content: "Result data")

    result = @adapter.format_messages([msg])

    assert_equal "user", result[0][:role]
    assert_equal "tool_result", result[0][:content][0][:type]
    assert_equal "tool_1", result[0][:content][0][:tool_use_id]
    assert_equal "Result data", result[0][:content][0][:content]
  end

  def test_format_tool_result_with_hash_data
    tool = RobotLab::ToolMessage.new(id: "tool_1", name: "search", input: {})
    msg = RobotLab::ToolResultMessage.new(tool: tool, content: { data: "result" })

    result = @adapter.format_messages([msg])

    assert_equal "result", result[0][:content][0][:content]
  end

  def test_format_tool_result_with_hash_object_data
    tool = RobotLab::ToolMessage.new(id: "tool_1", name: "search", input: {})
    msg = RobotLab::ToolResultMessage.new(tool: tool, content: { data: { key: "value" } })

    result = @adapter.format_messages([msg])

    # Complex data gets JSON encoded
    assert result[0][:content][0][:content].is_a?(String)
  end

  def test_format_tool_result_with_error
    tool = RobotLab::ToolMessage.new(id: "tool_1", name: "search", input: {})
    msg = RobotLab::ToolResultMessage.new(tool: tool, content: { error: { type: "Error", message: "Failed" } })

    result = @adapter.format_messages([msg])

    # Error content gets JSON encoded
    content = result[0][:content][0][:content]
    assert content.include?("error")
  end

  # format_tools tests
  def test_format_tools_anthropic_format
    tool = RobotLab::Tool.new(name: "search", description: "Search the web") { |i| i }

    result = @adapter.format_tools([tool])

    assert_equal 1, result.size
    assert_equal "search", result[0][:name]
    assert_equal "Search the web", result[0][:description]
    assert result[0].key?(:input_schema)
  end

  def test_format_tools_includes_input_schema
    params = { type: "object", properties: { q: { type: "string" } }, required: ["q"] }
    tool = RobotLab::Tool.new(name: "search", parameters: params) { |i| i }

    result = @adapter.format_tools([tool])

    assert_equal params, result[0][:input_schema]
  end

  # format_tool_choice tests
  def test_format_tool_choice_auto
    result = @adapter.format_tool_choice("auto")
    assert_equal({ type: "auto" }, result)
  end

  def test_format_tool_choice_any
    result = @adapter.format_tool_choice("any")
    assert_equal({ type: "any" }, result)
  end

  def test_format_tool_choice_specific
    result = @adapter.format_tool_choice("search")
    assert_equal({ type: "tool", name: "search" }, result)
  end

  # parse_tool_arguments tests
  def test_parse_tool_arguments_with_json_string
    result = @adapter.send(:parse_tool_arguments, '{"query": "test"}')

    assert_equal({ query: "test" }, result)
  end

  def test_parse_tool_arguments_with_invalid_json
    result = @adapter.send(:parse_tool_arguments, "not json")

    assert_equal({ raw: "not json" }, result)
  end

  def test_parse_tool_arguments_with_hash
    result = @adapter.send(:parse_tool_arguments, { "query" => "test" })

    assert_equal({ query: "test" }, result)
  end

  def test_parse_tool_arguments_with_nil
    result = @adapter.send(:parse_tool_arguments, nil)

    assert_equal({}, result)
  end

  # Mock classes for parse_response tests
  class MockToolCall
    attr_reader :name, :arguments

    def initialize(name:, arguments:)
      @name = name
      @arguments = arguments
    end
  end

  class MockResponse
    attr_reader :content, :tool_calls

    def initialize(content:, tool_calls:)
      @content = content
      @tool_calls = tool_calls
    end
  end

  # parse_response tests
  def test_parse_response_with_text_content
    response = MockResponse.new(content: "Hello!", tool_calls: nil)

    result = @adapter.parse_response(response)

    assert_equal 1, result.size
    assert result[0].is_a?(RobotLab::TextMessage)
    assert_equal "Hello!", result[0].content
    assert_equal "stop", result[0].stop_reason
  end

  def test_parse_response_with_tool_calls
    tool_call = MockToolCall.new(name: "search", arguments: { query: "test" })
    response = MockResponse.new(content: "", tool_calls: { "call_1" => tool_call })

    result = @adapter.parse_response(response)

    assert_equal 1, result.size
    assert result[0].is_a?(RobotLab::ToolCallMessage)
    assert_equal 1, result[0].tools.size
    assert_equal "search", result[0].tools[0].name
  end

  def test_parse_response_with_text_and_tool_calls
    tool_call = MockToolCall.new(name: "search", arguments: { query: "test" })
    response = MockResponse.new(content: "Let me search.", tool_calls: { "call_1" => tool_call })

    result = @adapter.parse_response(response)

    assert_equal 2, result.size
    assert result[0].is_a?(RobotLab::TextMessage)
    assert_equal "tool", result[0].stop_reason
    assert result[1].is_a?(RobotLab::ToolCallMessage)
  end

  def test_parse_response_empty
    response = MockResponse.new(content: "", tool_calls: nil)

    result = @adapter.parse_response(response)

    assert_empty result
  end
end
