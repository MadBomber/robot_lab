# frozen_string_literal: true

require "test_helper"
require "stringio"

class RobotLab::NarratorTest < Minitest::Test
  def setup
    @io = StringIO.new
    RobotLab::Narrator.output = @io
  end

  def teardown
    RobotLab::Narrator.output = $stderr
  end

  def tool_ctx(name, args = {})
    RobotLab::ToolCallHookContext.new(tool: Struct.new(:name).new(name), tool_args: args)
  end

  def narrate(hook, ctx)
    ctx.with_namespace(:narrator) { RobotLab::Narrator.public_send(hook, ctx) }
  end

  def test_default_output_is_stderr
    RobotLab::Narrator.instance_variable_set(:@output, nil)
    assert_equal $stderr, RobotLab::Narrator.output
  ensure
    RobotLab::Narrator.output = @io
  end

  def test_before_tool_call_narrates_tool_and_first_arg
    narrate(:before_tool_call, tool_ctx("write", { "path" => "lib/x.rb" }))
    assert_match(/write/, @io.string)
    assert_match(/path=/, @io.string)
  end

  def test_before_tool_call_without_args
    narrate(:before_tool_call, tool_ctx("dump"))
    assert_match(/dump/, @io.string)
  end

  def test_after_tool_call_reports_errors
    ctx = tool_ctx("bash")
    ctx.tool_error = RuntimeError.new("boom\nsecond line")
    narrate(:after_tool_call, ctx)
    assert_match(/boom/, @io.string)
    refute_match(/second line/, @io.string) # only the first line
  end

  def test_after_tool_call_silent_on_success
    narrate(:after_tool_call, tool_ctx("read"))
    assert_empty @io.string
  end

  def test_before_llm_generation_narrates_thinking_with_robot_name
    ctx = RobotLab::RunHookContext.new(robot: Struct.new(:name).new("planner"), request: "x")
    ctx.with_namespace(:narrator) { RobotLab::Narrator.before_llm_generation(ctx) }
    assert_match(/planner/, @io.string)
    assert_match(/thinking/, @io.string)
  end

  def test_long_argument_values_are_clipped
    narrate(:before_tool_call, tool_ctx("write", { "content" => "x" * 200 }))
    assert_match(/…/, @io.string)
  end

  def test_enable_registers_globally_and_sets_output
    RobotLab.clear_hooks!
    RobotLab::Narrator.enable!(output: @io)
    handlers = RobotLab.hooks.registrations.map(&:handler_class)
    assert_includes handlers, RobotLab::Narrator
    assert_equal @io, RobotLab::Narrator.output
  ensure
    RobotLab.clear_hooks!
  end
end
