# frozen_string_literal: true

require "test_helper"

class RobotLab::HookContextTest < Minitest::Test
  def test_base_context_to_h_includes_event_and_metadata
    assert_equal({ event: :x, metadata: {} }, RobotLab::HookContext.new(event: :x).to_h)
  end

  def test_subclass_to_h_includes_inherited_readers
    snapshot = RobotLab::LlmGenerationHookContext.new(robot: :r, request: "hi", iteration: 2).to_h

    assert_equal %i[config error event generation_response iteration memory metadata
                    network request response robot task],
                 snapshot.keys
    assert_equal :run, snapshot[:event]
    assert_equal :r, snapshot[:robot]
    assert_equal "hi", snapshot[:request]
    assert_equal 2, snapshot[:iteration]
  end

  def test_to_h_excludes_setters_methods_with_arguments_and_local
    context = RobotLab::ToolCallHookContext.new(tool: :t, tool_args: { a: 1 })
    keys = context.with_namespace(:ns) { |ctx| ctx.to_h.keys }

    refute_includes keys, :local
    refute_includes keys, :to_h
    refute_includes keys, :ext
    refute_includes keys, :with_namespace
    assert(keys.none? { |key| key.end_with?("=") })
  end

  def test_to_h_includes_zero_arity_predicates
    context = RobotLab::CompactionHookContext.new(robot: :r, messages_before: [], config: nil,
                                                  strategy: :custom)

    assert_equal false, context.to_h[:handled?]
  end

  def test_snapshot_readers_on_base_class
    assert_equal %i[event metadata], RobotLab::HookContext.snapshot_readers
  end

  def test_to_h_serializes_metadata_extension_state
    context = RobotLab::HookContext.new(event: :x)
    context.ext(:audit).count = 3

    assert_equal({ audit: { count: 3 } }, context.to_h[:metadata])
  end
end
