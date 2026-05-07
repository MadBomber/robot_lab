# frozen_string_literal: true

require "pathname"

module RobotLab
  # Singleton registry that scans ~/.prompts/skills/ and provides
  # AgentSkill lookup by ID.
  #
  # Skills are loaded lazily on first access (thread-safe via Mutex).
  # Bad SKILL.md files (missing name/description) are skipped with a warning.
  class AgentSkillCatalog
    SKILLS_ROOT = Pathname.new(File.expand_path("~/.prompts/skills"))

    class << self
      # The process-level singleton instance (uses SKILLS_ROOT).
      def instance
        @instance ||= new(SKILLS_ROOT)
      end

      # Reset the singleton (used in tests to swap the skills root).
      def reset!
        @instance = nil
      end
    end

    # @param skills_root [String, Pathname] directory to scan for skill folders
    def initialize(skills_root = SKILLS_ROOT)
      @skills_root = Pathname.new(skills_root)
      @skills      = {}
      @mutex       = Mutex.new
      @loaded      = false
    end

    # Return the AgentSkill for the given ID, or nil if not found.
    #
    # @param id [Symbol, String] skill folder name
    # @return [AgentSkill, nil]
    def find(id)
      load!
      @skills[id.to_sym]
    end

    # All discovered AgentSkill objects.
    #
    # @return [Array<AgentSkill>]
    def all
      load!
      @skills.values
    end

    private

    def load!
      @mutex.synchronize { load_skills! unless @loaded }
    end

    def load_skills!
      @loaded = true
      return unless @skills_root.directory?

      @skills_root.each_child do |dir|
        next unless dir.directory?

        skill_file = dir.join("SKILL.md")
        next unless skill_file.exist?

        begin
          skill = AgentSkill.new(skill_file)
          @skills[skill.name.to_sym] = skill
        rescue ConfigurationError, Psych::SyntaxError => e
          RobotLab.config.logger.warn("AgentSkillCatalog: #{e.message}, skipping #{dir.basename}")
        end
      end
    end
  end
end
