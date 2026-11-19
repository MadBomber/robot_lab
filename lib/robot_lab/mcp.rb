# frozen_string_literal: true

module RobotLab
  # robot_lab's thin layer over ruby_llm's built-in MCP client.
  #
  # ruby_llm 2.1 ships +RubyLLM::MCP+: a class that describes one Model
  # Context Protocol server (stdio or Streamable HTTP), connects lazily, and
  # exposes the server's tools, resources, prompts, OAuth flow, elicitation
  # and long-running tasks. robot_lab adds only what a robot needs on top:
  #
  # - {MCP.build} turns a robot_lab config Hash (the shape used in templates,
  #   +RunConfig#mcp+ and +RobotLab.build(mcp: [...])+) into a +RubyLLM::MCP+
  #   instance, and passes instances and subclasses through unchanged.
  # - {MCP::Server} is the +RubyLLM::MCP+ subclass those hashes become; it
  #   carries a +description+ for {MCP::ServerDiscovery} and a +connected?+ flag.
  # - {MCP::Registry} holds a robot's servers by name so repeated runs reuse
  #   one connection (and one stdio process) per server.
  #
  # @example A config hash
  #   RobotLab::MCP.build(
  #     name: "filesystem",
  #     transport: { type: "stdio", command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "."] },
  #     timeout: 30, only: %w[read_file list_directory]
  #   )
  #
  # @example A RubyLLM::MCP subclass
  #   class GitHub < RubyLLM::MCP
  #     command "github-mcp-server", "stdio"
  #     env GITHUB_PERSONAL_ACCESS_TOKEN: ENV["GITHUB_PERSONAL_ACCESS_TOKEN"]
  #     requires_approval if: :destructive?
  #   end
  #   RobotLab.build(name: "dev", mcp: [GitHub])
  module MCP
    # Transport types that map onto ruby_llm's Streamable HTTP client.
    HTTP_TYPES = %w[streamable-http streamable_http http https].freeze

    # Transport types the old robot_lab client offered that ruby_llm does not.
    UNSUPPORTED_TYPES = %w[sse ws websocket].freeze

    # Keys consumers attach for their own routing/grouping; never errors.
    IGNORED_KEYS = %i[topics independent group session_id auth_provider].freeze

    # Keys that may appear nested under +transport:+ or flat at the top level.
    TRANSPORT_KEYS = %i[type command args env url headers bearer_token oauth directory cwd].freeze

    # Keys the factory understands at the top level of a config hash.
    SETTING_KEYS = %i[name description transport timeout prefix only except
                      requires_approval defer log_level input_requests extensions].freeze

    # Errors a server can raise while connecting or listing tools. A robot
    # rescues these per server so one dead server does not abort a run.
    CONNECT_ERRORS = [RubyLLM::Error, RubyLLM::ConfigurationError, SystemCallError, IOError, ArgumentError].freeze

    module_function

    # Build a server from a config Hash, or pass through an instance or class.
    # A String names a +RubyLLM::MCP+ subclass constant, the form template
    # front matter uses (+mcp: ["SharedTools::MCP::GitHub"]+).
    #
    # @param spec [Hash, RubyLLM::MCP, Class<RubyLLM::MCP>, String]
    # @return [RubyLLM::MCP]
    # @raise [MCPError] for an unusable spec
    def build(spec)
      case (spec = resolve(spec))
      when RubyLLM::MCP then spec
      when Class
        raise MCPError, "#{spec} is not a RubyLLM::MCP subclass" unless spec <= RubyLLM::MCP

        spec.new
      when Hash then define(spec).new
      else
        raise MCPError, "Cannot build an MCP server from #{spec.class}; " \
                        'pass a Hash, a RubyLLM::MCP, a RubyLLM::MCP subclass, or its constant name'
      end
    end

    # Turn a String spec into the +RubyLLM::MCP+ subclass it names; any other
    # spec is returned unchanged.
    #
    # @param spec [Hash, RubyLLM::MCP, Class<RubyLLM::MCP>, String]
    # @return [Hash, RubyLLM::MCP, Class<RubyLLM::MCP>]
    # @raise [MCPError] when the String does not name a RubyLLM::MCP subclass
    def resolve(spec)
      return spec unless spec.is_a?(String)

      klass = begin
        Object.const_get(spec)
      rescue NameError
        raise MCPError, "MCP server class '#{spec}' is not defined; require the file that defines it"
      end
      raise MCPError, "#{spec} is not a RubyLLM::MCP subclass" unless klass.is_a?(Class) && klass <= RubyLLM::MCP

      klass
    end

    # Turn a config Hash into an anonymous {Server} subclass with ruby_llm's
    # class-level DSL applied. Public so hosts can build classes once and
    # instantiate them per request (ruby_llm's recommended pattern).
    #
    # @param config [Hash]
    # @return [Class<Server>]
    # @raise [MCPError] when the hash has no name, no usable transport, or an unsupported one
    def define(config)
      config = normalize(config)
      klass  = Class.new(Server)
      apply_settings(klass, config)
      klass
    end

    # The name a spec will be registered under.
    #
    # @param spec [Hash, RubyLLM::MCP, Class<RubyLLM::MCP>, String]
    # @return [String]
    # @raise [MCPError] when the spec has no name
    def name_of(spec)
      name = case (spec = resolve(spec))
             when Hash then spec[:name] || spec['name']
             when Class then spec.default_name
             when RubyLLM::MCP then spec.name
             end
      raise MCPError, "MCP server spec has no name: #{spec.inspect}" if name.nil? || name.to_s.strip.empty?

      name.to_s
    end

    # Normalize a timeout to seconds. Values of 1000 or more are taken to be
    # milliseconds (the convention aia and older configs used); the result is
    # never below one second.
    #
    # @param value [Numeric, String]
    # @return [Float]
    def seconds(value)
      secs = value.to_f
      secs /= 1000.0 if secs >= 1000
      [secs, 1.0].max
    end

    # --- internals (module_function keeps them callable as MCP.xxx for the Class.new body) ---

    # Symbolize keys, fold flat transport keys into +:transport+, require a name.
    # :reek:TooManyStatements -- one linear normalization pass over the hash shape.
    def normalize(config)
      config = config.to_h.transform_keys(&:to_sym)
      name_of(config)

      raw = config[:transport]
      transport = case raw
                  when Hash           then raw.transform_keys(&:to_sym)
                  when String, Symbol then { type: raw.to_s }
                  when nil            then {}
                  else                     raw # a transport object (duck type)
                  end
      if transport.is_a?(Hash)
        TRANSPORT_KEYS.each { |key| transport[key] = config[key] if config.key?(key) && !transport.key?(key) }
      end
      config.merge(transport: transport)
    end

    def apply_settings(klass, config)
      klass.default_name = config[:name].to_s
      klass.description(config[:description]) if config[:description]
      apply_transport(klass, config)
      apply_tool_shaping(klass, config)
      log_ignored_keys(config)
    end

    # :reek:TooManyStatements -- each optional setting is one guarded DSL call.
    def apply_tool_shaping(klass, config)
      klass.timeout(seconds(config[:timeout]))      if config[:timeout]
      klass.prefix(config[:prefix])                 if config[:prefix]
      klass.only(*Array(config[:only]))             if config[:only]
      klass.except(*Array(config[:except]))         if config[:except]
      klass.log_level(config[:log_level])           if config[:log_level]
      klass.input_requests(*Array(config[:input_requests])) if config.key?(:input_requests)
      apply_extensions(klass, config[:extensions])
      apply_approvals(klass, config[:requires_approval])
      apply_deferral(klass, config[:defer])
    end

    def apply_transport(klass, config)
      transport = config[:transport]
      return klass.transport(transport) if transport_object?(transport)

      case (type = transport_type(config, transport))
      when 'stdio'            then apply_stdio(klass, config, transport)
      when *HTTP_TYPES        then apply_http(klass, config, transport)
      when *UNSUPPORTED_TYPES then raise MCPError, unsupported_transport_message(config[:name], type)
      else raise MCPError, "Unknown MCP transport type '#{type}' for server '#{config[:name]}'"
      end
    end

    def transport_object?(transport)
      !transport.is_a?(Hash) && transport.respond_to?(:request) && transport.respond_to?(:close)
    end

    def transport_type(config, transport)
      type = transport[:type]&.to_s&.downcase
      return type unless type.nil? || type.empty?
      return 'stdio' if transport[:command]
      return 'streamable-http' if transport[:url]

      raise MCPError, "MCP server '#{config[:name]}' needs a command (stdio) or a url (Streamable HTTP)"
    end

    def apply_stdio(klass, config, transport)
      command = transport[:command]
      raise MCPError, "MCP server '#{config[:name]}' uses stdio but has no command" if command.nil?

      klass.command(*(Array(command) + Array(transport[:args])).map(&:to_s))
      env = transport[:env]
      klass.env(**env.to_h.transform_keys(&:to_sym)) if env && !env.empty?
      directory = transport[:directory] || transport[:cwd]
      klass.directory(directory.to_s) if directory
    end

    # :reek:TooManyStatements -- url, headers, bearer token and oauth are four independent guarded calls.
    def apply_http(klass, config, transport)
      url = transport[:url]
      raise MCPError, "MCP server '#{config[:name]}' uses Streamable HTTP but has no url" if url.nil?

      klass.url(url.to_s)
      transport[:headers].to_h.each { |header, value| klass.header(header.to_s, value) }
      klass.bearer_token(transport[:bearer_token]) if transport[:bearer_token]
      apply_oauth(klass, transport[:oauth])
    end

    def apply_oauth(klass, oauth)
      case oauth
      when nil, false then nil
      when true       then klass.oauth
      else                 klass.oauth(**oauth_settings(oauth))
      end
    end

    # Symbolize keys, and the grant: ruby_llm compares it against Symbols
    # (:client_credentials, ...) but YAML configs give Strings.
    def oauth_settings(oauth)
      settings = oauth.to_h.transform_keys(&:to_sym)
      settings[:grant] = settings[:grant].to_sym if settings[:grant].is_a?(String)
      settings
    end

    def apply_extensions(klass, extensions)
      case extensions
      when nil then nil
      when Hash
        extensions.each { |name, settings| klass.extension(extension_name(name), **settings.to_h.transform_keys(&:to_sym)) }
      else Array(extensions).each { |name| klass.extension(extension_name(name)) }
      end
    end

    # ruby_llm takes a Symbol for the extensions it knows (:tasks, :apps) and
    # a vendor-prefixed String for the rest; YAML configs give Strings for both.
    def extension_name(name)
      name.to_s.include?('/') ? name.to_s : name.to_sym
    end

    def apply_approvals(klass, value)
      case value
      when nil, false then nil
      when true       then klass.requires_approval
      when Hash       then klass.requires_approval(**value.transform_keys(&:to_sym))
      else                 klass.requires_approval(*Array(value).map(&:to_s))
      end
    end

    def apply_deferral(klass, value)
      case value
      when nil, false then nil
      when true       then klass.defer
      else                 klass.defer(*Array(value).map(&:to_s))
      end
    end

    def log_ignored_keys(config)
      unknown = config.keys - SETTING_KEYS - TRANSPORT_KEYS - IGNORED_KEYS
      return if unknown.empty?

      RobotLab.config.logger.debug { "MCP server '#{config[:name]}': ignoring unknown keys #{unknown.join(', ')}" }
    end

    def unsupported_transport_message(name, type)
      "MCP server '#{name}' uses transport '#{type}', which ruby_llm 2.1 does not provide " \
        '(only stdio and Streamable HTTP). Point the server at its Streamable HTTP endpoint, ' \
        'or pass a transport: object that responds to request/notify/cancel/close.'
    end
  end
end
