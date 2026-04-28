# frozen_string_literal: true

require 'test_helper'

class RobotLab::RunConfigTest < Minitest::Test
  # --- Construction ---

  def test_empty_construction
    config = RobotLab::RunConfig.new
    assert config.empty?
    assert_equal({}, config.to_h)
  end


  def test_keyword_construction
    config = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.7)
    assert_equal "claude-sonnet-4", config.model
    assert_in_delta 0.7, config.temperature
  end


  def test_block_construction
    config = RobotLab::RunConfig.new do |c|
      c.model "claude-sonnet-4"
      c.temperature 0.7
    end

    assert_equal "claude-sonnet-4", config.model
    assert_in_delta 0.7, config.temperature
  end


  def test_combined_keyword_and_block
    config = RobotLab::RunConfig.new(model: "claude-sonnet-4") do |c|
      c.temperature 0.9
    end

    assert_equal "claude-sonnet-4", config.model
    assert_in_delta 0.9, config.temperature
  end


  def test_block_overrides_keyword
    config = RobotLab::RunConfig.new(temperature: 0.5) do |c|
      c.temperature 0.9
    end

    assert_in_delta 0.9, config.temperature
  end


  def test_unknown_field_raises
    assert_raises(ArgumentError) do
      RobotLab::RunConfig.new(bogus: "nope")
    end
  end


  # --- Accessors ---

  def test_getter_returns_nil_for_unset_field
    config = RobotLab::RunConfig.new
    assert_nil config.model
  end


  def test_setter_returns_self_for_chaining
    config = RobotLab::RunConfig.new
    result = config.model("claude-sonnet-4")
    assert_same config, result
  end


  def test_chaining_multiple_setters
    config = RobotLab::RunConfig.new
      .model("claude-sonnet-4")
      .temperature(0.7)
      .max_tokens(1000)

    assert_equal "claude-sonnet-4", config.model
    assert_in_delta 0.7, config.temperature
    assert_equal 1000, config.max_tokens
  end


  def test_nil_removes_field
    config = RobotLab::RunConfig.new(model: "claude-sonnet-4")
    config.model(nil)
    assert_nil config.model
    refute config.key?(:model)
  end


  def test_all_llm_fields
    config = RobotLab::RunConfig.new(
      model: "gpt-4",
      temperature: 0.5,
      top_p: 0.9,
      top_k: 40,
      max_tokens: 2000,
      presence_penalty: 0.1,
      frequency_penalty: 0.2,
      stop: ["\n"]
    )

    assert_equal "gpt-4", config.model
    assert_in_delta 0.5, config.temperature
    assert_in_delta 0.9, config.top_p
    assert_equal 40, config.top_k
    assert_equal 2000, config.max_tokens
    assert_in_delta 0.1, config.presence_penalty
    assert_in_delta 0.2, config.frequency_penalty
    assert_equal ["\n"], config.stop
  end


  def test_tool_fields
    config = RobotLab::RunConfig.new(mcp: :inherit, tools: [:search])
    assert_equal :inherit, config.mcp
    assert_equal [:search], config.tools
  end


  def test_callback_fields
    on_call = ->(tc) { tc }
    on_result = ->(tr) { tr }
    config = RobotLab::RunConfig.new(on_tool_call: on_call, on_tool_result: on_result)

    assert_equal on_call, config.on_tool_call
    assert_equal on_result, config.on_tool_result
  end


  def test_infra_fields
    config = RobotLab::RunConfig.new(enable_cache: false)
    assert_equal false, config.enable_cache
  end


  def test_max_tool_rounds_field
    config = RobotLab::RunConfig.new(max_tool_rounds: 25)
    assert_equal 25, config.max_tool_rounds
  end


  def test_token_budget_field
    config = RobotLab::RunConfig.new(token_budget: 10_000)
    assert_equal 10_000, config.token_budget
  end


  def test_new_infra_fields_are_in_fields_constant
    assert_includes RobotLab::RunConfig::INFRA_FIELDS, :max_tool_rounds
    assert_includes RobotLab::RunConfig::INFRA_FIELDS, :token_budget
    assert_includes RobotLab::RunConfig::FIELDS, :max_tool_rounds
    assert_includes RobotLab::RunConfig::FIELDS, :token_budget
  end


  def test_new_infra_fields_merge_correctly
    base = RobotLab::RunConfig.new(max_tool_rounds: 10)
    override = RobotLab::RunConfig.new(max_tool_rounds: 25)
    merged = base.merge(override)
    assert_equal 25, merged.max_tool_rounds
  end


  # --- to_h ---

  def test_to_h_returns_only_set_values
    config = RobotLab::RunConfig.new(model: "gpt-4", temperature: 0.5)
    h = config.to_h
    assert_equal({ model: "gpt-4", temperature: 0.5 }, h)
  end


  def test_to_h_returns_dup
    config = RobotLab::RunConfig.new(model: "gpt-4")
    h1 = config.to_h
    h1[:model] = "changed"
    assert_equal "gpt-4", config.model
  end


  # --- to_json_hash ---

  def test_to_json_hash_skips_procs
    on_call = ->(tc) { tc }
    config = RobotLab::RunConfig.new(model: "gpt-4", on_tool_call: on_call)
    json_h = config.to_json_hash

    assert_equal "gpt-4", json_h[:model]
    refute json_h.key?(:on_tool_call)
  end


  def test_to_json_hash_skips_bus
    config = RobotLab::RunConfig.new(model: "gpt-4", bus: Object.new)
    json_h = config.to_json_hash

    assert_equal "gpt-4", json_h[:model]
    refute json_h.key?(:bus)
  end


  # --- merge ---

  def test_merge_returns_new_instance
    a = RobotLab::RunConfig.new(model: "gpt-4")
    b = RobotLab::RunConfig.new(temperature: 0.5)
    merged = a.merge(b)

    refute_same a, merged
    refute_same b, merged
  end


  def test_merge_other_wins
    a = RobotLab::RunConfig.new(model: "gpt-4", temperature: 0.5)
    b = RobotLab::RunConfig.new(temperature: 0.9)
    merged = a.merge(b)

    assert_equal "gpt-4", merged.model
    assert_in_delta 0.9, merged.temperature
  end


  def test_merge_nil_does_not_override
    a = RobotLab::RunConfig.new(model: "gpt-4", temperature: 0.5)
    b = RobotLab::RunConfig.new
    merged = a.merge(b)

    assert_equal "gpt-4", merged.model
    assert_in_delta 0.5, merged.temperature
  end


  def test_merge_accepts_hash
    a = RobotLab::RunConfig.new(model: "gpt-4")
    merged = a.merge({ temperature: 0.9 })

    assert_equal "gpt-4", merged.model
    assert_in_delta 0.9, merged.temperature
  end


  def test_merge_does_not_mutate_original
    a = RobotLab::RunConfig.new(model: "gpt-4")
    a.merge(RobotLab::RunConfig.new(temperature: 0.5))

    refute a.key?(:temperature)
  end


  # --- from_front_matter ---

  def test_from_front_matter_extracts_llm_fields
    metadata = Struct.new(:model, :temperature, :top_p, :top_k, :max_tokens,
                          :presence_penalty, :frequency_penalty, :stop,
                          :mcp, :tools, keyword_init: true)
                .new(model: "gpt-4", temperature: 0.5)

    config = RobotLab::RunConfig.from_front_matter(metadata)
    assert_equal "gpt-4", config.model
    assert_in_delta 0.5, config.temperature
    refute config.key?(:top_p)
  end


  def test_from_front_matter_extracts_tool_fields
    metadata = Struct.new(:model, :mcp, :tools, keyword_init: true)
                .new(mcp: [{ name: "server1" }], tools: ["search"])

    config = RobotLab::RunConfig.from_front_matter(metadata)
    assert_equal [{ name: "server1" }], config.mcp
    assert_equal ["search"], config.tools
  end


  def test_from_front_matter_ignores_nil_values
    metadata = Struct.new(:model, :temperature, keyword_init: true)
                .new(model: nil, temperature: nil)

    config = RobotLab::RunConfig.from_front_matter(metadata)
    assert config.empty?
  end


  def test_from_front_matter_handles_missing_methods
    metadata = Object.new
    config = RobotLab::RunConfig.from_front_matter(metadata)
    assert config.empty?
  end


  # --- apply_to ---

  def test_apply_to_calls_with_methods_on_chat
    calls = []
    chat = Object.new
    chat.define_singleton_method(:respond_to?) { |m, *| m.to_s.start_with?("with_") ? true : super(m) }
    chat.define_singleton_method(:with_model) { |v| calls << [:with_model, v] }
    chat.define_singleton_method(:with_temperature) { |v| calls << [:with_temperature, v] }

    config = RobotLab::RunConfig.new(model: "gpt-4", temperature: 0.5)
    config.apply_to(chat)

    assert_includes calls, [:with_model, "gpt-4"]
    assert_includes calls, [:with_temperature, 0.5]
  end


  def test_apply_to_skips_unset_fields
    calls = []
    chat = Object.new
    chat.define_singleton_method(:respond_to?) { |m, *| m.to_s.start_with?("with_") ? true : super(m) }
    chat.define_singleton_method(:with_model) { |v| calls << [:with_model, v] }
    chat.define_singleton_method(:with_temperature) { |v| calls << [:with_temperature, v] }

    config = RobotLab::RunConfig.new(model: "gpt-4")
    config.apply_to(chat)

    assert_equal [[:with_model, "gpt-4"]], calls
  end


  def test_apply_to_skips_non_llm_fields
    calls = []
    chat = Object.new
    chat.define_singleton_method(:respond_to?) { |m, *| m.to_s.start_with?("with_") ? true : super(m) }
    chat.define_singleton_method(:with_model) { |v| calls << [:with_model, v] }

    config = RobotLab::RunConfig.new(model: "gpt-4", mcp: :inherit, on_tool_call: -> {})
    config.apply_to(chat)

    assert_equal [[:with_model, "gpt-4"]], calls
  end


  # --- empty? ---

  def test_empty_true_when_no_fields
    assert RobotLab::RunConfig.new.empty?
  end


  def test_empty_false_when_fields_set
    refute RobotLab::RunConfig.new(model: "gpt-4").empty?
  end


  # --- key? ---

  def test_key_true_for_set_field
    config = RobotLab::RunConfig.new(model: "gpt-4")
    assert config.key?(:model)
  end


  def test_key_false_for_unset_field
    config = RobotLab::RunConfig.new(model: "gpt-4")
    refute config.key?(:temperature)
  end


  # --- equality ---

  def test_equality_same_fields
    a = RobotLab::RunConfig.new(model: "gpt-4", temperature: 0.5)
    b = RobotLab::RunConfig.new(model: "gpt-4", temperature: 0.5)
    assert_equal a, b
  end


  def test_inequality_different_fields
    a = RobotLab::RunConfig.new(model: "gpt-4")
    b = RobotLab::RunConfig.new(model: "gpt-3.5")
    refute_equal a, b
  end


  def test_inequality_with_non_run_config
    config = RobotLab::RunConfig.new(model: "gpt-4")
    refute_equal config, { model: "gpt-4" }
  end


  # --- inspect ---

  def test_inspect_includes_class_and_fields
    config = RobotLab::RunConfig.new(model: "gpt-4")
    assert_includes config.inspect, "RunConfig"
    assert_includes config.inspect, "model"
    assert_includes config.inspect, "gpt-4"
  end


  # --- FIELDS constant ---

  def test_fields_includes_all_categories
    all = RobotLab::RunConfig::LLM_FIELDS +
          RobotLab::RunConfig::TOOL_FIELDS +
          RobotLab::RunConfig::CALLBACK_FIELDS +
          RobotLab::RunConfig::INFRA_FIELDS

    assert_equal all, RobotLab::RunConfig::FIELDS
  end

  def test_ractor_pool_size_defaults_to_nil
    config = RobotLab::RunConfig.new
    assert_nil config.ractor_pool_size
  end

  def test_ractor_pool_size_can_be_set
    config = RobotLab::RunConfig.new(ractor_pool_size: 4)
    assert_equal 4, config.ractor_pool_size
  end

  def test_ractor_pool_size_merges
    base   = RobotLab::RunConfig.new(ractor_pool_size: 2)
    other  = RobotLab::RunConfig.new(ractor_pool_size: 8)
    merged = base.merge(other)
    assert_equal 8, merged.ractor_pool_size
  end

  def test_max_concurrent_robots_defaults_to_nil
    config = RobotLab::RunConfig.new
    assert_nil config.max_concurrent_robots
  end

  def test_max_concurrent_robots_can_be_set
    config = RobotLab::RunConfig.new(max_concurrent_robots: 10)
    assert_equal 10, config.max_concurrent_robots
  end

  def test_max_concurrent_robots_merges
    base   = RobotLab::RunConfig.new(max_concurrent_robots: 4)
    other  = RobotLab::RunConfig.new(max_concurrent_robots: 10)
    merged = base.merge(other)
    assert_equal 10, merged.max_concurrent_robots
  end

  def test_max_concurrent_robots_is_in_infra_fields
    assert_includes RobotLab::RunConfig::INFRA_FIELDS, :max_concurrent_robots
    assert_includes RobotLab::RunConfig::FIELDS, :max_concurrent_robots
  end
end
