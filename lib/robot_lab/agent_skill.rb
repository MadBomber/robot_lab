# frozen_string_literal: true

require "yaml"

module RobotLab
  # Value object representing an AgentSkills.io skill folder.
  #
  # A skill is a directory containing SKILL.md with required front matter
  # fields (name, description) and optional scripts/, references/, assets/.
  class AgentSkill
    attr_reader :name, :description, :path, :capabilities

    # @param skill_md_path [String, Pathname] path to the SKILL.md file
    # @raise [ConfigurationError] if name or description is missing
    def initialize(skill_md_path)
      @path = Pathname.new(skill_md_path).dirname
      content = File.read(skill_md_path)
      front_matter, @_body = parse_skill_md(content)

      @name         = front_matter["name"]
      @description  = front_matter["description"]
      @capabilities = Capabilities.from_front_matter(front_matter)

      raise ConfigurationError, "SKILL.md at #{skill_md_path} missing 'name'"        if @name.to_s.strip.empty?
      raise ConfigurationError, "SKILL.md at #{skill_md_path} missing 'description'" if @description.to_s.strip.empty?
    end

    # Full instruction text from the SKILL.md body (below the front matter).
    def instructions
      @instructions ||= @_body.strip
    end

    # Pathnames of all files inside the scripts/ subdirectory, sorted.
    def scripts
      @scripts ||= begin
        dir = @path.join("scripts")
        dir.directory? ? dir.children.select(&:file?).sort : []
      end
    end

    # RobotLab::Tool instances wrapping each executable script.
    # Non-executable scripts are skipped with a warning.
    def script_tools
      @script_tools ||= scripts.filter_map do |script_path|
        ScriptTool.from_path(script_path, capabilities: @capabilities, skill_dir: @path.to_s)
      end
    end

    private

    # Split SKILL.md content into front matter Hash and body String.
    def parse_skill_md(content)
      if content.start_with?("---\n")
        parts = content.split(/^---\s*$/, 3)
        if parts.length >= 3
          fm = YAML.safe_load(parts[1])
          front_matter = fm.is_a?(Hash) ? fm : {}
          return [front_matter, parts[2]]
        end
      end
      [{}, content]
    end
  end
end
