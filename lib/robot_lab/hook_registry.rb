# frozen_string_literal: true

module RobotLab
  class HookRegistry
    Registration = Data.define(:handler_class, :context) do
      def initialize(handler_class:, context: nil)
        super
      end

      def namespace
        handler_class.namespace
      end
    end

    def initialize
      @registrations = []
    end

    # Register a hook handler class.
    #
    # @param handler_class [Class] a RobotLab::Hook subclass
    # @param context [Hash, nil] optional default values merged into ctx.local on each call
    # @return [Registration]
    def on(handler_class, context: nil)
      unless handler_class.is_a?(Class) && handler_class < RobotLab::Hook
        raise ArgumentError, "#{handler_class.inspect} must be a RobotLab::Hook subclass"
      end
      raise ArgumentError, "#{handler_class} has no namespace" if handler_class.namespace.nil?

      registration = Registration.new(handler_class: handler_class, context: context)
      @registrations << registration
      registration
    end

    # Returns registrations whose handler implements the given hook method.
    #
    # @param hook_name [Symbol]
    # @return [Array<Registration>]
    def registrations_for(hook_name)
      hook_sym = hook_name.to_sym
      @registrations.select { |reg| reg.handler_class.singleton_class.public_method_defined?(hook_sym) }
    end

    # Returns all registrations (defensive copy).
    #
    # @return [Array<Registration>]
    def registrations
      @registrations.dup
    end

    def clear
      @registrations.clear
    end
  end
end
