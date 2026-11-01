#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 4: MCP (Model Context Protocol) Integration
#
# robot_lab 0.4 uses ruby_llm's built-in MCP client. A server is described
# once, as a config Hash or a RubyLLM::MCP subclass, and gives a robot the
# server's tools, resources, and prompts.
#
# This example talks to the reference filesystem server, which needs only
# Node (npx) and is scoped to the directory you hand it.
#
# Prerequisites:
#   - Node.js with npx on PATH
#   - For Part 2, LM Studio running (see examples/common.rb); Part 1 needs no LLM
#
# Usage:
#   bundle exec ruby examples/04_mcp.rb

require_relative "common"

# One config Hash is all a server needs. The same shape works in
# RobotLab.build(mcp: [...]), template front matter, Network#task(mcp:),
# RunConfig#mcp, and RobotLab::MCP.build.
filesystem = {
  name:        "filesystem",
  description: "Read, write, and search files under the examples directory",
  transport: {
    type:    "stdio",
    command: "npx",
    args:    ["-y", "@modelcontextprotocol/server-filesystem", __dir__]
  },
  timeout: 60 # seconds; the first npx run downloads the server
}

banner "MCP Integration"

puts "A server described as a Hash, used directly and then through a robot."
puts

robot = nil
begin
  # ==========================================================================
  # Part 1: A server on its own
  # ==========================================================================

  section "Part 1: A server on its own"
  puts "Building the server (connects lazily on first use)..."

  server = RobotLab::MCP.build(filesystem) # => a RubyLLM::MCP
  tools  = server.tools                    # connects, lists tools

  puts "Connected: #{server.name} (protocol #{server.version})"
  puts "Instructions: #{server.instructions.lines.first.strip}" if server.instructions
  puts

  puts "Tools (#{tools.size}):"
  hr
  tools.first(10).each do |tool|
    puts "  #{tool.name}"
    puts "    #{tool.description.lines.first.strip}" if tool.description
  end
  puts "  ... and #{tools.size - 10} more" if tools.size > 10
  puts

  puts "Calling list_directory directly:"
  hr
  result = server.call(:list_directory, path: __dir__)
  puts result.error? ? "  error: #{result.text}" : result.text.lines.first(8).map { |l| "  #{l}" }.join
  puts

  # Resources and prompts are part of the same object. A server that does not
  # implement them answers with a JSON-RPC "method not found" error.
  offered = lambda do |label|
    "#{server.public_send(label).size} #{label}"
  rescue RubyLLM::MCP::Error => e
    "#{label} not offered (#{e.message})"
  end
  puts "Resources: #{offered.call(:resources)}"
  puts "Prompts:   #{offered.call(:prompts)}"
  puts

  server.close
  puts "Closed (the next request would reconnect)."

  # ==========================================================================
  # Part 2: Robot + MCP
  # ==========================================================================

  section "Part 2: Robot + MCP"

  # The server part above needs no LLM; the robot part does.
  require_lms!

  # mcp: registers the server with the robot. tool_approval: :approve lets
  # tools the server marks as requiring approval run unattended; the default
  # is :deny, or pass on_tool_approval: to decide per call.
  robot = RobotLab.build(
    **llm_opts,
    name:          "fs_assistant",
    system_prompt: "You answer questions about files using the tools you are given. Be brief.",
    mcp:           [filesystem],
    tool_approval: :approve
  )

  # Connections are made on the first run that selects a server; connect_mcp!
  # connects now so status can be shown up front.
  robot.connect_mcp!

  puts "Robot: #{robot.name} (#{robot.model})"
  puts "  MCP servers:  #{robot.mcp.names.join(', ')}"
  puts "  Failed:       #{robot.failed_mcp_server_names.inspect}"
  puts "  MCP tools:    #{robot.mcp_tools.size}"
  puts "  Same object:  robot.mcp[:filesystem].tools.size == #{robot.mcp[:filesystem].tools.size}"
  puts

  # run() defaults to mcp: :none / tools: :none, which sends the model no
  # tools at all. mcp: :inherit selects the robot's servers for this turn;
  # tools: takes a name allowlist (or :inherit for every tool). Allowlisting
  # keeps the tool schemas small for local models.
  question = "Which Ruby files in this directory have 'network' in their name? Just list them."
  puts "Query: #{question}"
  hr

  result = robot.run(question, mcp: :inherit, tools: %w[list_directory search_files])

  puts
  puts "Robot Response:"
  hr
  result.output.each { |msg| puts msg.content if msg.respond_to?(:content) }
  puts

  if result.tool_calls.any?
    puts "Tool calls made: #{result.tool_calls.size}"
    puts
  end

  # Closes every server (stopping the npx process); servers stay registered
  # and would reconnect on the next run.
  robot.disconnect
  puts "Robot disconnected."

  # ==========================================================================
  # Part 3: Servers as classes
  # ==========================================================================

  section "Part 3: Servers as classes"
  puts "Anything RubyLLM::MCP's class DSL offers works on a robot too:"
  puts
  show_code <<~RUBY
    class GitHub < RubyLLM::MCP
      command "github-mcp-server", "stdio"
      env GITHUB_PERSONAL_ACCESS_TOKEN: ENV["GITHUB_PERSONAL_ACCESS_TOKEN"]
      only "search_repositories", "get_file_contents", "create_issue"
      requires_approval "create_issue"     # paused until approved
    end

    robot = RobotLab.build(
      name: "dev",
      mcp:  [GitHub],
      on_tool_approval: ->(call) { call.name != "create_issue" || ask_the_user(call) }
    )

    robot.run("Open an issue about the flaky test", mcp: :inherit, tools: :inherit)
    robot.run(robot.mcp[:git_hub].prompt("code_review", code: diff), mcp: :inherit)
  RUBY
rescue RobotLab::MCPError, RubyLLM::MCP::Error => e
  puts "MCP error: #{e.message}"
  exit 1
rescue Errno::ENOENT => e
  puts <<~ERROR

    ERROR: #{e.message}

    This example runs the filesystem MCP server with npx. Install Node.js
    (https://nodejs.org) so that `npx` is on your PATH.
  ERROR
  exit 1
ensure
  # Stops the npx server process on every exit path, including an abort above.
  robot&.disconnect
end

puts
hr
puts "Example complete!"
