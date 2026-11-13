# frozen_string_literal: true

require "test_helper"

# Named hook whose namespace is derived from its class name.
class NamedNamespaceHook < RobotLab::Hook; end

# Tests RobotLab::Hook.namespace for named and anonymous subclasses.
class RobotLabHookTest < Minitest::Test
  def anonymous_hook(&before_run)
    before_run ||= proc {}
    Class.new(RobotLab::Hook) { define_singleton_method(:before_run, &before_run) }
  end

  def test_named_hook_namespace_derives_from_class_name
    assert_equal :named_namespace_hook, NamedNamespaceHook.namespace
  end

  def test_anonymous_hook_namespace_is_nil
    assert_nil anonymous_hook.namespace
  end

  def test_anonymous_hook_with_explicit_namespace
    hook = anonymous_hook
    hook.namespace = :custom

    assert_equal :custom, hook.namespace
  end

  def test_registry_rejects_anonymous_hook_with_argument_error
    error = assert_raises(ArgumentError) { RobotLab::HookRegistry.new.on(anonymous_hook) }

    assert_match(/has no namespace/, error.message)
  end

  def test_anonymous_per_run_hook_fires
    fired = false
    hook = anonymous_hook { |_ctx| fired = true }
    result = RobotLab::Hooks.run(:run, RobotLab::HookContext.new(event: :run),
                                 registries: [], per_run_hooks: hook) { :ok }

    assert_equal :ok, result
    assert fired
  end
end
