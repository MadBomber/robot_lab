# frozen_string_literal: true

require "test_helper"

class RobotLab::ConfigTest < Minitest::Test
  def setup
    # Clear any cached config
    RobotLab.instance_variable_set(:@config, nil)
  end

  def teardown
    # Clean up environment variables
    ENV.delete("ROBOT_LAB_DEFAULT_MODEL")
    ENV.delete("ROBOT_LAB_MAX_ITERATIONS")
    ENV.delete("ROBOT_LAB_STREAMING_ENABLED")
    ENV.delete("ROBOT_LAB_RUBY_LLM__REQUEST_TIMEOUT")

    # Reset config
    RobotLab.instance_variable_set(:@config, nil)
  end

  # New config accessor tests
  def test_config_returns_config_instance
    assert_instance_of RobotLab::Config, RobotLab.config
  end

  def test_config_is_singleton
    config1 = RobotLab.config
    config2 = RobotLab.config
    assert_same config1, config2
  end

  # Default values from defaults.yml
  def test_default_provider_from_config
    assert_equal :anthropic, RobotLab.config.default_provider
  end

  def test_default_model_from_config
    assert_equal "claude-sonnet-4", RobotLab.config.default_model
  end

  def test_default_max_iterations_from_config
    assert_equal 10, RobotLab.config.max_iterations
  end

  def test_default_max_tool_iterations_from_config
    assert_equal 10, RobotLab.config.max_tool_iterations
  end

  def test_default_streaming_enabled_from_config
    # Note: In test environment this may be false per defaults.yml
    # This tests that the value is a boolean
    assert [true, false].include?(RobotLab.config.streaming_enabled)
  end

  def test_default_mcp_from_config
    assert_equal :none, RobotLab.config.mcp
  end

  def test_default_tools_from_config
    assert_equal :none, RobotLab.config.tools
  end

  # Nested ruby_llm configuration
  def test_ruby_llm_section_exists
    refute_nil RobotLab.config.ruby_llm
  end

  def test_ruby_llm_request_timeout_default
    assert_equal 120, RobotLab.config.ruby_llm.request_timeout
  end

  def test_ruby_llm_max_retries_default
    assert_equal 3, RobotLab.config.ruby_llm.max_retries
  end

  def test_ruby_llm_log_level_default
    # Default is :info but test environment might override to :warn
    assert_includes %i[info debug warn error], RobotLab.config.ruby_llm.log_level
  end

  # Environment predicates
  def test_environment_predicates_exist
    assert_respond_to RobotLab.config, :development?
    assert_respond_to RobotLab.config, :test?
    assert_respond_to RobotLab.config, :production?
  end

  def test_environment_method
    assert_respond_to RobotLab.config, :environment
    assert_includes %w[development test production], RobotLab.config.environment
  end

  # Reload functionality
  def test_reload_config_creates_new_instance
    config1 = RobotLab.config
    config2 = RobotLab.reload_config!

    refute_same config1, config2
  end

  # Logger attribute
  def test_logger_attribute_exists
    assert_respond_to RobotLab.config, :logger
    assert_respond_to RobotLab.config, :logger=
  end

  def test_logger_can_be_set
    custom_logger = Logger.new($stderr)
    RobotLab.config.logger = custom_logger
    assert_equal custom_logger, RobotLab.config.logger
  end

  # after_load hook
  def test_after_load_is_called
    # Just verify the method exists and can be called
    config = RobotLab::Config.new
    assert_respond_to config, :after_load
    # Should not raise
    config.after_load
  end

  # apply_ruby_llm_config! tests
  def test_apply_ruby_llm_config_method_exists
    config = RobotLab::Config.new
    assert_respond_to config, :apply_ruby_llm_config!
  end
end
