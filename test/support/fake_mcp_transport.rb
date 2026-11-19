# frozen_string_literal: true

# An in-process MCP transport for tests, implementing the duck type
# RubyLLM::MCP.transport documents: request/notify/cancel/close. It answers
# the legacy `initialize` handshake and the tools/resources/prompts
# methods with canned data and records everything it is asked.
#
#   transport = FakeMCPTransport.new(name: "fake", tools: [fake_tool_def("echo")])
#   server    = RobotLab::MCP.build(name: "fake", transport: transport)
#   server.tools.map(&:name)   # => ["echo"]
#   transport.calls            # => [["echo", {}]]
class FakeMCPTransport
  PROTOCOL_VERSION = '2025-06-18'

  attr_reader :name, :requests, :notifications, :close_count
  # Set fail_with to raise from every request; tool_results maps a tool name to a result Hash or a callable.
  attr_accessor :fail_with, :tool_results

  def initialize(name: 'fake', tools: [], resources: [], prompts: [], fail_with: nil, instructions: nil)
    @name          = name
    @tools         = tools
    @resources     = resources
    @prompts       = prompts
    @fail_with     = fail_with
    @instructions  = instructions
    @tool_results  = {}
    @requests      = []
    @notifications = []
    @close_count   = 0
  end

  # The tools/call invocations seen so far, as [tool_name, arguments] pairs.
  def calls
    @requests.select { |m| m[:method] == 'tools/call' }
             .map { |m| [m.dig(:params, :name), m.dig(:params, :arguments) || {}] }
  end

  def request(message, version: nil, timeout: nil, headers: {})
    raise @fail_with if @fail_with

    @requests << message
    result = result_for(message)
    return error_response(message) if result.nil?

    { 'jsonrpc' => '2.0', 'id' => message[:id], 'result' => result }
  end

  def notify(message, version: nil)
    @notifications << message
    nil
  end

  def cancel(notification, version: nil)
    notify(notification, version: version)
  end

  def close
    @close_count += 1
  end

  private

  # :reek:TooManyStatements -- one branch per JSON-RPC method the fake speaks.
  def result_for(message)
    params = message[:params] || {}
    case message[:method]
    when 'initialize'
      { 'protocolVersion' => PROTOCOL_VERSION, 'capabilities' => {},
        'serverInfo' => { 'name' => @name, 'version' => '0.0.1' }, 'instructions' => @instructions }.compact
    when 'ping'            then {}
    when 'tools/list'      then { 'tools' => @tools }
    when 'tools/call'      then tool_result(params)
    when 'resources/list'  then { 'resources' => @resources }
    when 'resources/read'  then { 'contents' => [{ 'uri' => params[:uri], 'text' => "contents of #{params[:uri]}" }] }
    when 'prompts/list'    then { 'prompts' => @prompts }
    when 'prompts/get'     then prompt_result(params[:name])
    end
  end

  # A canned result per tool name, or a callable given the tools/call params
  # (so a test can answer `input_required` first and a result second).
  def tool_result(params)
    tool_name = params[:name]
    value = @tool_results.fetch(tool_name) do
      { 'content' => [{ 'type' => 'text', 'text' => "#{tool_name} ok" }] }
    end
    value.respond_to?(:call) ? value.call(params) : value
  end

  def prompt_result(prompt_name)
    { 'messages' => [{ 'role' => 'user', 'content' => { 'type' => 'text', 'text' => "prompt #{prompt_name}" } }] }
  end

  def error_response(message)
    { 'jsonrpc' => '2.0', 'id' => message[:id],
      'error' => { 'code' => -32_601, 'message' => "Method not found: #{message[:method]}" } }
  end
end
