# frozen_string_literal: true

require 'open3'
require 'shellwords'

module RobotLab
  # Factory module for wrapping AgentSkills scripts as RobotLab::Tool instances.
  #
  # Given a path to an executable shell script, produces a Tool that shells
  # out to the script and returns its combined stdout+stderr output.
  # Non-executable scripts return nil with a logged warning.
  #
  # Core has no sandboxing of its own: by default every script runs unconfined
  # with no timeout. An extension gem (e.g. robot_lab-sandbox) can install a
  # confinement strategy by setting {.executor} to an object responding to
  # +call(cmd, capabilities:, skill_dir:)+; when set, ScriptTool.execute
  # delegates to it instead of running the command directly.
  module ScriptTool
    class << self
      # @return [#call, nil] optional executor installed by an extension gem
      attr_accessor :executor
    end

    # Wrap a script file as a RobotLab::Tool.
    #
    # @param script_path [String, Pathname] path to the script file
    # @return [RobotLab::Tool, nil] nil if the script is not executable
    # @param script_path [String, Pathname] path to the script file
    # @param capabilities [Capabilities, nil] declared capabilities (from SKILL.md)
    # @param skill_dir [String, nil] skill bundle root (defaults to the script's dir)
    # @return [RobotLab::Tool, nil] nil if the script is not executable
    # :reek:ControlParameter -- `capabilities || ...` and `skill_dir || ...` are nil-safe defaults, not behavior selection.
    # :reek:TooManyStatements -- linear derive/validate/build factory; the closure needs every derived local.
    def self.from_path(script_path, capabilities: nil, skill_dir: nil)
      path = Pathname.new(script_path)

      unless path.executable?
        RobotLab.config.logger.warn(
          "ScriptTool: #{path.basename} is not executable, skipping"
        )
        return nil
      end

      tool_name   = derive_name(path)
      description = extract_description(path)
      script      = path.to_s
      caps        = capabilities || Capabilities.new
      dir         = skill_dir || path.dirname.to_s

      Tool.create(
        name: tool_name,
        description: description,
        parameters: {
          type: 'object',
          properties: {
            args: { type: 'string', description: 'Optional command-line arguments' }
          },
          required: []
        }
      ) do |tool_args|
        cli_args = tool_args[:args].to_s.strip
        cmd      = cli_args.empty? ? ['bash', script] : ['bash', script, *Shellwords.split(cli_args)]
        ScriptTool.execute(cmd, capabilities: caps, skill_dir: dir)
      end
    end

    # Run a command, delegating to the installed {.executor} if one is present.
    #
    # With no executor installed (the default — core has no sandboxing), this
    # is a plain, unconfined capture2e path with no timeout. An extension gem
    # that sets {.executor} controls confinement and timeout behavior entirely.
    #
    # @return [String] combined stdout+stderr, or an error string on failure
    def self.execute(cmd, capabilities:, skill_dir:)
      return executor.call(cmd, capabilities: capabilities, skill_dir: skill_dir) if executor

      output, status = Open3.capture2e(*cmd)
      format_result(output, status)
    end

    # @param status [Process::Status, nil] nil indicates a timeout kill
    def self.format_result(output, status)
      return "Error (timed out):\n#{output}" if status.nil?

      status.success? ? output : "Error (exit #{status.exitstatus}):\n#{output}"
    end

    # @param path [Pathname]
    # @return [String] snake_case tool name derived from filename
    def self.derive_name(path)
      path.basename.to_s
          .sub(/\.[^.]+$/, '')
          .gsub(/[^a-zA-Z0-9]+/, '_')
          .gsub(/^_+|_+$/, '')
    end

    # Extract tool description from the first non-shebang comment line.
    #
    # @param path [Pathname]
    # @return [String]
    def self.extract_description(path)
      File.foreach(path) do |line|
        stripped = line.strip
        next unless stripped.start_with?('#')
        next if stripped.start_with?('#!') # skip shebang

        desc = stripped.sub(/^#+\s*/, '').strip
        return desc unless desc.empty?
      end
      derive_name(path)
    rescue StandardError
      derive_name(path)
    end
  end
end
