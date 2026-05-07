# frozen_string_literal: true

require "test_helper"

class RobotLab::RoboticModelTest < Minitest::Test
  # Initialization tests
  def test_initialization_with_model_id
    model = RobotLab::RoboticModel.new("claude-sonnet-4")

    assert_equal "claude-sonnet-4", model.model_id
  end

  def test_initialization_detects_anthropic_provider
    model = RobotLab::RoboticModel.new("claude-3-opus")

    assert_equal :anthropic, model.provider
  end

  def test_initialization_detects_anthropic_from_prefix
    model = RobotLab::RoboticModel.new("anthropic/model")

    assert_equal :anthropic, model.provider
  end

  def test_initialization_detects_openai_provider_gpt
    model = RobotLab::RoboticModel.new("gpt-4")

    assert_equal :openai, model.provider
  end

  def test_initialization_detects_openai_provider_o1
    model = RobotLab::RoboticModel.new("o1-preview")

    assert_equal :openai, model.provider
  end

  def test_initialization_detects_openai_provider_o3
    model = RobotLab::RoboticModel.new("o3-mini")

    assert_equal :openai, model.provider
  end

  def test_initialization_detects_openai_provider_chatgpt
    model = RobotLab::RoboticModel.new("chatgpt-4o")

    assert_equal :openai, model.provider
  end

  def test_initialization_detects_gemini_provider
    model = RobotLab::RoboticModel.new("gemini-pro")

    assert_equal :gemini, model.provider
  end

  def test_initialization_detects_ollama_provider_llama
    model = RobotLab::RoboticModel.new("llama-3")

    assert_equal :ollama, model.provider
  end

  def test_initialization_detects_ollama_provider_mistral
    model = RobotLab::RoboticModel.new("mistral-7b")

    assert_equal :ollama, model.provider
  end

  def test_initialization_detects_ollama_provider_mixtral
    model = RobotLab::RoboticModel.new("mixtral-8x7b")

    assert_equal :ollama, model.provider
  end

  def test_initialization_uses_default_provider_for_unknown_model
    model = RobotLab::RoboticModel.new("unknown-model")

    assert_equal RobotLab.config.ruby_llm.provider, model.provider
  end

  def test_initialization_with_explicit_provider
    model = RobotLab::RoboticModel.new("custom-model", provider: :openai)

    assert_equal :openai, model.provider
  end

  def test_initialization_creates_adapter
    model = RobotLab::RoboticModel.new("claude-3-opus")

    assert model.adapter.is_a?(RobotLab::Adapters::Anthropic)
  end

  def test_initialization_creates_correct_adapter_for_provider
    {
      "claude-3" => RobotLab::Adapters::Anthropic,
      "gpt-4" => RobotLab::Adapters::OpenAI,
      "gemini-pro" => RobotLab::Adapters::Gemini
    }.each do |model_id, adapter_class|
      model = RobotLab::RoboticModel.new(model_id)
      assert model.adapter.is_a?(adapter_class), "Expected #{adapter_class} for #{model_id}"
    end
  end

  # Case insensitivity
  def test_provider_detection_is_case_insensitive
    model = RobotLab::RoboticModel.new("CLAUDE-3-OPUS")

    assert_equal :anthropic, model.provider
  end
end

class RobotLab::ToolExecutionCaptureTest < Minitest::Test
  def setup
    RobotLab::ToolExecutionCapture.clear!
  end

  def test_captured_returns_array
    assert RobotLab::ToolExecutionCapture.captured.is_a?(Array)
  end

  def test_captured_is_thread_local
    RobotLab::ToolExecutionCapture.record(
      tool_name: "test",
      tool_id: "123",
      input: {},
      output: "result"
    )

    other_thread_captured = nil
    Thread.new do
      other_thread_captured = RobotLab::ToolExecutionCapture.captured
    end.join

    assert_equal 1, RobotLab::ToolExecutionCapture.captured.size
    assert_equal 0, other_thread_captured.size
  end

  def test_clear_empties_captured
    RobotLab::ToolExecutionCapture.record(
      tool_name: "test",
      tool_id: "123",
      input: {},
      output: "result"
    )

    RobotLab::ToolExecutionCapture.clear!

    assert_empty RobotLab::ToolExecutionCapture.captured
  end

  def test_record_adds_to_captured
    RobotLab::ToolExecutionCapture.record(
      tool_name: "search",
      tool_id: "abc-123",
      input: { query: "test" },
      output: "found"
    )

    captured = RobotLab::ToolExecutionCapture.captured

    assert_equal 1, captured.size
    assert_equal "search", captured.first[:tool_name]
    assert_equal "abc-123", captured.first[:tool_id]
    assert_equal({ query: "test" }, captured.first[:input])
    assert_equal "found", captured.first[:output]
  end

  def test_multiple_records
    RobotLab::ToolExecutionCapture.record(
      tool_name: "tool1",
      tool_id: "1",
      input: {},
      output: "result1"
    )
    RobotLab::ToolExecutionCapture.record(
      tool_name: "tool2",
      tool_id: "2",
      input: {},
      output: "result2"
    )

    assert_equal 2, RobotLab::ToolExecutionCapture.captured.size
  end
