# frozen_string_literal: true

module RobotLab
  module MCP
    # Selects relevant MCP servers for a given user query using TF cosine
    # similarity between the query and each server's topic text
    # (name + description).
    #
    # This is used as a fallback mechanism when a robot has many MCP servers
    # configured but only some are relevant to a particular user message.
    # Instead of connecting to all servers upfront, the robot can enable
    # discovery so only the semantically matching servers are connected.
    #
    # == Usage
    #
    #   robot = RobotLab.build(
    #     name: "assistant",
    #     mcp_discovery: true,
    #     mcp: [
    #       {
    #         name: "filesystem",
    #         description: "Read, write, and search local files and directories",
    #         transport: { type: "stdio", command: "mcp-server-fs" }
    #       },
    #       {
    #         name: "github",
    #         description: "GitHub repos, issues, pull requests, code search",
    #         transport: { type: "stdio", command: "mcp-server-github" }
    #       },
    #       {
    #         name: "brew",
    #         description: "Install, update, and manage macOS packages via Homebrew",
    #         transport: { type: "stdio", command: "mcp-server-brew" }
    #       }
    #     ]
    #   )
    #
    #   # Discovery connects only the :brew server for this query:
    #   robot.run("install imagemagick")
    #
    # == Fallback Behaviour
    #
    # The full server list is returned unchanged when:
    # - No server has a +:description+ field
    # - The 'classifier' gem is unavailable
    # - The query is blank
    # - No server scores at or above +threshold+ (minimum relevance)
    #
    # @api private
    module ServerDiscovery
      # Minimum cosine similarity score for a server to be considered relevant.
      # Low by design — server descriptions are short, so scores are naturally
      # low even for on-topic queries.
      DEFAULT_THRESHOLD = 0.05

      # Select MCP servers relevant to the given query.
      #
      # @param query     [String]          user message or intent
      # @param from      [Array<Hash, MCP::Server>] candidate server configs
      # @param threshold [Float]           minimum cosine score (default 0.05)
      # @return [Array<Hash, MCP::Server>] matching servers, or +from+ as
      #   fallback when no match is found
      def self.select(query, from:, threshold: DEFAULT_THRESHOLD)
        return from if from.empty?
        return from if query.to_s.strip.empty?
        return from unless any_descriptions?(from)

        TextAnalysis.require_classifier!

        scored = from.map { |server| [server, score(query, server)] }
        matches = scored.select { |_, s| s >= threshold }.map(&:first)

        matches.empty? ? from : matches
      rescue DependencyError
        # Classifier gem not available — connect to all servers
        from
      end

      # @param servers [Array<Hash, MCP::Server>]
      def self.any_descriptions?(servers)
        servers.any? { |s| !description_for(s).empty? }
      end

      # Build the topic string used for similarity scoring: name + description.
      #
      # @param server [Hash, MCP::Server]
      # @return [String]
      def self.topic_text(server)
        name = server.is_a?(Hash) ? server[:name].to_s : server.name.to_s
        "#{name} #{description_for(server)}".strip
      end

      # @param server [Hash, MCP::Server]
      # @return [String] description or empty string
      def self.description_for(server)
        desc = server.is_a?(Hash) ? server[:description] : server.respond_to?(:description) && server.description
        desc.to_s.strip
      end

      # @param query  [String]
      # @param server [Hash, MCP::Server]
      # @return [Float] cosine similarity in [0.0, 1.0]
      def self.score(query, server)
        TextAnalysis.tf_cosine_similarity(query, topic_text(server))
      end
    end
  end
end
