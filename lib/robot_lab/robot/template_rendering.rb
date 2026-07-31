# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    # Template loading, rendering, and front-matter extraction.
    #
    # Owns:    @expanded_skills, @pending_agent_skills, @agent_skill_store
    # Reads:   @chat, @template, @build_context, @name, @name_from_constructor, @description, @local_tools, @mcp_config, @config
    # Contract: called during initialize after assign_identity_ivars and build_effective_config
    module TemplateRendering
      # Front matter keys that map to chat configuration methods
      FRONT_MATTER_CONFIG_KEYS = %i[
        model temperature top_p top_k max_tokens
        presence_penalty frequency_penalty stop
      ].freeze

      # Front matter keys for robot identity and capabilities.
      # Note: uses `robot_name` because PM::Metadata reserves `name` for the filename.
      FRONT_MATTER_EXTRA_KEYS = %i[tools mcp robot_name description skills].freeze

      # Apply a prompt_manager template to the robot's chat
      #
      # @param template_id [Symbol, String] the template identifier
      # @param context [Hash] variables to pass to the template
      # @return [self]
      def with_template(template_id, **context)
        @template = template_id.to_sym
        @build_context = context
        apply_template_to_chat(context)
        self
      end

      private

      # Apply a prompt_manager template to the persistent chat.
      # If required parameters are missing, applies front matter config but
      # defers rendering until run time when all values are available.
      def apply_template_to_chat(context)
        parsed = PM.parse(@template)

        # Extract extra config from front matter (name, description, tools, mcp)
        apply_front_matter_extras(parsed.metadata)

        # Extract LLM config from front matter and apply to chat.
        # Front matter is the base; @config (from constructor kwargs) overrides.
        fm_config = RunConfig.from_front_matter(parsed.metadata)
        effective = fm_config.merge(@config)
        effective.apply_to(@chat, provider: @provider, assume_model_exists: !@provider.nil?)

        # Resolve context (could be a Proc)
        resolved_ctx = resolve_context(context, network: nil)

        # Render the template body with context
        begin
          rendered = parsed.to_s(**resolved_ctx)
          @chat.with_instructions(rendered)
        rescue ArgumentError => e
          raise unless e.message.start_with?("Missing required parameters:")

          # Required parameters not yet available; template will be
          # fully rendered at run time via rerender_template.
        end
      end

      # Re-render the template with run-time context merged into build-time context.
      # prompt_manager parameters may be required (null) and only available at run time.
      #
      # Re-rendering replaces the system message, so the inline system_prompt must be
      # re-appended here exactly as apply_system_prompt does at construction --
      # otherwise it would be silently dropped on any run that supplies context.
      def rerender_template(run_context)
        merged = (@build_context || {}).merge(run_context)
        resolved_ctx = resolve_context(merged, network: nil)

        if @expanded_skills&.any?
          # Re-render all skill bodies + main template body with merged context
          bodies = @expanded_skills.map do |skill_id|
            parsed = PM.parse(skill_id)
            render_body(parsed, resolved_ctx)
          end.compact

          if @template
            parsed = PM.parse(@template)
            body = render_body(parsed, resolved_ctx)
            bodies << body if body
          end

          @chat.with_instructions(with_system_prompt_appended(bodies.join("\n\n")))
        else
          parsed = PM.parse(@template)
          rendered = parsed.to_s(**resolved_ctx)
          @chat.with_instructions(with_system_prompt_appended(rendered))
        end
      end

      # Append the inline system_prompt to freshly rendered template text.
      #
      # @param rendered [String] newly rendered template body
      # @return [String] rendered text with system_prompt appended, if one is set
      def with_system_prompt_appended(rendered)
        return rendered unless @system_prompt

        [rendered, @system_prompt].reject { |s| s.to_s.empty? }.join("\n\n")
      end

      # Orchestrate skill expansion and template application.
      #
      # @param skill_ids [Array<Symbol>] skill IDs from constructor + front matter
      # @param context [Hash, Proc] variables to pass to all templates
      def apply_skills_and_template_to_chat(skill_ids, context)
        bodies, accumulated_config, extras = collect_prompt_content(skill_ids, context)
        apply_prompt_to_chat(bodies, accumulated_config, extras)
      end

      # Expand skills and render all bodies, configs, and extras into plain data.
      # Pure computation — reads ivars but does not mutate @chat.
      #
      # @return [Array(Array<String>, RunConfig, Hash)] bodies, merged config, extras hash
      def collect_prompt_content(skill_ids, context)
        visited = Set.new
        visited.add(@template) if @template
        @expanded_skills = expand_skills(skill_ids, visited)

        extras = {}
        accumulated_config = RunConfig.new
        bodies = []
        resolved_ctx = resolve_context(context, network: nil)

        @expanded_skills.each do |skill_id|
          parsed = PM.parse(skill_id)
          accumulate_extras(parsed.metadata, extras)
          accumulated_config = accumulated_config.merge(RunConfig.from_front_matter(parsed.metadata))
          body = render_body(parsed, resolved_ctx)
          bodies << body if body
        end

        if @template
          parsed = PM.parse(@template)
          accumulate_extras(parsed.metadata, extras)
          accumulated_config = accumulated_config.merge(RunConfig.from_front_matter(parsed.metadata))
          body = render_body(parsed, resolved_ctx)
          bodies << body if body
        end

        [bodies, accumulated_config, extras]
      end

      # Apply collected prompt content to @chat.
      # Pure mutation — takes plain data and writes to @chat.
      #
      # @param bodies [Array<String>] rendered template bodies
      # @param accumulated_config [RunConfig] merged skill + template config
      # @param extras [Hash] accumulated front-matter extras (name, description, tools, mcp)
      def apply_prompt_to_chat(bodies, accumulated_config, extras)
        apply_accumulated_extras(extras)

        effective = accumulated_config.merge(@config)
        effective.apply_to(@chat, provider: @provider, assume_model_exists: !@provider.nil?)

        combined = bodies.join("\n\n")
        @chat.with_instructions(combined) unless combined.empty?
      end

      # Recursively expand skill IDs depth-first.
      # Checks AgentSkillCatalog first; falls back to PM template lookup.
      # Returns a flat Array<Symbol> in processing order (deepest first).
      #
      # @param skill_ids [Array<Symbol>] skill IDs to expand
      # @param visited [Set<Symbol>] already-visited IDs for cycle detection
      # @return [Array<Symbol>] flat ordered list of skill IDs
      def expand_skills(skill_ids, visited = Set.new)
        expand_skills_with_catalog(skill_ids, visited, AgentSkillCatalog.instance)
      end

      # Recursively expand skill IDs depth-first, using the given catalog.
      # AgentSkills folder format takes priority over PM template lookup.
      # Catalog hits are stored in @pending_agent_skills / @agent_skill_store
      # and are NOT included in the returned Array (they are handled separately).
      #
      # @param skill_ids [Array<Symbol>] skill IDs to expand
      # @param visited [Set<Symbol>] already-visited IDs for cycle detection
      # @param catalog [AgentSkillCatalog] catalog to check first
      # @return [Array<Symbol>] flat ordered list of PM-based skill IDs
      def expand_skills_with_catalog(skill_ids, visited, catalog)
        result = []

        skill_ids.each do |skill_id|
          skill_id = skill_id.to_sym

          if visited.include?(skill_id)
            RobotLab.config.logger.warn(
              "Robot '#{@name}': skill cycle detected at '#{skill_id}', skipping"
            )
            next
          end

          visited.add(skill_id)

          # Check catalog first: AgentSkills folder format takes priority
          if (agent_skill = catalog.find(skill_id))
            @pending_agent_skills ||= []
            unless defined?(RobotLab::DocumentStore)
              raise LoadError,
                    "robot_lab-document_store is required to use AgentSkill catalogs. " \
                    "Add `gem 'robot_lab-document_store'` to your Gemfile."
            end
            @agent_skill_store ||= RobotLab::DocumentStore.new
            @pending_agent_skills << agent_skill
            @agent_skill_store.store(agent_skill.name.to_sym, agent_skill.description)
            next
          end

          # Fall back to PM template (existing behavior)
          parsed = PM.parse(skill_id)
          nested = extract_skills_from_metadata(parsed.metadata)

          result.concat(expand_skills_with_catalog(nested, visited, catalog)) if nested.any?

          result << skill_id
        end

        result
      end

      # Extract skills array from metadata.
      #
      # @param metadata [PM::Metadata] front matter metadata
      # @return [Array<Symbol>]
      def extract_skills_from_metadata(metadata)
        return [] unless metadata.respond_to?(:skills) && metadata.skills

        Array(metadata.skills).map(&:to_sym)
      end

      # Accumulate extras from metadata into a hash.
      # Later calls overwrite earlier values (last-write-wins).
      #
      # @param metadata [PM::Metadata] front matter metadata
      # @param extras [Hash] accumulator hash
      def accumulate_extras(metadata, extras)
        if metadata.respond_to?(:robot_name) && metadata.robot_name
          extras[:robot_name] = metadata.robot_name.to_s
        end

        if metadata.respond_to?(:description) && metadata.description
          extras[:description] = metadata.description.to_s
        end

        if metadata.respond_to?(:tools) && metadata.tools.is_a?(Array)
          extras[:tools] = metadata.tools
        end

        return unless metadata.respond_to?(:mcp) && metadata.mcp.is_a?(Array)
        extras[:mcp] = metadata.mcp.map { |m| m.is_a?(Hash) ? m.transform_keys(&:to_sym) : m }
      end

      # Apply accumulated extras to the robot, respecting constructor precedence.
      #
      # @param extras [Hash] accumulated extras from skills + main template
      def apply_accumulated_extras(extras)
        if extras[:robot_name] && !@name_from_constructor
          @name = extras[:robot_name]
        end

        if extras[:description] && @description.nil?
          @description = extras[:description]
        end

        if extras[:tools] && @local_tools.empty?
          @local_tools = resolve_frontmatter_tools(extras[:tools])
        end

        return unless extras[:mcp] && ToolConfig.none_value?(@mcp_config)
        @mcp_config = extras[:mcp]
      end

      # Extract identity and capability keys from front matter metadata.
      # Constructor-provided values take precedence over frontmatter.
      def apply_front_matter_extras(metadata)
        if metadata.respond_to?(:robot_name) && metadata.robot_name && !@name_from_constructor
          @name = metadata.robot_name.to_s
        end

        if metadata.respond_to?(:description) && metadata.description && @description.nil?
          @description = metadata.description.to_s
        end

        if metadata.respond_to?(:tools) && metadata.tools.is_a?(Array) && @local_tools.empty?
          @local_tools = resolve_frontmatter_tools(metadata.tools)
        end

        return unless metadata.respond_to?(:mcp) && metadata.mcp.is_a?(Array) && ToolConfig.none_value?(@mcp_config)
        @mcp_config = metadata.mcp.map { |m| m.is_a?(Hash) ? m.transform_keys(&:to_sym) : m }
      end

      # Render a parsed template body, returning nil if required params are missing.
      #
      # @param parsed [PM::Parsed] the parsed template
      # @param context [Hash] resolved context variables
      # @return [String, nil]
      def render_body(parsed, context)
        parsed.to_s(**context)
      rescue ArgumentError => e
        raise unless e.message.start_with?("Missing required parameters:")

        nil
      end

      # Resolve string tool names from frontmatter to Ruby constants.
      # Tool subclasses are instantiated; instances are used as-is.
      # Unresolvable names are skipped with a warning.
      def resolve_frontmatter_tools(tool_names)
        tool_names.filter_map do |name|
          case name
          when String
            begin
              const = Object.const_get(name)
              const.is_a?(Class) && const < RubyLLM::Tool ? const.new : const
            rescue NameError
              RobotLab.config.logger.warn("Robot '#{@name}': tool '#{name}' not found, skipping")
              nil
            end
          when Class
            name.new
          else
            name
          end
        end
      end

      def resolve_context(context, network:)
        case context
        when Proc then context.call(network: network)
        when Hash then context
        else {}
        end
      end
    end
  end
end
