# frozen_string_literal: true

module RobotLab
  module Hooks
    module_function

    def run(family, context, registries:, per_run_hooks: nil, &)
      before = registrations(:"before_#{family}", registries, per_run_hooks)
      around = registrations(:"around_#{family}", registries, per_run_hooks)
      after  = registrations(:"after_#{family}", registries, per_run_hooks)
      errors = error_registrations(family, registries, per_run_hooks)

      call_all(before, :"before_#{family}", context)
      result = call_around(around, :"around_#{family}", context, &)
      set_result(context, family, result)
      call_all(after, :"after_#{family}", context)
      result
    rescue Exception => e # rubocop:disable Lint/RescueException
      context.error = e if context.respond_to?(:error=)
      call_all(errors, :on_error, context)
      raise
    end

    def call(hook_name, context, registries:, per_run_hooks: nil)
      call_all(registrations(hook_name, registries, per_run_hooks), hook_name, context)
    end

    def around(hook_name, context, registries:, per_run_hooks: nil, &)
      call_around(registrations(hook_name, registries, per_run_hooks), hook_name, context, &)
    end

    def registrations(hook_name, registries, per_run_hooks)
      registry_entries = registries.compact.flat_map { |registry| registry.registrations_for(hook_name) }
      registry_entries + per_run_entries(hook_name, per_run_hooks)
    end

    def error_registrations(family, registries, per_run_hooks)
      return [] unless %i[run network_run task].include?(family.to_sym)

      registrations(:on_error, registries, per_run_hooks)
    end

    def call_all(registrations, hook_name, context)
      registrations.each { |registration| call_registration(registration, hook_name, context) }
    end

    def call_around(registrations, hook_name, context, &block)
      chain = registrations.reverse.inject(block) do |next_link, registration|
        proc { call_registration(registration, hook_name, context, &next_link) }
      end

      chain.call
    end

    def call_registration(registration, hook_name, context, &)
      context.with_namespace(registration.namespace) do
        if registration.context && registration.namespace
          context.ext(registration.namespace).merge_defaults(registration.context)
        end
        registration.handler_class.call(hook_name, context, &)
      end
    end

    # per_run_hooks is now a single handler class or an array of handler classes.
    def per_run_entries(hook_name, hooks)
      return [] unless hooks

      hook_sym = hook_name.to_sym
      Array(hooks).filter_map do |handler_class|
        next unless handler_class.singleton_class.public_method_defined?(hook_sym)

        HookRegistry::Registration.new(handler_class: handler_class)
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
