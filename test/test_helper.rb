# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'

  add_group 'Core', 'lib/robot_lab'
  add_group 'MCP', 'lib/robot_lab/mcp'
  add_group 'History', 'lib/robot_lab/history'
  add_group 'Streaming', 'lib/robot_lab/streaming'
  add_group 'Rails', 'lib/robot_lab/rails'

  enable_coverage :branch
  minimum_coverage line: 95, branch: 75
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Configure RobotLab for testing
# Set template path via environment variable before loading config
ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.expand_path('../examples/prompts', __dir__)

require 'robot_lab'
require 'simple_flow'   # ensure SimpleFlow is loaded regardless of test order
require 'robot_lab/document_store' rescue LoadError  # optional extension gem

# Minimal in-memory store that satisfies the DocumentStore interface used by
# AgentSkillMatching without requiring the extension gem or fastembed.
# Use this in core tests that exercise inject/restore/expand logic but don't
# need real semantic scores — semantic scoring tests belong in robot_lab-document_store.
class FakeSkillStore
  def initialize = (@docs = {})
  def store(key, text)
    @docs[key.to_sym] = text
  end and self
  def search(_query, limit: 5)
    @docs.first(limit).map { |key, text| { key: key, text: text, score: 0.9 } }
  end

  def size = @docs.size
  def empty? = @docs.empty?
end
require 'minitest/autorun'
require 'minitest/reporters'

# rubocop:disable Style/FileOpen, Style/GlobalStdStream, Layout/LineLength
$stdout = File.open('test_output.txt', 'w').tap { |f| f.sync = true }

class TerminalSummaryReporter < Minitest::Reporters::BaseReporter
  def report
    super
    ok    = failures.zero? && errors.zero?
    badge = ok ? "\e[32mPASS\e[0m" : "\e[31mFAIL\e[0m"
    STDOUT.puts "[#{badge}] #{count} tests, #{failures} failures, #{errors} errors, #{skips} skips (#{format('%.2f', total_time)}s) — see test_output.txt"
    STDOUT.flush
  end
end
# rubocop:enable Style/FileOpen, Style/GlobalStdStream, Layout/LineLength

Minitest::Reporters.use! [
  Minitest::Reporters::DefaultReporter.new(color: false, slow_count: 5),
  TerminalSummaryReporter.new
]

# Set dummy API key so RubyLLM model resolution doesn't fail in unit tests
# (Robot now creates a persistent chat in initialize via Agent)
RubyLLM.configure { |c| c.anthropic_api_key = 'test-key-for-unit-tests' }

# Suppress logging in tests
RobotLab.config.logger = Logger.new(nil)

# Test helpers
module RobotLabTestHelpers
  # Create a real Robot instance for testing
  def build_robot(name:, template: :assistant, **)
    RobotLab::Robot.new(
      name: name,
      template: template,
      **
    )
  end

  # Create a real Network instance for testing
  def build_network(name:, **, &)
    RobotLab::Network.new(name: name, **, &)
  end

  # Create a RunConfig for testing
  def build_config(**, &)
    RobotLab::RunConfig.new(**, &)
  end

  # Extract the system instructions from a robot's chat
  def system_instructions(robot)
    chat = robot.instance_variable_get(:@chat)
    messages = chat.instance_variable_get(:@messages)
    sys = messages&.find { |m| m.role.to_s == 'system' }
    sys&.content
  end

  # Create a Tool for testing
  def build_tool(name:, description: 'Test tool', &)
    RobotLab::Tool.create(
      name: name,
      description: description,
      &
    )
  end
end

class Minitest::Test
  include RobotLabTestHelpers

  def wait_until(timeout: 1, interval: 0.005)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return if yield
      raise "wait_until timed out after #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep interval
    end
  end
end
