# frozen_string_literal: true

require "test_helper"

class RobotLab::MemoryTest < Minitest::Test
  def setup
    @memory = RobotLab::Memory.new
  end

  # Basic key-value operations
  def test_set_and_get_value
    @memory[:user_name] = "Alice"
    assert_equal "Alice", @memory[:user_name]
  end

  def test_set_with_string_key
    @memory["key"] = "value"
    assert_equal "value", @memory[:key]
  end

  def test_get_nonexistent_key_returns_nil
    assert_nil @memory[:nonexistent]
  end

  def test_key_exists
    @memory[:key] = "value"
    assert @memory.key?(:key)
  end

  def test_key_not_exists
    refute @memory.key?(:nonexistent)
  end

  def test_has_key_alias
    @memory[:key] = "value"
    assert @memory.has_key?(:key)
  end

  def test_include_alias
    @memory[:key] = "value"
    assert @memory.include?(:key)
  end

  # Reserved keys
  def test_reserved_keys_always_exist
    assert @memory.key?(:data)
    assert @memory.key?(:results)
    assert @memory.key?(:messages)
    assert @memory.key?(:session_id)
    assert @memory.key?(:cache)
  end

  def test_data_accessor
    assert @memory.data.is_a?(RobotLab::StateProxy)
  end

  def test_data_set_and_get
    @memory.data[:category] = "billing"
    assert_equal "billing", @memory.data[:category]
  end

  def test_data_method_style_access
    @memory.data[:name] = "Alice"
    assert_equal "Alice", @memory.data.name
  end

  def test_results_returns_empty_array_by_default
    assert_equal [], @memory.results
  end

  def test_messages_returns_empty_array_by_default
    assert_equal [], @memory.messages
  end

  def test_session_id_nil_by_default
    assert_nil @memory.session_id
  end

  def test_session_id_setter
    @memory.session_id = "thread-123"
    assert_equal "thread-123", @memory.session_id
  end

  def test_cache_is_semantic_cache_module
    assert_equal RubyLLM::SemanticCache, @memory.cache
  end

  def test_cache_nil_when_disabled
    memory = RobotLab::Memory.new(enable_cache: false)
    assert_nil memory.cache
  end

  def test_cache_enabled_by_default
    memory = RobotLab::Memory.new
    assert_equal RubyLLM::SemanticCache, memory.cache
  end

  def test_clone_preserves_enable_cache_true
    memory = RobotLab::Memory.new(enable_cache: true)
    cloned = memory.clone
    assert_equal RubyLLM::SemanticCache, cloned.cache
  end

  def test_clone_preserves_enable_cache_false
    memory = RobotLab::Memory.new(enable_cache: false)
    cloned = memory.clone
    assert_nil cloned.cache
  end

  # Keys management
  def test_keys_excludes_reserved_keys
    @memory[:custom1] = "value1"
    @memory[:custom2] = "value2"

    keys = @memory.keys
    assert_includes keys, :custom1
    assert_includes keys, :custom2
    refute_includes keys, :data
    refute_includes keys, :results
  end

  def test_all_keys_includes_reserved
    @memory[:custom] = "value"

    all = @memory.all_keys
    assert_includes all, :custom
    assert_includes all, :data
    assert_includes all, :results
  end

  def test_delete_custom_key
    @memory[:key] = "value"
    deleted = @memory.delete(:key)

    assert_equal "value", deleted
    refute @memory.key?(:key)
  end

  def test_delete_reserved_key_raises
    assert_raises(ArgumentError) do
      @memory.delete(:data)
    end
  end

  # Merge
  def test_merge_adds_values
    @memory.merge!(user_id: 123, session_id: "abc")

    assert_equal 123, @memory[:user_id]
    assert_equal "abc", @memory[:session_id]
  end

  def test_merge_returns_self
    assert_equal @memory, @memory.merge!(key: "value")
  end

  # Clear and reset
  def test_clear_removes_custom_keys
    @memory[:custom1] = "value1"
    @memory[:custom2] = "value2"
    @memory.clear

    assert_equal [], @memory.keys
  end

  def test_clear_preserves_reserved_keys
    @memory.data[:category] = "test"
    @memory.clear

    # Reserved keys still exist, data preserved
    assert @memory.key?(:data)
  end

  def test_clear_returns_self
    assert_equal @memory, @memory.clear
  end

  def test_reset_clears_everything
    @memory[:custom] = "value"
    @memory.data[:category] = "billing"
    @memory.reset

    assert_equal [], @memory.keys
    assert_equal({}, @memory.data.to_h)
    assert_equal [], @memory.results
    assert_nil @memory.session_id
  end

  # Results management
  def test_append_result
    result = mock_robot_result("robot1")
    @memory.append_result(result)

    assert_equal 1, @memory.results.size
    assert_equal result, @memory.results.first
  end

  def test_set_results
    results = [mock_robot_result("robot1"), mock_robot_result("robot2")]
    @memory.set_results(results)

    assert_equal 2, @memory.results.size
  end

  def test_results_from
    results = [mock_robot_result("robot1"), mock_robot_result("robot2"), mock_robot_result("robot3")]
    @memory.set_results(results)

    from_1 = @memory.results_from(1)
    assert_equal 2, from_1.size
    assert_equal "robot2", from_1.first.robot_name
  end

  # Clone
  def test_clone_creates_copy
    @memory[:custom] = "value"
    @memory.data[:category] = "billing"

    cloned = @memory.clone

    assert_equal "value", cloned[:custom]
    assert_equal "billing", cloned.data[:category]
  end

  def test_clone_is_isolated
    @memory[:custom] = "original"
    cloned = @memory.clone

    cloned[:custom] = "modified"
    assert_equal "original", @memory[:custom]
  end

  def test_dup_alias_for_clone
    @memory[:key] = "value"
    duped = @memory.dup

    assert_equal "value", duped[:key]
  end

  # Serialization
  def test_to_h_exports_memory
    @memory[:custom] = "value"
    @memory.data[:category] = "billing"

    hash = @memory.to_h

    assert_equal({ category: "billing" }, hash[:data])
    assert_equal({ custom: "value" }, hash[:custom])
  end

  def test_to_json
    @memory[:key] = "value"
    json = @memory.to_json

    assert json.is_a?(String)
    parsed = JSON.parse(json)
    assert_equal "value", parsed["custom"]["key"]
  end

  def test_from_hash
    hash = {
      data: { category: "billing" },
      session_id: "thread-123",
      custom: { user_id: 456 }
    }

    memory = RobotLab::Memory.from_hash(hash)

    assert_equal "billing", memory.data[:category]
    assert_equal "thread-123", memory.session_id
    assert_equal 456, memory[:user_id]
  end

  # Initialization
  def test_initialize_with_data
    memory = RobotLab::Memory.new(data: { category: "billing" })
    assert_equal "billing", memory.data[:category]
  end

  def test_initialize_with_session_id
    memory = RobotLab::Memory.new(session_id: "thread-123")
    assert_equal "thread-123", memory.session_id
  end

  def test_initialize_with_messages
    messages = [{ role: "user", content: "Hello", type: "text" }]
    memory = RobotLab::Memory.new(messages: messages)

    assert_equal 1, memory.messages.size
    assert_equal "Hello", memory.messages.first.content
  end

  # Format history
  def test_format_history_combines_messages_and_results
    memory = RobotLab::Memory.new(
      messages: [{ role: "user", content: "Hello", type: "text" }]
    )
    memory.append_result(mock_robot_result("robot1"))

    history = memory.format_history

    assert history.size >= 1  # At least the message
  end

  # Backend check
  def test_redis_returns_false_for_hash_backend
    refute @memory.redis?
  end

  # Thread safety
  def test_concurrent_access
    threads = 10.times.map do |i|
      Thread.new do
        100.times do |j|
          @memory["key_#{i}_#{j}"] = "value_#{i}_#{j}"
          @memory["key_#{i}_#{j}"]
        end
      end
    end

    threads.each(&:join)

    # Verify some data survived
    assert @memory.keys.size > 0
  end

  private

  def mock_robot_result(robot_name)
    RobotLab::RobotResult.new(
      robot_name: robot_name,
      output: [RobotLab::TextMessage.new(role: "assistant", content: "Response from #{robot_name}")],
      tool_calls: []
    )
  end
end
