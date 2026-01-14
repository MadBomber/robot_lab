#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 4: MCP (Model Context Protocol) Integration
#
# Demonstrates connecting to MCP servers for external tools.
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/04_mcp.rb
#
# Note: This example requires an MCP server to be running.
# You can use the Neon database MCP server or any compatible server.

require_relative "../lib/robot_lab"

# Configure Ruby LLM
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
end

# MCP server configuration
# This example shows different transport options

# WebSocket transport (most common)
websocket_server = {
  name: "database",
  transport: {
    type: "ws",
    url: "ws://localhost:8080/mcp"
  }
}

# HTTP transport with session management
http_server = {
  name: "api_tools",
  transport: {
    type: "streamable-http",
    url: "https://api.example.com/mcp",
    session_id: nil # Will be assigned on connect
  }
}

# StdIO transport (for local tools)
stdio_server = {
  name: "local_tools",
  transport: {
    type: "stdio",
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
  }
}

puts "MCP Integration Example"
puts "-" * 40
puts ""
puts "This example demonstrates MCP server configuration."
puts "MCP servers provide external tools to robots via the Model Context Protocol."
puts ""
puts "Supported transports:"
puts "  - WebSocket (ws://)"
puts "  - Streamable HTTP (https://)"
puts "  - StdIO (local processes)"
puts "  - SSE (Server-Sent Events)"
puts ""

# Create robot with MCP servers
# (Uncomment and configure when you have a running MCP server)

# robot = RobotLab.build(
#   name: "mcp_robot",
#   system: "You have access to database tools via MCP.",
#   mcp_servers: [websocket_server],
#   model: RobotLab::RoboticModel.new("claude-sonnet-4", provider: :anthropic)
# )

# Example: Using MCP client directly
puts "MCP Client Usage:"
puts ""
puts <<~CODE
  # Create MCP client
  client = RobotLab::MCP::Client.new(websocket_server)

  # Connect to server
  client.connect

  # List available tools
  tools = client.list_tools
  puts "Available tools: \#{tools.map { |t| t[:name] }.join(', ')}"

  # Call a tool
  result = client.call_tool("query", { sql: "SELECT * FROM users LIMIT 5" })
  puts "Query result: \#{result}"

  # Disconnect
  client.close
CODE

puts "-" * 40
