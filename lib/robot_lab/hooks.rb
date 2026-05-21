# frozen_string_literal: true

module RobotLab
  module Hooks
    module_function

    def run(family, context, registries:, per_run_hooks: nil, &)
      before = registrations(:"before_#{family}", registries, per_run_hooks)
      around = registrations(:"around_#{family}", registries, per_run_hooks)
      after  = registrations(:"after_#{family}", registries, per_run_hooks)
      errors = error_registrations(family, registries, per_run_hooks)

      call_all(before, context)
      result = call_around(around, context, &)
      set_result(context, family, result)
      call_all(after, context)
      result
    rescue Exception => e # rubocop:disable Lint/RescueException
      context.error = e if context.respond_to?(:error=)
      call_all(errors, context)
      raise
    end

    def call(hook_name, context, registries:, per_run_hooks: nil)
      call_all(registrations(hook_name, registries, per_run_hooks), context)
    end

    def around(hook_name, context, registries:, per_run_hooks: nil, &)
      call_around(registrations(hook_name, registries, per_run_hooks), context, &)
    end

    def registrations(hook_name, registries, per_run_hooks)
      registry_entries = registries.compact.flat_map { |registry| registry.registrations_for(hook_name) }
      registry_entries + per_run_entries(hook_name, per_run_hooks)
    end

    def error_registrations(family, registries, per_run_hooks)
      return [] unless %i[run network_run task].include?(family.to_sym)

      registrations(:on_error, registries, per_run_hooks)
    end

    def call_all(registrations, context)
      registrations.each { |registration| call_registration(registration, context) }
    end

    def call_around(registrations, context, &block)
      chain = registrations.reverse.inject(block) do |next_link, registration|
        proc { call_registration(registration, context, &next_link) }
      end

      chain.call
    end

    def call_registration(registration, context, &block)
      context.with_namespace(registration.namespace) do
        if registration.context && registration.namespace
          context.ext(registration.namespace).merge_defaults(registration.context)
        end
        if block
          registration.callback.call(context, &block)
        else
          registration.callback.call(context)
        end
      end
    end

    def per_run_entries(hook_name, hooks)
      return [] unless hooks

      Array(hooks[hook_name.to_sym]).map do |callback|
        HookRegistry::Registration.new(
          hook_name: hook_name.to_sym,
          namespace: hooks[:namespace]&.to_sym,
          callback: callback
        )
      end
    end

    def set_result(context, family, result)
      case family.to_sym
      when :run
        context.response = result if context.respond_to?(:response=)
      when :network_run, :task
        context.result = result if context.respond_to?(:result=)
      when :llm_generation
        context.generation_response = result if context.respond_to?(:generation_response=)
      end
    end
  end
end
