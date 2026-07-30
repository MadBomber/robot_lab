# frozen_string_literal: true

require 'open3'
require 'shellwords'
require 'timeout'

module RobotLab
  # Factory module for wrapping AgentSkills scripts as RobotLab::Tool instances.
  #
  # Given a path to an executable shell script, produces a Tool that shells
  # out to the script and returns its combined stdout+stderr output.
  # Non-executable scripts return nil with a logged warning.
  module ScriptTool
    # Wrap a script file as a RobotLab::Tool.
    #
    # @param script_path [String, Pathname] path to the script file
    # @return [RobotLab::Tool, nil] nil if the script is not executable
    # @param script_path [String, Pathname] path to the script file
    # @param capabilities [Capabilities, nil] declared capabilities (from SKILL.md)
    # @param skill_dir [String, nil] skill bundle root (defaults to the script's dir)
    # @return [RobotLab::Tool, nil] nil if the script is not executable
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

    # Run a command, optionally confined by the sandbox and a timeout.
    #
    # When sandboxing is disabled (the default) this is the original, unconfined
    # capture2e path with no timeout — behaviour is unchanged. When enabled, the
    # command is wrapped by the sandbox strategy for the effective grant and
    # bounded by the grant's timeout.
    #
    # @return [String] combined stdout+stderr, or an error string on failure
    def self.execute(cmd, capabilities:, skill_dir:)
      unless Sandbox.enabled?
        output, status = Open3.capture2e(*cmd)
        return format_result(output, status)
      end

      grant   = capabilities.intersect(Capabilities.ceiling)
      sandbox = Sandbox.for(grant, skill_dir: skill_dir)
      begin
        output, status = run_with_timeout(sandbox.wrap(cmd), grant.timeout)
        format_result(output, status)
      ensure
        sandbox.cleanup
      end
    end

    # @return [Array(String, Process::Status|nil)] output and status (nil = timed out)
    def self.run_with_timeout(cmd, timeout)
      Open3.popen2e(*cmd, pgroup: true) do |stdin, out, wait|
        stdin.close
        output = +''
        begin
          Timeout.timeout(timeout) { output << out.read }
        rescue Timeout::Error
          terminate(wait.pid)
          return ["#{output}\n[killed: exceeded #{timeout}s]", nil]
        end
        [output, wait.value]
      end
    end

    def self.terminate(pid)
      Process.kill('-TERM', Process.getpgid(pid))
    rescue StandardError
      nil
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
