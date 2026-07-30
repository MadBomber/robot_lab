# frozen_string_literal: true

module RobotLab
  module Sandbox
    # Passthrough strategy: runs the command with no confinement. Used when
    # sandboxing is unavailable (non-macOS) or unnecessary (trust: core).
    class Null
      def wrap(cmd) = cmd

      def cleanup; end
    end
  end
end
