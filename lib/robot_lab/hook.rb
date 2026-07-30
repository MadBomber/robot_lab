# frozen_string_literal: true

module RobotLab
  # Base class for hook handlers.
  #
  # Subclasses implement class methods for each hook they handle.
  # Unimplemented hooks are silently skipped; around hooks passthrough
  # automatically so the chain never breaks.
  #
  # The namespace defaults to the snake_case form of the last segment of the
  # class name (e.g. TokenLogger -> :token_logger). Override with
  # `self.namespace = :custom` when needed.
  #
  # @example
  #   class AuditHook < RobotLab::Hook
  #     def self.before_run(ctx)
  #       ctx.local.started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  #     end
  #
  #     def self.after_run(ctx)
  #       elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - ctx.local.started_at
  #       puts "[#{ctx.robot.name}] #{(elapsed * 1000).round(1)}ms"
  #     end
  #
  #     def self.on_error(ctx)
  #       puts "[#{ctx.robot.name}] ERROR: #{ctx.error.message}"
  #     end
  #   end
  #
  #   RobotLab.on(AuditHook)
  #   robot.on(AuditHook)
  #   network.on(AuditHook)
  #
  class Hook
    @namespace = nil

    class << self
      attr_writer :namespace

      # Returns the hook's namespace symbol, derived from the class name by
      # default. Returns nil for the base Hook class itself.
      #
      # @return [Symbol, nil]
      def namespace
        return @namespace if @namespace
        return nil if self == Hook

        name.split('::').last
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
            .to_sym
      end

      # Dispatch a single hook to this handler.
      #
      # If the handler implements the method it is called. For around hooks that
      # are not implemented the block is called directly (passthrough). Non-around
      # hooks that are not implemented are silent no-ops.
      #
      # @param hook_name [Symbol] e.g. :before_run, :around_tool_call
      # @param context [HookContext] the hook context object
      # @yield for around hooks — the next link in the chain
      def call(hook_name, context, &block)
        if singleton_class.public_method_defined?(hook_name)
          block ? public_send(hook_name, context, &block)
                : public_send(hook_name, context)
        elsif block
          block.call
        end
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@namespace, nil)
      end
    end
  end
end
