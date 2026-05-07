# frozen_string_literal: true

require "test_helper"

class RobotLab::Adapters::RegistryTest < Minitest::Test
  # .for tests
  def test_for_returns_anthropic_adapter
    adapter = RobotLab::Adapters::Registry.for(:anthropic)
    assert adapter.is_a?(RobotLab::Adapters::Anthropic)
  end

  def test_for_returns_openai_adapter
    adapter = RobotLab::Adapters::Registry.for(:openai)
    assert adapter.is_a?(RobotLab::Adapters::OpenAI)
  end

  def test_for_returns_gemini_adapter
    adapter = RobotLab::Adapters::Registry.for(:gemini)
    assert adapter.is_a?(RobotLab::Adapters::Gemini)
  end

  def test_for_azure_openai_returns_openai_adapter
    adapter = RobotLab::Adapters::Registry.for(:azure_openai)
    assert adapter.is_a?(RobotLab::Adapters::OpenAI)
  end

  def test_for_grok_returns_openai_adapter
    adapter = RobotLab::Adapters::Registry.for(:grok)
    assert adapter.is_a?(RobotLab::Adapters::OpenAI)
  end

  def test_for_ollama_returns_openai_adapter
    adapter = RobotLab::Adapters::Registry.for(:ollama)
    assert adapter.is_a?(RobotLab::Adapters::OpenAI)
  end

  def test_for_openrouter_returns_openai_adapter
    adapter = RobotLab::Adapters::Registry.for(:openrouter)
    assert adapter.is_a?(RobotLab::Adapters::OpenAI)
  end

  def test_for_bedrock_returns_anthropic_adapter
    adapter = RobotLab::Adapters::Registry.for(:bedrock)
    assert adapter.is_a?(RobotLab::Adapters::Anthropic)
  end

  def test_for_vertexai_returns_gemini_adapter
    adapter = RobotLab::Adapters::Registry.for(:vertexai)
    assert adapter.is_a?(RobotLab::Adapters::Gemini)
  end

  # String argument handling
  def test_for_accepts_string_argument
    adapter = RobotLab::Adapters::Registry.for("anthropic")
    assert adapter.is_a?(RobotLab::Adapters::Anthropic)
  end

  def test_for_normalizes_kebab_case_to_snake_case
    adapter = RobotLab::Adapters::Registry.for("azure-openai")
    assert adapter.is_a?(RobotLab::Adapters::OpenAI)
  end

  def test_for_handles_mixed_case
    adapter = RobotLab::Adapters::Registry.for("ANTHROPIC")
    assert adapter.is_a?(RobotLab::Adapters::Anthropic)
  end

  # Error handling
  def test_for_raises_argument_error_for_unknown_provider
    error = assert_raises(ArgumentError) do
      RobotLab::Adapters::Registry.for(:unknown_provider)
    end

    assert_includes error.message, "Unknown provider: unknown_provider"
    assert_includes error.message, "Available providers:"
  end

  # .available tests
  def test_available_returns_array_of_provider_symbols
    providers = RobotLab::Adapters::Registry.available
    assert providers.is_a?(Array)
    assert providers.all? { |p| p.is_a?(Symbol) }
  end

  def test_available_includes_core_providers
    providers = RobotLab::Adapters::Registry.available

    assert_includes providers, :anthropic
    assert_includes providers, :openai
    assert_includes providers, :gemini
  end

  def test_available_includes_variant_providers
    providers = RobotLab::Adapters::Registry.available

    assert_includes providers, :azure_openai
    assert_includes providers, :bedrock
    assert_includes providers, :vertexai
    assert_includes providers, :ollama
    assert_includes providers, :openrouter
    assert_includes providers, :grok
  end

  # .supports? tests
  def test_supports_returns_true_for_known_provider
    assert RobotLab::Adapters::Registry.supports?(:anthropic)
    assert RobotLab::Adapters::Registry.supports?(:openai)
    assert RobotLab::Adapters::Registry.supports?(:gemini)
  end

  def test_supports_returns_false_for_unknown_provider
    refute RobotLab::Adapters::Registry.supports?(:unknown)
    refute RobotLab::Adapters::Registry.supports?(:not_a_provider)
  end

  def test_supports_handles_string_argument
    assert RobotLab::Adapters::Registry.supports?("anthropic")
    assert RobotLab::Adapters::Registry.supports?("OpenAI")
  end

  def test_supports_normalizes_kebab_case
    assert RobotLab::Adapters::Registry.supports?("azure-openai")
  end

  # .register tests
  # Note: The ADAPTERS hash is frozen, so register will raise FrozenError
  # This tests the current behavior - register is intended for runtime extension
  # but requires unfreezing the hash first
  def test_register_raises_frozen_error_on_frozen_hash
    custom_adapter_class = Class.new(RobotLab::Adapters::Base)

    assert_raises(FrozenError) do
      RobotLab::Adapters::Registry.register(:custom_provider, custom_adapter_class)
    end
  end

  # Adapter instances are new each time
  def test_for_returns_new_adapter_instance_each_time
    adapter1 = RobotLab::Adapters::Registry.for(:anthropic)
    adapter2 = RobotLab::Adapters::Registry.for(:anthropic)

    refute_same adapter1, adapter2
  end
end
