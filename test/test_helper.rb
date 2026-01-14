# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "robot_lab"
require "minitest/autorun"
require "minitest/reporters"
require "webmock/minitest"

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

# Disable real network connections during tests
WebMock.disable_net_connect!(allow_localhost: true)

# Configure RobotLab for testing
RobotLab.configure do |config|
  config.logger = Logger.new(nil) # Silence logging in tests
end

# Test helpers
module RobotLabTestHelpers
  def build_test_robot(name: "test_robot", system: "You are a test assistant")
    RobotLab.build(
      name: name,
      system: system,
      model: mock_model
    )
  end

  def build_test_network(name: "test_network", robots: [])
    robots = [build_test_robot] if robots.empty?
    RobotLab.create_network(
      name: name,
      robots: robots,
      default_model: mock_model
    )
  end

  def mock_model
    @mock_model ||= MockModel.new
  end

  # Mock model for testing without real API calls
  class MockModel
    attr_accessor :responses

    def initialize
      @responses = []
      @call_count = 0
    end

    def add_response(messages:, stop_reason: "stop")
      @responses << { messages: messages, stop_reason: stop_reason }
    end

    def infer(messages, tools, tool_choice: "auto")
      response = @responses[@call_count] || default_response
      @call_count += 1

      InferenceResult.new(
        output: response[:messages],
        stop_reason: response[:stop_reason]
      )
    end

    private

    def default_response
      {
        messages: [RobotLab::TextMessage.new(role: :assistant, content: "Test response")],
        stop_reason: "stop"
      }
    end
  end

  # Simple inference result for mock
  class InferenceResult
    attr_reader :output, :stop_reason

    def initialize(output:, stop_reason:)
      @output = output
      @stop_reason = stop_reason
    end
  end
end

class Minitest::Test
  include RobotLabTestHelpers
end
