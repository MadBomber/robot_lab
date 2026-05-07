# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    # Prepended module that intercepts run() to inject relevant AgentSkills.io
    # skills into the system prompt and tool list for the duration of each call.
    #
    # Skills are matched by embedding similarity between the incoming message
    # and each pending skill's description (via DocumentStore/fastembed).
    # Injected content is fully restored in an ensure block after run() returns.
    module AgentSkillMatching
      SIMILARITY_THRESHOLD = 0.70

      def run(message = nil, **kwargs, &block)
        @_active_agent_skills = match_agent_skills(message.to_s)

        if @_active_agent_skills.any?
          @_agent_skill_original_instructions = current_agent_skill_instructions
          prepend_skill_instructions(@_active_agent_skills)
          @_agent_skill_injected_tools = @_active_agent_skills.flat_map(&:script_tools).compact
          @local_tools = @local_tools + @_agent_skill_injected_tools
        end

        super(message, **kwargs, &block)
      ensure
        if @_active_agent_skills&.any?
          @local_tools = @local_tools - (@_agent_skill_injected_tools || [])
          @chat.with_instructions(@_agent_skill_original_instructions.to_s)
        end
        @_active_agent_skills               = nil
        @_agent_skill_original_instructions = nil
        @_agent_skill_injected_tools        = nil
      end

      # Override to re-inject skill instructions after template re-render replaces
      # the system prompt during a run() call with runtime kwargs.
      def rerender_template(run_context)
        super
        return unless @_active_agent_skills&.any?

        @_agent_skill_original_instructions = current_agent_skill_instructions
        prepend_skill_instructions(@_active_agent_skills)
      end

      private

      # Find pending AgentSkills whose descriptions are semantically similar to message.
      #
      # @param message [String]
      # @param threshold [Float] cosine similarity cutoff (default SIMILARITY_THRESHOLD)
      # @return [Array<AgentSkill>]
      def match_agent_skills(message, threshold: SIMILARITY_THRESHOLD)
        return [] if @pending_agent_skills.nil? || @pending_agent_skills.empty?

        results = @agent_skill_store.search(message, limit: @pending_agent_skills.size)
        results
          .select { |r| r[:score] >= threshold }
          .filter_map { |r| @pending_agent_skills.find { |s| s.name.to_sym == r[:key] } }
      rescue => e
        RobotLab.config.logger.warn(
          "Robot '#{@name}': AgentSkill embedding failed: #{e.message}"
        )
        []
      end

      # Prepend skill instructions before existing system prompt content.
      #
      # @param skills [Array<AgentSkill>]
      def prepend_skill_instructions(skills)
        skill_content = skills.map(&:instructions).join("\n\n")
        base          = @_agent_skill_original_instructions.to_s
        combined      = [skill_content, base].reject(&:empty?).join("\n\n")
        @chat.with_instructions(combined)
      end

      # Inject script tools and snapshot instructions before injection.
      #
      # @param skills [Array<AgentSkill>]
      def inject_agent_skills(skills)
        @_active_agent_skills               = skills
        @_agent_skill_original_instructions = current_agent_skill_instructions
        prepend_skill_instructions(skills)
        @_agent_skill_injected_tools = skills.flat_map(&:script_tools).compact
        @local_tools = @local_tools + @_agent_skill_injected_tools
      end

      # Remove injected tools and restore original system prompt.
      def restore_after_agent_skills
        @local_tools = @local_tools - (@_agent_skill_injected_tools || [])
        @chat.with_instructions(@_agent_skill_original_instructions.to_s)
        @_active_agent_skills               = nil
        @_agent_skill_original_instructions = nil
        @_agent_skill_injected_tools        = nil
      end

      # Read the current system message content from the underlying chat.
      #
      # @return [String, nil]
      def current_agent_skill_instructions
        messages = @chat.instance_variable_get(:@messages)
        sys = messages&.find { |m| m.role.to_s == "system" }
        sys&.content
      end
    end
  end
end
