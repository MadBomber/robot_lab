# frozen_string_literal: true

# xyzzy.rb — single-file RobotLab hook extension demo
#
# Demonstrates the Hook handler class pattern: implement class methods for
# every hook under a dedicated namespace and log each callback with its
# context snapshot. Useful as a live trace of the full hook pipeline during
# development.
#
# stdout : one tagline per hook call  →  [xyzzy] HH:MM:SS.mmm hook_name
# logfile: full context snapshot for each call (set via Xyzzy.logger=)
#
# Usage (from any example that requires common):
#   require_relative "xyzzy"

require "logger"

module RobotLab
  class Xyzzy < Hook
    self.namespace = :xyzzy

    class << self
      attr_writer :logger

      def logger
        @logger ||= Logger.new($stdout)
      end

      def before_run(ctx)               = log_hook(:before_run, ctx)
      def after_run(ctx)                = log_hook(:after_run, ctx)
      def on_error(ctx)                 = log_hook(:on_error, ctx)
      def before_llm_generation(ctx)    = log_hook(:before_llm_generation, ctx)
      def after_llm_generation(ctx)     = log_hook(:after_llm_generation, ctx)
      def before_tool_call(ctx)         = log_hook(:before_tool_call, ctx)
      def after_tool_call(ctx)          = log_hook(:after_tool_call, ctx)
      def before_network_run(ctx)       = log_hook(:before_network_run, ctx)
      def after_network_run(ctx)        = log_hook(:after_network_run, ctx)
      def before_task(ctx)              = log_hook(:before_task, ctx)
      def after_task(ctx)               = log_hook(:after_task, ctx)

      def around_run(ctx, &block)
        log_hook(:around_run, ctx)
        block.call
      end

      def around_llm_generation(ctx, &block)
        log_hook(:around_llm_generation, ctx)
        block.call
      end

      def around_tool_call(ctx, &block)
        log_hook(:around_tool_call, ctx)
        block.call
      end

      def around_network_run(ctx, &block)
        log_hook(:around_network_run, ctx)
        block.call
      end

      def around_task(ctx, &block)
        log_hook(:around_task, ctx)
        block.call
      end

      private

      def log_hook(hook_name, ctx)
        ts = Time.now.strftime('%H:%M:%S.%3N')
        puts "  [xyzzy] #{ts} #{hook_name}"
        logger.info("#{ts} #{hook_name} #{context_snapshot(ctx)}")
      end

      def context_snapshot(ctx)
        {
          robot:   ctx.respond_to?(:robot)   ? ctx.robot&.name    : nil,
          request: ctx.respond_to?(:request) ? ctx.request        : nil,
          network: ctx.respond_to?(:network) ? ctx.network&.name  : nil,
          task:    ctx.respond_to?(:task)    ? ctx.task           : nil,
          error:   ctx.respond_to?(:error)   ? ctx.error&.message : nil
        }.compact
      end
    end
  end
end

RobotLab.register_extension(:xyzzy, RobotLab::Xyzzy) if RobotLab.respond_to?(:register_extension)
RobotLab.on(RobotLab::Xyzzy)
