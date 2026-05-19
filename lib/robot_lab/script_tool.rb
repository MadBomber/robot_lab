# frozen_string_literal: true

require 'open3'
require 'shellwords'

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
    def self.from_path(script_path)
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
        output, status = Open3.capture2e(*cmd)
        status.success? ? output : "Error (exit #{status.exitstatus}):\n#{output}"
      end
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
