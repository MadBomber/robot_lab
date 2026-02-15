# frozen_string_literal: true

require "test_helper"

class RobotLab::ToolTest < Minitest::Test
  # ── Subclass pattern ──────────────────────────────────────────

  def test_subclass_inherits_from_ruby_llm_tool
    assert RobotLab::Tool < RubyLLM::Tool
  end

  def test_subclass_with_description_and_params
    klass = Class.new(RobotLab::Tool) do
      description "Adds two numbers"
      param :a, type: "number", desc: "First number"
      param :b, type: "number", desc: "Second number"

      def execute(a:, b:)
        a + b
      end
    end

    tool = klass.new
    assert_equal "Adds two numbers", tool.description
    assert tool.parameters.key?(:a)
    assert tool.parameters.key?(:b)
  end

  def test_subclass_execute
    klass = Class.new(RobotLab::Tool) do
      description "Doubles a value"
      param :value, type: "number", desc: "Value to double"

      def execute(value:)
        value * 2
      end
    end

    tool = klass.new
    result = tool.call({ "value" => 10 })
    assert_equal 20, result
  end

  # ── robot: accessor ──────────────────────────────────────────

  def test_robot_accessor_in_constructor
    mock_robot = Object.new
    klass = Class.new(RobotLab::Tool) do
      description "Test tool"
      def execute(**); end
    end

    tool = klass.new(robot: mock_robot)
    assert_equal mock_robot, tool.robot
  end

  def test_robot_accessor_is_writable
    tool = Class.new(RobotLab::Tool) { def execute(**); end }.new
    mock_robot = Object.new

    tool.robot = mock_robot
    assert_equal mock_robot, tool.robot
  end

  def test_robot_accessible_in_execute
    captured_robot = nil
    klass = Class.new(RobotLab::Tool) do
      description "Captures robot"
      param :x, type: "string", desc: "Ignored"

      define_method(:execute) do |**_args|
        captured_robot = robot
        "done"
      end
    end

    mock_robot = Object.new
    tool = klass.new(robot: mock_robot)
    tool.call({ "x" => "test" })

    assert_equal mock_robot, captured_robot
  end

  def test_robot_defaults_to_nil
    tool = Class.new(RobotLab::Tool) { def execute(**); end }.new
    assert_nil tool.robot
  end

  # ── Tool.create factory ──────────────────────────────────────

  def test_create_with_name_and_description
    tool = RobotLab::Tool.create(
      name: "get_time",
      description: "Get the current time"
    ) { |_args| Time.now.to_s }

    assert_equal "get_time", tool.name
    assert_equal "Get the current time", tool.description
  end

  def test_create_with_parameters
    tool = RobotLab::Tool.create(
      name: "search",
      description: "Search for items",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search query" },
          limit: { type: "integer", description: "Max results" }
        },
        required: ["query"]
      }
    ) { |args| args }

    schema = tool.params_schema
    assert schema
    props = schema[:properties] || schema["properties"]
    assert props
    assert props.key?(:query) || props.key?("query")
  end

  def test_create_executes_handler_block
    tool = RobotLab::Tool.create(
      name: "adder",
      description: "Adds numbers"
    ) { |args| args[:a] + args[:b] }

    result = tool.call({ "a" => 2, "b" => 3 })
    assert_equal 5, result
  end

  def test_create_with_robot
    mock_robot = Object.new
    tool = RobotLab::Tool.create(
      name: "test",
      description: "Test",
      robot: mock_robot
    ) { |_args| "ok" }

    assert_equal mock_robot, tool.robot
  end

  def test_create_with_symbol_name
    tool = RobotLab::Tool.create(name: :symbol_name) { |_args| "ok" }
    assert_equal "symbol_name", tool.name
  end

  # ── MCP ──────────────────────────────────────────────────────

  def test_mcp_flag_true_when_set
    tool = RobotLab::Tool.create(
      name: "mcp_tool",
      mcp: "github"
    ) { |_args| "ok" }

    assert tool.mcp?
    assert_equal "github", tool.mcp
  end

  def test_mcp_flag_false_when_nil
    tool = RobotLab::Tool.create(name: "local_tool") { |_args| "ok" }
    refute tool.mcp?
  end

  def test_mcp_nil_on_subclass
    klass = Class.new(RobotLab::Tool) { def execute(**); end }
    tool = klass.new
    refute tool.mcp?
    assert_nil tool.mcp
  end

  # ── name ─────────────────────────────────────────────────────

  def test_name_from_class_on_subclass
    # RubyLLM::Tool derives name from class name
    klass = Class.new(RobotLab::Tool) { def execute(**); end }
    tool = klass.new
    # Anonymous classes have nil name, so RubyLLM falls through
    # Named classes would work: class MyTool < RobotLab::Tool => "my"
    assert tool.name.is_a?(String)
  end

  def test_name_explicit_on_create
    tool = RobotLab::Tool.create(name: "explicit_name") { |_args| "ok" }
    assert_equal "explicit_name", tool.name
  end

  # ── call (inherited from RubyLLM::Tool) ─────────────────────

  def test_call_transforms_string_keys_to_symbols
    received_args = nil
    tool = RobotLab::Tool.create(
      name: "test",
      description: "Test",
      parameters: {
        type: "object",
        properties: { key: { type: "string" } },
        required: ["key"]
      }
    ) { |args| received_args = args; "ok" }

    tool.call({ "key" => "value" })
    assert_equal({ key: "value" }, received_args)
  end

  def test_call_with_symbol_keys
    received_args = nil
    tool = RobotLab::Tool.create(name: "test") { |args| received_args = args; "ok" }

    tool.call({ key: "value" })
    assert_equal({ key: "value" }, received_args)
  end

  # ── to_json_schema ──────────────────────────────────────────

  def test_to_json_schema_with_no_parameters
    tool = RobotLab::Tool.create(name: "simple", description: "A simple tool") { |_args| "ok" }

    schema = tool.to_json_schema

    assert_equal "simple", schema[:name]
    assert_equal "A simple tool", schema[:description]
    assert schema[:parameters]
  end

  def test_to_json_schema_with_parameters
    tool = RobotLab::Tool.create(
      name: "search",
      description: "Search",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search query" }
        },
        required: ["query"]
      }
    ) { |_args| "ok" }

    schema = tool.to_json_schema

    assert_equal "search", schema[:name]
    assert schema[:parameters]
  end

  def test_to_json_schema_excludes_nil_description
    tool = RobotLab::Tool.create(name: "minimal") { |_args| "ok" }

    schema = tool.to_json_schema

    # nil description should be compacted out
    refute schema.key?(:description) if tool.description.nil?
  end

  # ── to_h ────────────────────────────────────────────────────

  def test_to_h_includes_name_and_description
    tool = RobotLab::Tool.create(name: "full", description: "Full tool") { |_args| "ok" }

    hash = tool.to_h

    assert_equal "full", hash[:name]
    assert_equal "Full tool", hash[:description]
  end

  def test_to_h_includes_mcp
    tool = RobotLab::Tool.create(name: "mcp_tool", mcp: "server") { |_args| "ok" }

    hash = tool.to_h

    assert_equal "server", hash[:mcp]
  end

  def test_to_h_excludes_nil_values
    tool = RobotLab::Tool.create(name: "minimal") { |_args| "ok" }

    hash = tool.to_h

    refute hash.key?(:mcp)
  end

  # ── to_json ─────────────────────────────────────────────────

  def test_to_json_returns_json_string
    tool = RobotLab::Tool.create(name: "json_tool", description: "Test") { |_args| "ok" }

    json = tool.to_json

    assert json.is_a?(String)
    parsed = JSON.parse(json)
    assert_equal "json_tool", parsed["name"]
    assert_equal "Test", parsed["description"]
  end

  # ── params_schema (inherited) ──────────────────────────────

  def test_params_schema_from_param_dsl
    klass = Class.new(RobotLab::Tool) do
      param :x, type: "integer", desc: "An integer"
      def execute(x:); x; end
    end

    tool = klass.new
    schema = tool.params_schema

    assert schema
    assert schema[:properties]&.key?(:x) || schema["properties"]&.key?("x")
  end

  def test_params_schema_nil_without_parameters
    klass = Class.new(RobotLab::Tool) { def execute(**); end }
    tool = klass.new

    # RubyLLM::Tool returns nil when no params defined
    # (or an empty schema depending on version)
    schema = tool.params_schema
    assert schema.nil? || schema.is_a?(Hash)
  end

  # ── provider_params (inherited) ────────────────────────────

  def test_provider_params_defaults_to_empty_hash
    klass = Class.new(RobotLab::Tool) { def execute(**); end }
    tool = klass.new

    assert_equal({}, tool.provider_params)
  end

  def test_provider_params_with_strict
    klass = Class.new(RobotLab::Tool) do
      with_params(strict: true)
      def execute(**); end
    end

    tool = klass.new
    assert tool.provider_params[:strict]
  end

  # ── Error handling ─────────────────────────────────────────

  def test_execute_raising_propagates_from_call
    tool = RobotLab::Tool.create(name: "error_tool") do |_args|
      raise StandardError, "Something went wrong"
    end

    # RubyLLM::Tool#call does not catch exceptions — they propagate
    assert_raises(StandardError) { tool.call({}) }
  end

  # ── halt (inherited) ───────────────────────────────────────

  def test_halt_returns_halt_object
    klass = Class.new(RobotLab::Tool) do
      description "Halting tool"
      def execute(**)
        halt("Stop processing")
      end
    end

    tool = klass.new
    result = tool.call({})
    assert result.is_a?(RubyLLM::Tool::Halt)
    assert_equal "Stop processing", result.to_s
  end

  # ── is_a? checks ───────────────────────────────────────────

  def test_tool_is_a_ruby_llm_tool
    tool = RobotLab::Tool.create(name: "test") { |_args| "ok" }

    assert tool.is_a?(RubyLLM::Tool)
    assert tool.is_a?(RobotLab::Tool)
  end

  def test_subclass_is_a_ruby_llm_tool
    klass = Class.new(RobotLab::Tool) { def execute(**); end }
    tool = klass.new

    assert tool.is_a?(RubyLLM::Tool)
    assert tool.is_a?(RobotLab::Tool)
  end
end
