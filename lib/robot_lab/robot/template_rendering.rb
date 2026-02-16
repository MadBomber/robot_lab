# frozen_string_literal: true

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
      FRONT_MATTER_EXTRA_KEYS = %i[tools mcp robot_name description].freeze

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

        # Extract and apply LLM config to the chat (model, temperature, etc.)
        apply_front_matter_config(parsed.metadata)

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
        parsed = PM.parse(@template)
        resolved_ctx = resolve_context(merged, network: nil)
        rendered = parsed.to_s(**resolved_ctx)
        @chat.with_instructions(rendered)
      end


      # Extract whitelisted config from front matter and apply to chat
      def apply_front_matter_config(metadata)
        FRONT_MATTER_CONFIG_KEYS.each do |key|
          value = metadata.respond_to?(key) ? metadata.send(key) : nil
          next unless value

          method = :"with_#{key}"
          @chat.public_send(method, value) if @chat.respond_to?(method)
        end

        # Handle model specially (may need with_model)
        return unless metadata.respond_to?(:model) && metadata.model

        @chat.with_model(metadata.model)
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
