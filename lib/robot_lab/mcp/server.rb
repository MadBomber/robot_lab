# frozen_string_literal: true

module RobotLab
  module MCP
    # The +RubyLLM::MCP+ subclass that {MCP.build} creates from a config Hash.
    #
    # Everything a server can do comes from ruby_llm: +tools+, +call+,
    # +resources+, +resource+, +prompts+, +prompt+, +instructions+, +version+,
    # +listen+, +close+, the OAuth flow, and so on. This subclass adds only:
    #
    # - a class-level +description+, used by {ServerDiscovery} to pick servers
    #   relevant to a message;
    # - +connected?+, true once the server has answered a +tools+ request and
    #   false again after +close+.
    #
    # Subclass it directly when you want the description macro:
    #
    #   class Brew < RobotLab::MCP::Server
    #     description "Install, update, and manage macOS packages via Homebrew"
    #     command "mcp-server-brew"
    #   end
    # :reek:InstanceVariableAssumption -- @description is a class-level DSL ivar set by the description macro
    #   and copied by inherited; it has no instance-side initializer by design.
    class Server < RubyLLM::MCP
      @description = nil

      class << self
        # Sets or reads a short description of what the server offers.
        #
        # @param value [String, nil]
        # @return [String, nil]
        def description(value = nil)
          return @description if value.nil?

          @description = value.to_s
        end

        def inherited(subclass) # :nodoc:
          super
          subclass.description(@description) if @description
        end
      end

      def initialize(context: nil, **inputs)
        super
        @connected = false
      end

      # @return [String] the class-level description, or an empty string
      def description
        self.class.description.to_s
      end

      # @return [Boolean] whether the server has answered a tools request since the last close
      def connected?
        @connected == true
      end

      # Lists the server's tools, connecting on the first call (see RubyLLM::MCP#tools).
      def tools
        super.tap { @connected = true }
      end

      # Closes the connection (see RubyLLM::MCP#close). The next request reconnects.
      def close
        @connected = false
        super
      end
    end
  end
end
