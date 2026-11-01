# frozen_string_literal: true

module RobotLab
  module MCP
    # The MCP servers a robot knows, keyed by server name.
    #
    # A robot resolves its +mcp+ config on every run. The registry makes that
    # cheap and side-effect free: adding the same config Hash (by value), the
    # same +RubyLLM::MCP+ instance, or the same class again returns the server
    # already built, so a stdio server's process is started once and reused
    # across runs. Adding a different spec under an existing name closes the
    # old server and replaces it.
    #
    # Servers are closed only by {#delete}, {#clear}, or the robot's
    # +disconnect+; selecting a subset of servers for one run never closes
    # the others.
    class Registry
      include Enumerable

      def initialize
        @servers = {}
        @specs   = {}
      end

      # Register a server (or return the one already registered for +spec+).
      #
      # @param spec [Hash, RubyLLM::MCP, Class<RubyLLM::MCP>]
      # @return [RubyLLM::MCP]
      def add(spec)
        key      = MCP.name_of(spec).to_sym
        existing = @servers[key]
        return existing if existing && same_spec?(key, spec, existing)

        existing&.close
        @specs[key]   = spec
        @servers[key] = MCP.build(spec)
      end

      # @param name [String, Symbol]
      # @return [RubyLLM::MCP, nil]
      def [](name)
        @servers[name.to_sym]
      end

      def key?(name)
        @servers.key?(name.to_sym)
      end

      def each(&)
        @servers.each_value(&)
      end

      # @return [Array<String>] registered server names, in registration order
      def names
        @servers.keys.map(&:to_s)
      end

      def empty?
        @servers.empty?
      end

      def size
        @servers.size
      end

      # Close and forget one server.
      #
      # @param name [String, Symbol]
      # @return [RubyLLM::MCP, nil] the removed server
      def delete(name)
        key = name.to_sym
        @specs.delete(key)
        server = @servers.delete(key)
        server&.close
        server
      end

      # Close and forget every server.
      #
      # @return [self]
      def clear
        each(&:close)
        @servers.clear
        @specs.clear
        self
      end

      private

      def same_spec?(key, spec, existing)
        case spec
        when RubyLLM::MCP then existing.equal?(spec)
        when Hash         then @specs[key] == spec
        else                   @specs[key].equal?(spec)
        end
      end
    end
  end
end
