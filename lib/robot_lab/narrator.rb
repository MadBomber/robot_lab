# frozen_string_literal: true

module RobotLab
  # Opt-in live observability hook: narrates what a robot is doing as it happens,
  # so a run is never silent between events. Complements RobotLab::Audit (which
  # records to a persistent store) with a human-facing console feed.
  #
  # Enable it globally (applies to every robot run, including networks):
  #
  #   RobotLab::Narrator.enable!            # narrate to $stderr
  #   RobotLab::Narrator.enable!(output: $stdout)
  #
  # or register like any hook for finer scope:
  #
  #   robot.on(RobotLab::Narrator)
  #   network.on(RobotLab::Narrator)
  #
  # Output goes to $stderr by default and uses IO#puts (not Kernel#warn, which is
  # silenced when Ruby warnings are disabled — i.e. $VERBOSE is nil, common under
  # `bundle exec`).
  class Narrator < RobotLab::Hook
    self.namespace = :narrator

    MAX = 80

    class << self
      attr_writer :output

      # @return [IO] where narration is written (default $stderr)
      def output
        @output ||= $stderr
      end

      # Register the narrator globally and set its output.
      #
      # @param output [IO]
      # @return [Class] self
      def enable!(output: $stderr)
        self.output = output
        RobotLab.on(self)
        self
      end

      # --- hooks ---------------------------------------------------------------

      def before_llm_generation(ctx)
        who = ctx.respond_to?(:robot) ? ctx.robot&.name : nil
        say "#{"#{who}: " if who}thinking…"
      rescue StandardError
        nil
      end

      def before_tool_call(ctx)
        say "→ #{ctx.tool_name}#{summarize(ctx.tool_args)}"
      rescue StandardError
        nil
      end

      def after_tool_call(ctx)
        say "  ✗ #{clip(ctx.tool_error.message)}" if ctx.tool_error
      rescue StandardError
        nil
      end

      private

      def say(message)
        output.puts("  · #{message}")
      rescue StandardError
        nil
      end

      # Compact one-line summary of the first tool argument, e.g. " path=\"a.rb\"".
      def summarize(args)
        return "" unless args.is_a?(Hash) && !args.empty?

        key, value = args.first
        " #{key}=#{clip(value).inspect}"
      end

      def clip(text)
        line = text.to_s.lines.first.to_s.strip
        line.length > MAX ? "#{line[0, MAX]}…" : line
      end
    end
  end
end