end

class RobotLab::InferenceResponseTest < Minitest::Test
  def test_initialization
    output = []
    response = RobotLab::InferenceResponse.new(
      output: output,
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    assert_equal output, response.output
    assert_equal({}, response.raw)
    assert_equal "claude-3", response.model
    assert_equal :anthropic, response.provider
    assert_equal [], response.captured_tool_results
  end

  def test_initialization_with_captured_tool_results
    captured = [{ tool: "test", result: "value" }]
    response = RobotLab::InferenceResponse.new(
      output: [],
      raw: {},
      model: "claude-3",
      provider: :anthropic,
      captured_tool_results: captured
    )

    assert_equal captured, response.captured_tool_results
  end

  def test_stop_reason_from_last_output
    msg = RobotLab::TextMessage.new(role: "assistant", content: "Hello")
    msg.instance_variable_set(:@stop_reason, "stop")
    msg.define_singleton_method(:stop_reason) { @stop_reason }

    response = RobotLab::InferenceResponse.new(
      output: [msg],
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    assert_equal "stop", response.stop_reason
  end

  def test_stop_reason_nil_when_empty
    response = RobotLab::InferenceResponse.new(
      output: [],
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    assert_nil response.stop_reason
  end

  def test_stopped_true_when_stop_reason_is_stop
    msg = RobotLab::TextMessage.new(role: "assistant", content: "Hello")
    msg.define_singleton_method(:stop_reason) { "stop" }

    response = RobotLab::InferenceResponse.new(
      output: [msg],
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    assert response.stopped?
  end

  def test_stopped_false_when_stop_reason_not_stop
    msg = RobotLab::TextMessage.new(role: "assistant", content: "Hello")
    msg.define_singleton_method(:stop_reason) { "tool" }

    response = RobotLab::InferenceResponse.new(
      output: [msg],
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    refute response.stopped?
  end

  def test_wants_tools_true_when_stop_reason_tool
    msg = RobotLab::TextMessage.new(role: "assistant", content: "Hello")
    msg.define_singleton_method(:stop_reason) { "tool" }
    msg.define_singleton_method(:tool_call?) { false }

    response = RobotLab::InferenceResponse.new(
      output: [msg],
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    assert response.wants_tools?
  end

  def test_text_content_concatenates_text_messages
    msg1 = RobotLab::TextMessage.new(role: "assistant", content: "Hello ")
    msg2 = RobotLab::TextMessage.new(role: "assistant", content: "World")

    response = RobotLab::InferenceResponse.new(
      output: [msg1, msg2],
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    assert_equal "Hello World", response.text_content
  end

  def test_text_content_empty_when_no_text_messages
    response = RobotLab::InferenceResponse.new(
      output: [],
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    assert_equal "", response.text_content
  end

  def test_tool_calls_returns_tools_from_tool_call_messages
    tool = RobotLab::ToolMessage.new(id: "t1", name: "search", input: { query: "test" })
    tool_call_msg = RobotLab::ToolCallMessage.new(role: "assistant", tools: [tool])

    response = RobotLab::InferenceResponse.new(
      output: [tool_call_msg],
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    assert_equal 1, response.tool_calls.size
    assert_equal "search", response.tool_calls.first.name
  end

  def test_tool_calls_returns_empty_when_no_tool_calls
    text_msg = RobotLab::TextMessage.new(role: "assistant", content: "Hello")

    response = RobotLab::InferenceResponse.new(
      output: [text_msg],
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    assert_empty response.tool_calls
  end

  def test_wants_tools_true_when_output_has_tool_call_message
    tool = RobotLab::ToolMessage.new(id: "t1", name: "search", input: {})
    tool_call_msg = RobotLab::ToolCallMessage.new(role: "assistant", tools: [tool])

    response = RobotLab::InferenceResponse.new(
      output: [tool_call_msg],
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    assert response.wants_tools?
  end

  def test_wants_tools_false_when_no_tool_indicators
    text_msg = RobotLab::TextMessage.new(role: "assistant", content: "Hello", stop_reason: "stop")

    response = RobotLab::InferenceResponse.new(
      output: [text_msg],
      raw: {},
      model: "claude-3",
      provider: :anthropic
    )

    refute response.wants_tools?
  end
end
