# frozen_string_literal: true

require "test_helper"

class RobotLab::Adapters::GeminiTest < Minitest::Test
  def setup
    @adapter = RobotLab::Adapters::Gemini.new
  end

  def test_initialization_sets_gemini_provider
    assert_equal :gemini, @adapter.provider
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
    msg = RobotLab::TextMessage.new(role: "user", content: "Hello Gemini")

    result = @adapter.format_messages([msg])

    assert_equal "user", result[0][:role]
    assert_equal [{ text: "Hello Gemini" }], result[0][:parts]
  end

  def test_format_messages_assistant_role_maps_to_model
    msg = RobotLab::TextMessage.new(role: "assistant", content: "Hi there!")

    result = @adapter.format_messages([msg])

    assert_equal "model", result[0][:role]
    assert_equal [{ text: "Hi there!" }], result[0][:parts]
  end

  def test_format_messages_tool_call_message
    tool = RobotLab::ToolMessage.new(id: "tool_1", name: "search", input: { query: "test" })
    msg = RobotLab::ToolCallMessage.new(role: "assistant", tools: [tool])

    result = @adapter.format_messages([msg])

    assert_equal "model", result[0][:role]
    assert result[0][:parts].is_a?(Array)
    assert_equal "search", result[0][:parts][0][:functionCall][:name]
    assert_equal({ query: "test" }, result[0][:parts][0][:functionCall][:args])
  end

  def test_format_messages_tool_result_message
    tool = RobotLab::ToolMessage.new(id: "tool_1", name: "search", input: {})
    msg = RobotLab::ToolResultMessage.new(tool: tool, content: "Result data")

    result = @adapter.format_messages([msg])

    assert_equal "user", result[0][:role]
    assert_equal "search", result[0][:parts][0][:functionResponse][:name]
    assert_equal({ result: "Result data" }, result[0][:parts][0][:functionResponse][:response])
  end

  def test_format_tool_result_with_hash
    tool = RobotLab::ToolMessage.new(id: "tool_1", name: "search", input: {})
    msg = RobotLab::ToolResultMessage.new(tool: tool, content: { data: "value" })

    result = @adapter.format_messages([msg])

    # Hash passed through directly
    assert_equal({ data: "value" }, result[0][:parts][0][:functionResponse][:response])
  end

  # format_tools tests
  def test_format_tools_gemini_format
    tool = RobotLab::Tool.new(name: "search", description: "Search the web") { |i| i }

    result = @adapter.format_tools([tool])

    assert_equal 1, result.size
    assert_equal "search", result[0][:name]
    assert_equal "Search the web", result[0][:description]
    assert result[0].key?(:parameters)
  end

  def test_format_tools_removes_additional_properties
    params = {
      type: "object",
      properties: { q: { type: "string" } },
      additionalProperties: false
    }
    tool = RobotLab::Tool.new(name: "search", parameters: params) { |i| i }

    result = @adapter.format_tools([tool])

    refute result[0][:parameters].key?(:additionalProperties)
    refute result[0][:parameters].key?("additionalProperties")
  end

  def test_format_tools_cleans_nested_additional_properties
    params = {
      type: "object",
      properties: {
        nested: {
          type: "object",
          additionalProperties: false,
          properties: {}
        }
      },
      additionalProperties: false
    }
    tool = RobotLab::Tool.new(name: "search", parameters: params) { |i| i }

    result = @adapter.format_tools([tool])

    refute result[0][:parameters][:properties][:nested].key?(:additionalProperties)
  end

  # format_tool_choice tests
  def test_format_tool_choice_auto
    result = @adapter.format_tool_choice("auto")
    assert_equal({ mode: "AUTO" }, result)
  end

  def test_format_tool_choice_any
    result = @adapter.format_tool_choice("any")
    assert_equal({ mode: "ANY" }, result)
  end

  def test_format_tool_choice_none
    result = @adapter.format_tool_choice("none")
    assert_equal({ mode: "NONE" }, result)
  end

  def test_format_tool_choice_specific
    result = @adapter.format_tool_choice("search")
    assert_equal({ mode: "ANY", allowed_function_names: ["search"] }, result)
  end

  # parse_tool_arguments tests (private but important)
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

  # gemini_role tests (private)
  def test_gemini_role_maps_assistant_to_model
    result = @adapter.send(:gemini_role, "assistant")
    assert_equal "model", result
  end

  def test_gemini_role_maps_system_to_user
    result = @adapter.send(:gemini_role, "system")
    assert_equal "user", result
  end

  def test_gemini_role_passes_through_other_roles
    result = @adapter.send(:gemini_role, "user")
    assert_equal "user", result
  end

  # format_tool_result_content tests (private)
  def test_format_tool_result_content_with_hash
    result = @adapter.send(:format_tool_result_content, { data: "value" })
    assert_equal({ data: "value" }, result)
  end

  def test_format_tool_result_content_with_string
    result = @adapter.send(:format_tool_result_content, "result")
    assert_equal({ result: "result" }, result)
  end

  def test_format_tool_result_content_with_other
    result = @adapter.send(:format_tool_result_content, 123)
    assert_equal({ result: "123" }, result)
  end

  # parse_response tests using simple mock objects
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
    response = MockResponse.new(content: "Let me search for that.", tool_calls: { "call_1" => tool_call })

    result = @adapter.parse_response(response)

    assert_equal 2, result.size
    assert result[0].is_a?(RobotLab::TextMessage)
    assert_equal "tool", result[0].stop_reason
    assert result[1].is_a?(RobotLab::ToolCallMessage)
  end
end
