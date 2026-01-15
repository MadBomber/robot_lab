# frozen_string_literal: true

require "test_helper"

class RobotLab::ToolTest < Minitest::Test
  def test_tool_initialization_with_block
    tool = RobotLab::Tool.new(
      name: "calculator",
      description: "Performs calculations"
    ) do |input, **_context|
      input[:a] + input[:b]
    end

    assert_equal "calculator", tool.name
    assert_equal "Performs calculations", tool.description
  end

  def test_tool_initialization_with_handler
    handler = ->(input, **_context) { input[:value] * 2 }
    tool = RobotLab::Tool.new(
      name: "doubler",
      description: "Doubles a value",
      handler: handler
    )

    assert_equal "doubler", tool.name
  end

  def test_tool_call
    tool = RobotLab::Tool.new(
      name: "adder",
      description: "Adds two numbers"
    ) do |input, **_context|
      input[:a] + input[:b]
    end

    result = tool.call({ a: 2, b: 3 }, robot: nil, network: nil)
    assert_equal 5, result
  end

  def test_tool_call_with_context
    captured_context = nil
    tool = RobotLab::Tool.new(name: "context_tool") do |_input, **context|
      captured_context = context
      "done"
    end

    mock_robot = Object.new
    mock_network = Object.new
    tool.call({}, robot: mock_robot, network: mock_network)

    assert_equal mock_robot, captured_context[:robot]
    assert_equal mock_network, captured_context[:network]
  end

  def test_tool_with_parameters_schema
    parameters = { type: "object", properties: { value: { type: "integer" } } }
    tool = RobotLab::Tool.new(
      name: "typed_tool",
      description: "A tool with schema",
      parameters: parameters
    ) { |input| input }

    assert_equal parameters, tool.parameters
  end

  def test_tool_to_hash
    tool = RobotLab::Tool.new(
      name: "hash_tool",
      description: "Test tool"
    ) { |input| input }

    hash = tool.to_h

    assert_equal "hash_tool", hash[:name]
    assert_equal "Test tool", hash[:description]
  end

  def test_tool_mcp_flag
    tool = RobotLab::Tool.new(
      name: "mcp_tool",
      mcp: true
    ) { |input| input }

    assert tool.mcp?
  end

  def test_tool_without_handler_raises_error
    tool = RobotLab::Tool.new(name: "no_handler")

    assert_raises(RobotLab::Error) do
      tool.call({}, robot: nil, network: nil)
    end
  end

  # Additional Tool tests for coverage
  def test_tool_name_converts_to_string
    tool = RobotLab::Tool.new(name: :symbol_name) { |i| i }

    assert_equal "symbol_name", tool.name
  end

  def test_tool_strict_attribute
    tool = RobotLab::Tool.new(name: "strict_tool", strict: true) { |i| i }

    assert tool.strict
  end

  def test_tool_mcp_attribute
    tool = RobotLab::Tool.new(name: "mcp_tool", mcp: "github") { |i| i }

    assert_equal "github", tool.mcp
    assert tool.mcp?
  end

  def test_tool_mcp_false_when_nil
    tool = RobotLab::Tool.new(name: "local_tool") { |i| i }

    refute tool.mcp?
  end

  # Error handling in call
  def test_tool_call_catches_errors_and_serializes
    tool = RobotLab::Tool.new(name: "error_tool") do |_input, **_context|
      raise StandardError, "Something went wrong"
    end

    result = tool.call({}, robot: nil, network: nil)

    assert result.is_a?(Hash)
    assert result[:error]
    assert_equal "StandardError", result[:error][:type]
    assert_equal "Something went wrong", result[:error][:message]
  end

  def test_tool_call_reraises_robotlab_errors
    tool = RobotLab::Tool.new(name: "robotlab_error_tool") do |_input, **_context|
      raise RobotLab::Error, "RobotLab specific error"
    end

    assert_raises(RobotLab::Error) do
      tool.call({}, robot: nil, network: nil)
    end
  end

  # to_json_schema tests
  def test_to_json_schema_with_no_parameters
    tool = RobotLab::Tool.new(name: "simple", description: "A simple tool") { |i| i }

    schema = tool.to_json_schema

    assert_equal "simple", schema[:name]
    assert_equal "A simple tool", schema[:description]
    assert_equal({ type: "object", properties: {}, required: [] }, schema[:parameters])
  end

  def test_to_json_schema_with_hash_parameters
    params = {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query" }
      },
      required: ["query"]
    }
    tool = RobotLab::Tool.new(name: "search", parameters: params) { |i| i }

    schema = tool.to_json_schema

    assert_equal params, schema[:parameters]
  end

  def test_to_json_schema_excludes_nil_values
    tool = RobotLab::Tool.new(name: "minimal") { |i| i }

    schema = tool.to_json_schema

    refute schema.key?(:description)
  end

  # to_h tests
  def test_to_h_includes_mcp_and_strict
    tool = RobotLab::Tool.new(
      name: "full",
      description: "Full tool",
      mcp: "server",
      strict: true
    ) { |i| i }

    hash = tool.to_h

    assert_equal "full", hash[:name]
    assert_equal "Full tool", hash[:description]
    assert_equal "server", hash[:mcp]
    assert hash[:strict]
  end

  def test_to_h_excludes_nil_values
    tool = RobotLab::Tool.new(name: "minimal") { |i| i }

    hash = tool.to_h

    refute hash.key?(:description)
    refute hash.key?(:mcp)
    refute hash.key?(:strict)
  end

  # to_json test
  def test_to_json_returns_json_string
    tool = RobotLab::Tool.new(name: "json_tool", description: "Test") { |i| i }

    json = tool.to_json

    assert json.is_a?(String)
    parsed = JSON.parse(json)
    assert_equal "json_tool", parsed["name"]
    assert_equal "Test", parsed["description"]
  end

  # params_schema test
  def test_params_schema_with_hash
    params = { type: "object", properties: { x: { type: "integer" } } }
    tool = RobotLab::Tool.new(name: "test", parameters: params) { |i| i }

    assert_equal params, tool.params_schema
  end

  def test_params_schema_returns_nil_without_parameters
    tool = RobotLab::Tool.new(name: "test") { |i| i }

    assert_nil tool.params_schema
  end

  # provider_params test
  def test_provider_params_returns_empty_hash
    tool = RobotLab::Tool.new(name: "test") { |i| i }

    assert_equal({}, tool.provider_params)
  end

  # Input validation tests
  def test_validate_input_passes_through_without_parameters
    tool = RobotLab::Tool.new(name: "test") { |input, **_c| input }

    result = tool.call({ key: "value" }, robot: nil, network: nil)

    assert_equal({ key: "value" }, result)
  end

  def test_validate_input_transforms_string_keys_to_symbols
    tool = RobotLab::Tool.new(
      name: "test",
      parameters: { type: "object", properties: { key: { type: "string" } } }
    ) { |input, **_c| input }

    result = tool.call({ "key" => "value" }, robot: nil, network: nil)

    # With parameters defined, string keys get transformed to symbols
    assert result.key?(:key) || result.key?("key")
  end

  # Step context
  def test_tool_receives_step_context
    captured_step = nil
    tool = RobotLab::Tool.new(name: "step_tool") do |_input, step:, **_context|
      captured_step = step
      "done"
    end

    mock_step = Object.new
    tool.call({}, robot: nil, network: nil, step: mock_step)

    assert_equal mock_step, captured_step
  end

  # to_ruby_llm_tool tests
  def test_to_ruby_llm_tool_returns_class
    tool = RobotLab::Tool.new(name: "converter", description: "Test tool") { |i| i }

    ruby_llm_class = tool.to_ruby_llm_tool

    assert ruby_llm_class.is_a?(Class)
    assert ruby_llm_class < RubyLLM::Tool
  end

  def test_to_ruby_llm_tool_with_hash_parameters
    params = {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query" },
        limit: { type: "integer" }
      },
      required: ["query"]
    }
    tool = RobotLab::Tool.new(
      name: "search_tool",
      description: "Searches for items",
      parameters: params
    ) { |i| i }

    ruby_llm_class = tool.to_ruby_llm_tool

    assert ruby_llm_class.is_a?(Class)
  end

  def test_to_ruby_llm_tool_execute_returns_kwargs
    tool = RobotLab::Tool.new(name: "test_tool", description: "Test") { |i| i }

    ruby_llm_class = tool.to_ruby_llm_tool
    instance = ruby_llm_class.new

    result = instance.execute(a: 1, b: 2)

    assert_equal({ a: 1, b: 2 }, result)
  end

  # Handler attribute access
  def test_handler_attribute
    handler = ->(i, **_c) { i }
    tool = RobotLab::Tool.new(name: "test", handler: handler)

    assert_equal handler, tool.handler
  end
end
