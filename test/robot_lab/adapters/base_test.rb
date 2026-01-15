# frozen_string_literal: true

require "test_helper"

class RobotLab::Adapters::BaseTest < Minitest::Test
  def setup
    @adapter = RobotLab::Adapters::Base.new(:test_provider)
  end

  def test_initialization_sets_provider
    assert_equal :test_provider, @adapter.provider
  end

  def test_format_messages_raises_not_implemented
    assert_raises(NotImplementedError) do
      @adapter.format_messages([])
    end
  end

  def test_parse_response_raises_not_implemented
    assert_raises(NotImplementedError) do
      @adapter.parse_response({})
    end
  end

  def test_format_tools_converts_to_json_schema
    tool1 = RobotLab::Tool.new(name: "search", description: "Search") { |i| i }
    tool2 = RobotLab::Tool.new(name: "delete", description: "Delete") { |i| i }

    result = @adapter.format_tools([tool1, tool2])

    assert_equal 2, result.size
    assert_equal "search", result[0][:name]
    assert_equal "delete", result[1][:name]
  end

  def test_format_tool_choice_auto
    result = @adapter.format_tool_choice("auto")
    assert_equal "auto", result
  end

  def test_format_tool_choice_auto_symbol
    result = @adapter.format_tool_choice(:auto)
    assert_equal "auto", result
  end

  def test_format_tool_choice_any
    result = @adapter.format_tool_choice("any")
    assert_equal "required", result
  end

  def test_format_tool_choice_specific_tool
    result = @adapter.format_tool_choice("search_tool")

    assert_equal({ type: "function", function: { name: "search_tool" } }, result)
  end

  def test_extract_system_message
    system_msg = RobotLab::TextMessage.new(role: "system", content: "You are helpful")
    user_msg = RobotLab::TextMessage.new(role: "user", content: "Hello")

    result = @adapter.extract_system_message([system_msg, user_msg])

    assert_equal "You are helpful", result
  end

  def test_extract_system_message_returns_nil_when_none
    user_msg = RobotLab::TextMessage.new(role: "user", content: "Hello")

    result = @adapter.extract_system_message([user_msg])

    assert_nil result
  end

  def test_conversation_messages_filters_system
    system_msg = RobotLab::TextMessage.new(role: "system", content: "System")
    user_msg = RobotLab::TextMessage.new(role: "user", content: "User")
    assistant_msg = RobotLab::TextMessage.new(role: "assistant", content: "Assistant")

    result = @adapter.conversation_messages([system_msg, user_msg, assistant_msg])

    assert_equal 2, result.size
    assert result.none?(&:system?)
  end
end
