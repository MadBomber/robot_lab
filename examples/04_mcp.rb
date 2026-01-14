#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 4: MCP (Model Context Protocol) Integration with GitHub
#
# Demonstrates connecting to the GitHub MCP server and using its tools
# to interact with GitHub repositories.
#
# Prerequisites:
#   1. Install the GitHub MCP server: brew install github-mcp-server
#   2. Set environment variables:
#      - ANTHROPIC_API_KEY: Your Anthropic API key
#      - GITHUB_PERSONAL_ACCESS_TOKEN: Your GitHub personal access token
#
# Usage:
#   ANTHROPIC_API_KEY=your_key GITHUB_PERSONAL_ACCESS_TOKEN=your_token ruby examples/04_mcp.rb
#
# The GitHub MCP server provides tools for:
#   - Searching repositories, code, issues, and users
#   - Creating and managing issues and pull requests
#   - Reading file contents and repository information
#   - Managing branches and commits

require_relative "../lib/robot_lab"

# Configure RobotLab
RobotLab.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.template_path = File.join(__dir__, "prompts")
end

# GitHub MCP server configuration using StdIO transport
github_server = {
  name: "github",
  transport: {
    type: "stdio",
    command: "github-mcp-server",
    args: ["stdio"],
    env: {
      "GITHUB_PERSONAL_ACCESS_TOKEN" => ENV.fetch("GITHUB_PERSONAL_ACCESS_TOKEN", "")
    }
  }
}

puts <<~HEADER
  MCP Integration Example: GitHub
  #{"=" * 40}

  This example demonstrates using the GitHub MCP server to interact
  with GitHub repositories through the Model Context Protocol.

HEADER

# Verify prerequisites
unless ENV["GITHUB_PERSONAL_ACCESS_TOKEN"]
  puts <<~ERROR
    ERROR: GITHUB_PERSONAL_ACCESS_TOKEN environment variable not set.

    To use this example:
      1. Create a GitHub Personal Access Token at https://github.com/settings/tokens
      2. Grant appropriate permissions (repo, read:user, etc.)
      3. Run: GITHUB_PERSONAL_ACCESS_TOKEN=your_token ruby examples/04_mcp.rb
  ERROR
  exit 1
end

# ============================================================================
# Part 1: Direct MCP Client Usage
# ============================================================================

puts "PART 1: Direct MCP Client Usage"
puts "-" * 40
puts
puts "Connecting to GitHub MCP server..."

begin
  # Create MCP client and connect
  client = RobotLab::MCP::Client.new(github_server)
  client.connect

  unless client.connected?
    puts <<~ERROR

      ERROR: Failed to connect to the GitHub MCP server.

      Make sure you have installed it:
        brew install github-mcp-server
    ERROR
    exit 1
  end

  puts "Connected successfully!"
  puts

  # List available tools
  puts "Available GitHub Tools:"
  puts "-" * 40

  tools = client.list_tools
  if tools.empty?
    puts "  (No tools returned - check server connection)"
  else
    tools.each do |tool|
      puts "  #{tool[:name]}"
      puts "    #{tool[:description]}" if tool[:description]
    end
  end

  puts "-" * 40
  puts "Total: #{tools.size} tools available"
  puts

  # Demonstrate a simple tool call: search for repositories
  puts "Demo: Searching for popular Ruby repositories..."
  puts

  result = client.call_tool("search_repositories", {
    query: "language:ruby stars:>1000",
    per_page: 5
  })

  # Extract and pretty print the JSON result
  if result.is_a?(Array) && result.first.is_a?(Hash) && result.first[:text]
    data = JSON.parse(result.first[:text])
    puts JSON.pretty_generate(data)
  else
    puts JSON.pretty_generate(result)
  end

  puts

  # Clean up direct client
  client.disconnect
  puts "Disconnected from direct MCP client."

  # ============================================================================
  # Part 2: Robot + MCP Integration
  # ============================================================================

  puts
  puts "=" * 40
  puts "PART 2: Robot + MCP Integration"
  puts "-" * 40
  puts

  puts "Creating Robot with MCP server integration..."
  puts

  # Create a Robot with MCP server - tools are automatically discovered
  robot = RobotLab.build(
    name: "github_assistant",
    template: :github_assistant,
    mcp_servers: [github_server],
    model: "claude-sonnet-4-20250514"
  )

  puts "Robot created: #{robot.name}"
  puts "  Model: #{robot.model}"
  puts "  MCP Servers: #{robot.mcp_clients.keys.join(", ")}"
  puts "  MCP Tools discovered: #{robot.mcp_tools.size}"
  puts

  # Show discovered MCP tools
  puts "Discovered MCP Tools:"
  puts "-" * 40
  robot.mcp_tools.first(10).each do |tool|
    puts "  #{tool.name}"
    puts "    #{tool.description&.slice(0, 60)}..." if tool.description
  end
  puts "  ... and #{robot.mcp_tools.size - 10} more" if robot.mcp_tools.size > 10
  puts

  # Run the robot with a query that will use MCP tools
  puts "Running Robot with a GitHub query..."
  puts "Query: 'What are the top 3 most starred Ruby web frameworks on GitHub?'"
  puts "-" * 40

  result = robot.run(message: "What are the top 3 most starred Ruby web frameworks on GitHub? Just list their names and star counts.")

  puts
  puts "Robot Response:"
  puts "-" * 40
  result.output.each do |msg|
    puts msg.content if msg.respond_to?(:content)
  end
  puts

  # Show tool calls if any were made
  if result.tool_calls.any?
    puts "Tool Calls Made:"
    puts "-" * 40
    result.tool_calls.each do |tc|
      tool_info = tc.respond_to?(:tool) ? tc.tool : tc
      puts "  #{tool_info[:name] || tool_info}"
    end
    puts
  end

  # Clean up robot's MCP connections
  robot.disconnect
  puts "Robot MCP connections disconnected."

rescue RobotLab::MCPError => e
  puts "MCP Error: #{e.message}"
  exit 1
rescue Errno::ENOENT
  puts <<~ERROR

    ERROR: Could not find the github-mcp-server command.

    Install it with:
      brew install github-mcp-server
  ERROR
  exit 1
end

puts
puts "=" * 40
puts "Example complete!"
