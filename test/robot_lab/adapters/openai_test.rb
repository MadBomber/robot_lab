# frozen_string_literal: true

require "test_helper"

class RobotLab::Adapters::OpenAITest < Minitest::Test
  def setup
    @adapter = RobotLab::Adapters::OpenAI.new
  end

  def test_initialization_sets_openai_provider
    assert_equal :openai, @adapter.provider
  end

  # format_messages tests
  def test_format_messages_includes_system_message
    system_msg = RobotLab::TextMessage.new(role: "system", content: "System prompt")
    user_msg = RobotLab::TextMessage.new(role: "user", content: "Hello")

    result = @adapter.format_messages([system_msg, user_msg])

    assert_equal 2, result.size
    assert_equal "system", result[0][:role]
  end

  def test_format_messages_text_message
    msg = RobotLab::TextMessage.new(role: "user", content: "Hello GPT")

    result = @adapter.format_messages([msg])

    assert_equal "user", result[0][:role]
    assert_equal "Hello GPT", result[0][:content]
  end

  def test_format_messages_tool_call_message
    tool = RobotLab::ToolMessage.new(id: "call_1", name: "search", input: { query: "test" })
    msg = RobotLab::ToolCallMessage.new(role: "assistant", tools: [tool])

    result = @adapter.format_messages([msg])

    assert_equal "assistant", result[0][:role]
    assert_nil result[0][:content]
    assert result[0][:tool_calls].is_a?(Array)
    assert_equal "call_1", result[0][:tool_calls][0][:id]
    assert_equal "function", result[0][:tool_calls][0][:type]
    assert_equal "search", result[0][:tool_calls][0][:function][:name]
  end

  def test_format_messages_tool_result_message
    tool = RobotLab::ToolMessage.new(id: "call_1", name: "search", input: {})
    msg = RobotLab::ToolResultMessage.new(tool: tool, content: "Result")

    result = @adapter.format_messages([msg])

    assert_equal "tool", result[0][:role]
    assert_equal "call_1", result[0][:tool_call_id]
    assert_equal "Result", result[0][:content]
  end

  def test_format_tool_result_with_hash
    tool = RobotLab::ToolMessage.new(id: "call_1", name: "search", input: {})
    msg = RobotLab::ToolResultMessage.new(tool: tool, content: { data: "value" })

    result = @adapter.format_messages([msg])

    # Hash gets JSON encoded
    assert result[0][:content].is_a?(String)
    assert result[0][:content].include?("data")
  end

  # format_tools tests
  def test_format_tools_openai_function_format
    tool = RobotLab::Tool.new(name: "search", description: "Search") { |i| i }

    result = @adapter.format_tools([tool])

    assert_equal 1, result.size
    assert_equal "function", result[0][:type]
    assert_equal "search", result[0][:function][:name]
    assert_equal "Search", result[0][:function][:description]
  end

  def test_format_tools_includes_strict_by_default
    tool = RobotLab::Tool.new(name: "search") { |i| i }

    result = @adapter.format_tools([tool])

    assert result[0][:function][:strict]
  end

  def test_format_tools_respects_strict_false
    tool = RobotLab::Tool.new(name: "search", strict: false) { |i| i }

    result = @adapter.format_tools([tool])

    refute result[0][:function][:strict]
  end

  # format_tool_choice tests
  def test_format_tool_choice_auto
    result = @adapter.format_tool_choice("auto")
    assert_equal "auto", result
  end

  def test_format_tool_choice_any
    result = @adapter.format_tool_choice("any")
    assert_equal "required", result
  end

  def test_format_tool_choice_none
    result = @adapter.format_tool_choice("none")
    assert_equal "none", result
  end

  def test_format_tool_choice_specific
    result = @adapter.format_tool_choice("search")

    assert_equal "function", result[:type]
    assert_equal "search", result[:function][:name]
  end

  # parse_tool_arguments tests
  def test_parse_tool_arguments_with_json_string
    result = @adapter.send(:parse_tool_arguments, '{"query": "test"}')

    assert_equal({ query: "test" }, result)
  end

  def test_parse_tool_arguments_removes_backtick_wrapper
    # OpenAI sometimes wraps JSON in backticks
    result = @adapter.send(:parse_tool_arguments, "```json\n{\"query\": \"test\"}\n```")

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
    response = MockResponse.new(content: "Hello GPT!", tool_calls: nil)

    result = @adapter.parse_response(response)

    assert_equal 1, result.size
    assert result[0].is_a?(RobotLab::TextMessage)
    assert_equal "Hello GPT!", result[0].content
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
    response = MockResponse.new(content: "Searching now.", tool_calls: { "call_1" => tool_call })

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
