# frozen_string_literal: true

require 'set'

module RobotLab
  class Robot < RubyLLM::Agent
    # Template loading, rendering, and front-matter extraction.
    #
    # Expects the including class to provide:
    #   @chat, @template, @build_context, @name, @name_from_constructor,
    #   @description, @local_tools, @mcp_config
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
        effective.apply_to(@chat)

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

          combined = bodies.join("\n\n")
          @chat.with_instructions(combined)
        else
          parsed = PM.parse(@template)
          rendered = parsed.to_s(**resolved_ctx)
          @chat.with_instructions(rendered)
        end
      end


      # Orchestrate skill expansion and template application.
      #
      # @param skill_ids [Array<Symbol>] skill IDs from constructor + front matter
      # @param context [Hash, Proc] variables to pass to all templates
      def apply_skills_and_template_to_chat(skill_ids, context)
        visited = Set.new
        # Prevent skills from pulling in the main template
        visited.add(@template) if @template

        @expanded_skills = expand_skills(skill_ids, visited)

        extras = {}
        accumulated_config = RunConfig.new
        bodies = []

        resolved_ctx = resolve_context(context, network: nil)

        # Process each expanded skill
        @expanded_skills.each do |skill_id|
          parsed = PM.parse(skill_id)
          accumulate_extras(parsed.metadata, extras)
          fm_config = RunConfig.from_front_matter(parsed.metadata)
          accumulated_config = accumulated_config.merge(fm_config)
          body = render_body(parsed, resolved_ctx)
          bodies << body if body
        end

        # Process main template if present
        if @template
          parsed = PM.parse(@template)
          accumulate_extras(parsed.metadata, extras)
          fm_config = RunConfig.from_front_matter(parsed.metadata)
          accumulated_config = accumulated_config.merge(fm_config)
          body = render_body(parsed, resolved_ctx)
          bodies << body if body
        end

        # Apply accumulated extras (respects constructor precedence)
        apply_accumulated_extras(extras)

        # Constructor config overrides skill + template config
        effective = accumulated_config.merge(@config)
        effective.apply_to(@chat)

        # Set instructions once with all bodies joined
        combined = bodies.join("\n\n")
        @chat.with_instructions(combined) unless combined.empty?
      end


      # Recursively expand skill IDs depth-first.
      # Returns a flat Array<Symbol> in processing order (deepest first).
      #
      # @param skill_ids [Array<Symbol>] skill IDs to expand
      # @param visited [Set<Symbol>] already-visited IDs for cycle detection
      # @return [Array<Symbol>] flat ordered list of skill IDs
      def expand_skills(skill_ids, visited = Set.new)
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

          # Parse the skill template and check for nested skills
          parsed = PM.parse(skill_id)
          nested = extract_skills_from_metadata(parsed.metadata)

          # Recurse on nested skills first (depth-first)
          result.concat(expand_skills(nested, visited)) if nested.any?

          # Then append this skill
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

        if metadata.respond_to?(:mcp) && metadata.mcp.is_a?(Array)
          extras[:mcp] = metadata.mcp.map { |m| m.is_a?(Hash) ? m.transform_keys(&:to_sym) : m }
        end
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

        if extras[:mcp] && ToolConfig.none_value?(@mcp_config)
          @mcp_config = extras[:mcp]
        end
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

        if metadata.respond_to?(:mcp) && metadata.mcp.is_a?(Array) && ToolConfig.none_value?(@mcp_config)
          @mcp_config = metadata.mcp.map { |m| m.is_a?(Hash) ? m.transform_keys(&:to_sym) : m }
        end
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
