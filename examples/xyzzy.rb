# frozen_string_literal: true

# xyzzy.rb — single-file RobotLab hook extension demo
#
# Demonstrates the extension pattern: register for every hook under a
# dedicated namespace and log each callback with its context snapshot.
# Useful as a live trace of the full hook pipeline during development.
#
# Usage (from any example that requires common):
#   require_relative "xyzzy"

require "logger"

module RobotLab
  module Xyzzy
    NAMESPACE = :xyzzy

    HOOK_NAMES = %i[
      before_run
      around_run
      after_run
      on_error
      before_llm_generation
      around_llm_generation
      after_llm_generation
      before_tool_call
      around_tool_call
      after_tool_call
      before_network_run
      around_network_run
      after_network_run
      before_task
      around_task
      after_task
    ].freeze

    class << self
      attr_writer :logger

      def logger
        @logger ||= Logger.new($stdout)
      end

      def attach_hooks(registry: RobotLab)
        return unless registry.respond_to?(:on)

        HOOK_NAMES.each { |hook_name| register_hook(registry, hook_name) }
        HOOK_NAMES
      end

      def callback_for(hook_name)
        if hook_name.to_s.start_with?("around_")
          proc { |context, &block| call_around_hook(hook_name, context, &block) }
        else
          proc { |context| log_hook(hook_name, context) }
        end
      end

      def log_hook(hook_name, context)
        logger.info(log_message(hook_name, context))
      end

      def log_message(hook_name, context)
        "robot_lab-xyzzy hook=#{hook_name} namespace=#{NAMESPACE} context=#{context_snapshot(context).inspect}"
      end

      def context_snapshot(context)
        if context.respond_to?(:to_h)
          context.to_h
        else
          public_context_methods(context).to_h { |m| [m, context.public_send(m)] }
        end
      end

      private

      def register_hook(registry, hook_name)
        if namespace_supported?(registry)
          registry.on(hook_name, namespace: NAMESPACE, &callback_for(hook_name))
        else
          registry.on(hook_name, &callback_for(hook_name))
        end
      end

      def namespace_supported?(registry)
        registry.method(:on).parameters.any? { |type, _| %i[key keyreq keyrest].include?(type) }
      end

      def call_around_hook(hook_name, context)
        log_hook(hook_name, context)
        yield if block_given?
      end

      def public_context_methods(context)
        context.public_methods(false).sort.grep_v(/=\z/)
      end
    end
  end
end

RobotLab.register_extension(RobotLab::Xyzzy::NAMESPACE, RobotLab::Xyzzy) if RobotLab.respond_to?(:register_extension)
RobotLab::Xyzzy.attach_hooks
