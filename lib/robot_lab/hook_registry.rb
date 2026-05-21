# frozen_string_literal: true

module RobotLab
  class HookRegistry
    Registration = Data.define(:hook_name, :namespace, :callback, :context) do
      def initialize(hook_name:, namespace:, callback:, context: nil)
        super
      end
    end

    def initialize
      @registrations = Hash.new { |h, key| h[key] = [] }
    end

    def on(hook_name, namespace: nil, context: nil, &callback)
      raise ArgumentError, "Hook registration requires a block" unless callback

      registration = Registration.new(
        hook_name: hook_name.to_sym,
        namespace: namespace&.to_sym,
        callback: callback,
        context: context
      )

      @registrations[registration.hook_name] << registration
      registration
    end

    def registrations_for(hook_name)
      @registrations[hook_name.to_sym]
    end

    def clear
      @registrations.clear
    end
  end
end
