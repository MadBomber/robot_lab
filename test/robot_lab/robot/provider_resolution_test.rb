# frozen_string_literal: true

require "test_helper"

# Issue #113: where a robot's provider comes from.
# Precedence: constructor > template front matter > ruby_llm.provider config.
class RobotLab::Robot::ProviderResolutionTest < Minitest::Test
  def setup
    @ruby_llm = RobotLab.config.ruby_llm
    @saved    = @ruby_llm.provider
    RubyLLM.configure { |c| c.ollama_api_base = "http://localhost:11434" }
  end

  def teardown
    @ruby_llm.provider = @saved
    RubyLLM.configure { |c| c.ollama_api_base = nil }
  end

  def test_no_provider_anywhere_leaves_it_nil
    @ruby_llm.provider = nil
    robot = RobotLab.build(name: "bot", system_prompt: "You are helpful.")

    assert_nil robot.provider
  end

  def test_configured_provider_is_used_when_the_constructor_names_none
    @ruby_llm.provider = :ollama
    robot = RobotLab.build(name: "bot", system_prompt: "You are helpful.", model: "llama3.2")

    assert_equal :ollama, robot.provider
    assert_equal "ollama", robot.chat_provider.to_s
  end

  def test_configured_provider_string_from_env_becomes_a_symbol
    @ruby_llm.provider = "ollama"
    robot = RobotLab.build(name: "bot", system_prompt: "You are helpful.", model: "llama3.2")

    assert_equal :ollama, robot.provider
  end

  def test_constructor_provider_beats_the_configured_one
    @ruby_llm.provider = :openai
    robot = RobotLab.build(name: "bot", system_prompt: "You are helpful.", provider: "ollama", model: "llama3.2")

    assert_equal "ollama", robot.provider
  end

  def test_front_matter_provider_beats_the_configured_one
    @ruby_llm.provider = :openai
    robot = RobotLab.build(name: "bot", template: :provider_test)

    assert_equal :ollama, robot.provider
    assert_equal "llama3.2", robot.model
    assert_equal "ollama", robot.chat_provider.to_s
  end

  def test_front_matter_provider_applies_through_the_skills_path
    @ruby_llm.provider = nil
    robot = RobotLab.build(name: "bot", template: :provider_test, skills: [:skill_b_test])

    assert_equal :ollama, robot.provider
  end

  def test_constructor_provider_beats_front_matter
    robot = RobotLab.build(name: "bot", template: :provider_test, provider: :openai, model: "gpt-4o")

    assert_equal :openai, robot.provider
  end

  def test_resolve_provider_in_isolation
    robot = RobotLab.build(name: "bot", system_prompt: "x")
    config = Struct.new(:ruby_llm).new(Struct.new(:provider).new(""))

    assert_equal :anthropic, robot.send(:resolve_provider, :anthropic, config)
    assert_nil robot.send(:resolve_provider, nil, config)
    config.ruby_llm.provider = "lms"
    assert_equal :lms, robot.send(:resolve_provider, nil, config)
  end
end
