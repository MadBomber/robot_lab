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
end
