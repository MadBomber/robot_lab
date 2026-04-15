#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 28: MCP Server Discovery
#
# When a robot has many MCP servers configured, connecting to all of them
# upfront is wasteful — some servers may be irrelevant to a particular query.
#
# MCP Server Discovery uses TF cosine similarity to select only the servers
# semantically relevant to the user's query, then connects only those.
#
# == Key config
#
#   robot = RobotLab.build(
#     mcp_discovery: true,    # ← enables semantic filtering
#     mcp: [ ... ]            # ← candidate servers, each with :description
#   )
#
# == Fallback behaviour
#
#   All servers are connected unchanged when:
#   - No server has a :description field
#   - The classifier gem is unavailable
#   - The query is blank or nil
#   - No server scores at or above the threshold (0.05 by default)
#
# This demo exercises MCP::ServerDiscovery directly — no LLM calls needed.
#
# Usage:
#   bundle exec ruby examples/28_mcp_discovery.rb

require_relative "../lib/robot_lab"

# Three representative MCP server configurations
SERVERS = [
  {
    name: "filesystem",
    description: "Read, write, and search local files and directories",
    transport: { type: "stdio", command: "mcp-server-filesystem" }
  },
  {
    name: "github",
    description: "GitHub repos, issues, pull requests, code search",
    transport: { type: "stdio", command: "mcp-server-github" }
  },
  {
    name: "brew",
    description: "Install, update, and manage macOS packages via Homebrew",
    transport: { type: "stdio", command: "mcp-server-brew" }
  }
].freeze

def show_query(label, query)
  selected = RobotLab::MCP::ServerDiscovery.select(query, from: SERVERS)
  names    = selected.map { |s| s[:name] }

  puts "  Query : #{query.inspect}"
  puts "  Match : #{names.inspect}"
  puts
end

puts "=" * 60
puts "Example 28: MCP Server Discovery"
puts "  Semantic server selection via TF cosine similarity"
puts "=" * 60
puts
puts "Candidate servers:"
SERVERS.each do |s|
  puts "  #{s[:name].ljust(12)} #{s[:description]}"
end
puts

puts "Discovery queries:"
puts "-" * 60
show_query("File ops",     "read my config file")
show_query("Package mgmt", "install imagemagick via homebrew")
show_query("Code review",  "list open pull requests on my repo")

puts "Fallback cases:"
puts "-" * 60

# No description → all servers returned
no_desc_servers = SERVERS.map { |s| s.except(:description) }
result = RobotLab::MCP::ServerDiscovery.select("install imagemagick", from: no_desc_servers)
puts "  No descriptions : returns all (#{result.size} servers)"

# Blank query → all servers returned
result = RobotLab::MCP::ServerDiscovery.select("", from: SERVERS)
puts "  Blank query     : returns all (#{result.size} servers)"

# Very high threshold → no match → fallback to all
result = RobotLab::MCP::ServerDiscovery.select("install imagemagick", from: SERVERS, threshold: 1.0)
puts "  High threshold  : returns all (#{result.size} servers) — no match above 1.0"

puts
puts "mcp_discovery: true on a Robot"
puts "-" * 60
puts <<~NOTE
  RobotLab.build(
    name: "assistant",
    mcp_discovery: true,
    mcp: [
      { name: "filesystem", description: "Read, write...", transport: { ... } },
      { name: "github",     description: "GitHub repos...", transport: { ... } },
      { name: "brew",       description: "Install packages...", transport: { ... } }
    ]
  )

  # Only the :brew server is connected for this message:
  robot.run("install imagemagick")
NOTE
puts "=" * 60
