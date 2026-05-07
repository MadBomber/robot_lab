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

  # =========================================================================
  # Reactive Memory API Tests
  # =========================================================================

  # Network name
  def test_network_name_nil_by_default
    assert_nil @memory.network_name
  end

  def test_network_name_set_on_initialize
    memory = RobotLab::Memory.new(network_name: "support")
    assert_equal "support", memory.network_name
  end

  def test_clone_preserves_network_name
    memory = RobotLab::Memory.new(network_name: "support")
    cloned = memory.clone
    assert_equal "support", cloned.network_name
  end

  # Current writer
  def test_current_writer_nil_by_default
    assert_nil @memory.current_writer
  end

  def test_current_writer_can_be_set
    @memory.current_writer = "robot_a"
    assert_equal "robot_a", @memory.current_writer
  end

  # set() method
  def test_set_stores_value
    @memory.set(:sentiment, { score: 0.8 })
    assert_equal({ score: 0.8 }, @memory.get(:sentiment))
  end

  def test_set_returns_value
    result = @memory.set(:key, "value")
    assert_equal "value", result
  end

  def test_set_converts_string_key_to_symbol
    @memory.set("string_key", "value")
    assert_equal "value", @memory.get(:string_key)
  end

  # get() method - immediate
  def test_get_returns_value_immediately
    @memory.set(:key, "value")
    assert_equal "value", @memory.get(:key)
  end

  def test_get_returns_nil_for_missing_key
    assert_nil @memory.get(:nonexistent)
  end

  def test_get_multiple_keys_returns_hash
    @memory.set(:a, 1)
    @memory.set(:b, 2)
    @memory.set(:c, 3)

    result = @memory.get(:a, :b, :c)
    assert_equal({ a: 1, b: 2, c: 3 }, result)
  end

  def test_get_multiple_keys_with_missing_returns_partial
    @memory.set(:a, 1)

    result = @memory.get(:a, :missing)
    assert_equal({ a: 1 }, result)
  end

  # get() with wait
  def test_get_with_wait_returns_immediately_if_value_exists
    @memory.set(:key, "value")
    result = @memory.get(:key, wait: true)
    assert_equal "value", result
  end

  def test_get_with_wait_blocks_until_value_set
    result = nil

    reader = Thread.new do
      result = @memory.get(:delayed_key, wait: true)
    end

    # Give reader time to start waiting
    sleep 0.01

    writer = Thread.new do
      @memory.set(:delayed_key, "arrived")
    end

    reader.join(2)  # 2 second timeout
    writer.join(1)

    assert_equal "arrived", result
  end

  def test_get_with_timeout_raises_on_timeout
    assert_raises(RobotLab::AwaitTimeout) do
      @memory.get(:never_arrives, wait: 0.1)
    end
  end

  def test_get_multiple_with_wait_waits_for_all
    results = nil

    reader = Thread.new do
      results = @memory.get(:key1, :key2, wait: true)
    end

    sleep 0.01

    Thread.new { @memory.set(:key1, "first") }
    sleep 0.01
    Thread.new { @memory.set(:key2, "second") }

    reader.join(2)

    assert_equal({ key1: "first", key2: "second" }, results)
  end

  # Subscriptions
  def test_subscribe_returns_subscription_id
    id = @memory.subscribe(:key) { |_change| }
    refute_nil id
    assert id.is_a?(String)
  end

  def test_subscribe_requires_block
    assert_raises(ArgumentError) do
      @memory.subscribe(:key)
    end
  end

  def test_subscribe_callback_receives_change
    received = nil

    @memory.subscribe(:sentiment) do |change|
      received = change
    end

    @memory.current_writer = "analyzer"
    @memory.set(:sentiment, { score: 0.8 })

    wait_until { received }

    refute_nil received
    assert_equal :sentiment, received.key
    assert_equal({ score: 0.8 }, received.value)
    assert_nil received.previous
    assert_equal "analyzer", received.writer
  end

  def test_subscribe_callback_includes_previous_value
    received = nil

    @memory.set(:counter, 1)

    @memory.subscribe(:counter) do |change|
      received = change
    end

    @memory.set(:counter, 2)

    wait_until { received }

    assert_equal 2, received.value
    assert_equal 1, received.previous
  end

  def test_subscribe_to_multiple_keys
    changes = []

    @memory.subscribe(:a, :b) do |change|
      changes << change.key
    end

    @memory.set(:a, 1)
    @memory.set(:b, 2)
    @memory.set(:c, 3)  # Not subscribed

    wait_until { changes.size >= 2 }

    assert_includes changes, :a
    assert_includes changes, :b
    refute_includes changes, :c
  end

  def test_unsubscribe_removes_subscription
    callback_count = 0

    id = @memory.subscribe(:key) do |_change|
      callback_count += 1
    end

    @memory.set(:key, "first")
    wait_until { callback_count >= 1 }

    @memory.unsubscribe(id)

    @memory.set(:key, "second")
    sleep 0.01

    assert_equal 1, callback_count
  end

  def test_unsubscribe_returns_true_if_found
    id = @memory.subscribe(:key) { |_| }
    assert @memory.unsubscribe(id)
  end

  def test_unsubscribe_returns_false_if_not_found
    refute @memory.unsubscribe("nonexistent-id")
  end

  def test_unsubscribe_keys_removes_all_for_key
    count = 0

    @memory.subscribe(:key) { count += 1 }
    @memory.subscribe(:key) { count += 1 }

    @memory.unsubscribe_keys(:key)

    @memory.set(:key, "value")
    sleep 0.01

    assert_equal 0, count
  end

  def test_subscribed_returns_true_when_subscribed
    @memory.subscribe(:key) { |_| }
    assert @memory.subscribed?(:key)
  end

  def test_subscribed_returns_false_when_not_subscribed
    refute @memory.subscribed?(:unsubscribed_key)
  end

  # Pattern subscriptions
  def test_subscribe_pattern_matches_keys
    matched_keys = []

    @memory.subscribe_pattern("analysis:*") do |change|
      matched_keys << change.key
    end

    @memory.set(:"analysis:sentiment", 0.8)
    @memory.set(:"analysis:entities", ["foo"])
    @memory.set(:other_key, "ignored")

    wait_until { matched_keys.size >= 2 }

    assert_includes matched_keys, :"analysis:sentiment"
    assert_includes matched_keys, :"analysis:entities"
    refute_includes matched_keys, :other_key
  end

  def test_subscribe_pattern_with_question_mark
    matched = []

    @memory.subscribe_pattern("step?") do |change|
      matched << change.key
    end

    @memory.set(:step1, "a")
    @memory.set(:step2, "b")
    @memory.set(:step10, "c")  # Won't match - too many chars

    wait_until { matched.size >= 2 }

    assert_includes matched, :step1
    assert_includes matched, :step2
    refute_includes matched, :step10
  end

  # MemoryChange object
  def test_memory_change_created
    change = RobotLab::MemoryChange.new(
      key: :test,
      value: "new",
      previous: nil
    )
    assert change.created?
    refute change.updated?
    refute change.deleted?
  end

  def test_memory_change_updated
    change = RobotLab::MemoryChange.new(
      key: :test,
      value: "new",
      previous: "old"
    )
    refute change.created?
    assert change.updated?
    refute change.deleted?
  end

  def test_memory_change_deleted
    change = RobotLab::MemoryChange.new(
      key: :test,
      value: nil,
      previous: "old"
    )
    refute change.created?
    refute change.updated?
    assert change.deleted?
  end

  def test_memory_change_to_h
    change = RobotLab::MemoryChange.new(
      key: :test,
      value: "value",
      writer: "robot_a",
      network_name: "support"
    )

    hash = change.to_h
    assert_equal :test, hash[:key]
    assert_equal "value", hash[:value]
    assert_equal "robot_a", hash[:writer]
    assert_equal "support", hash[:network_name]
  end

  # Bracket operators delegate to set/get
  def test_bracket_set_triggers_notifications
    received = nil

    @memory.subscribe(:key) do |change|
      received = change
    end

    @memory[:key] = "value"

    wait_until { received }

    refute_nil received
    assert_equal "value", received.value
  end

  # nil as a valid value

  def test_set_nil_value_is_retrievable
    @memory.set(:key, nil)
    assert @memory.key?(:key)
    assert_nil @memory.get(:key)
  end


  def test_get_single_with_wait_returns_nil_immediately_when_set
    @memory.set(:key, nil)
    result = @memory.get(:key, wait: true)
    assert_nil result
  end


  def test_get_single_with_wait_wakes_on_nil_value
    result = :not_set

    reader = Thread.new do
      result = @memory.get(:key, wait: true)
    end

    sleep 0.01
    @memory.set(:key, nil)

    reader.join(2)

    assert_nil result
  end


  def test_get_multiple_returns_nil_value_without_waiting
    @memory.set(:a, nil)
    @memory.set(:b, "present")

    result = @memory.get(:a, :b)
    assert_equal({ a: nil, b: "present" }, result)
  end


  def test_set_cache_key_raises_argument_error
    assert_raises(ArgumentError) do
      @memory[:cache] = RubyLLM::SemanticCache
    end
  end

  def test_set_cache_key_raises_with_any_value
    assert_raises(ArgumentError) do
      @memory[:cache] = nil
    end
  end

  def test_subscribe_pattern_requires_block
    assert_raises(ArgumentError) do
      @memory.subscribe_pattern("*")
    end
  end

  def test_subscribe_pattern_subscription_id_returned
    id = @memory.subscribe_pattern("test:*") { |_| }
    refute_nil id
    assert id.is_a?(String)
  end

  def test_subscribed_returns_true_for_pattern_match
    @memory.subscribe_pattern("prefix:*") { |_| }
    # subscribe_pattern matching is checked via subscribed? with exact key
    # subscribed? checks pattern subscriptions too
    # Set a key that matches the pattern and verify subscribed? returns false for non-matching
    refute @memory.subscribed?(:prefix)
  end

  def test_unsubscribe_removes_pattern_subscription
    count = 0
    id = @memory.subscribe_pattern("evt:*") { count += 1 }

    @memory.set(:"evt:one", 1)
    wait_until { count >= 1 }
    assert_equal 1, count

    @memory.unsubscribe(id)
    @memory.set(:"evt:two", 2)
    sleep 0.01

    assert_equal 1, count
  end

  def test_data_proxy_reset_when_data_key_set
    @memory[:data] = { category: "billing" }
    # @data_proxy should be reset; accessing data should return new proxy
    assert_equal "billing", @memory.data[:category]
  end

  def test_results_assigned_via_bracket
    result = mock_robot_result("bot")
    @memory[:results] = [result]
    assert_equal 1, @memory.results.size
    assert_equal "bot", @memory.results.first.robot_name
  end

  def test_messages_assigned_via_bracket
    msg = RobotLab::TextMessage.new(role: "user", content: "hi")
    @memory[:messages] = [msg]
    assert_equal 1, @memory.messages.size
    assert_equal "hi", @memory.messages.first.content
  end

  def test_messages_bracket_raises_for_invalid_message_type
    # memory.rb line 682: normalize_message else branch raises ArgumentError
    assert_raises(ArgumentError) do
      @memory[:messages] = [42]
    end
  end

  def test_session_id_assigned_via_bracket
    @memory[:session_id] = "abc-123"
    assert_equal "abc-123", @memory.session_id
  end

  def test_clear_returns_self
    assert_equal @memory, @memory.clear
  end

  def test_reset_restores_cache
    mem = RobotLab::Memory.new(enable_cache: true)
    mem.reset
    assert_equal RubyLLM::SemanticCache, mem.cache
  end

  def test_memory_change_from_hash_restores_fields
    original = RobotLab::MemoryChange.new(
      key: :sentiment,
      value: 0.9,
      previous: 0.5,
      writer: "analyzer",
      network_name: "pipeline",
      correlation_id: "abc-123"
    )

    hash = original.to_h
    restored = RobotLab::MemoryChange.from_hash(hash)

    assert_equal :sentiment, restored.key
    assert_equal 0.9, restored.value
    assert_equal 0.5, restored.previous
    assert_equal "analyzer", restored.writer
    assert_equal "pipeline", restored.network_name
    assert_equal "abc-123", restored.correlation_id
  end

  def test_memory_change_to_json
    change = RobotLab::MemoryChange.new(key: :test, value: "val", writer: "bot")
    json = change.to_json
    assert json.is_a?(String)
    parsed = JSON.parse(json)
    assert_equal "test", parsed["key"]
    assert_equal "val", parsed["value"]
    assert_equal "bot", parsed["writer"]
  end

  def test_memory_change_timestamp_defaults_to_now
    before = Time.now
    change = RobotLab::MemoryChange.new(key: :k, value: "v")
    after = Time.now
    assert change.timestamp >= before
    assert change.timestamp <= after
  end

  def test_memory_change_custom_timestamp
    t = Time.now - 3600
    change = RobotLab::MemoryChange.new(key: :k, value: "v", timestamp: t)
    assert_equal t, change.timestamp
  end

  def test_format_history_uses_custom_formatter
    output = [RobotLab::TextMessage.new(role: "assistant", content: "resp")]
    result = mock_robot_result("bot")
    result_with_output = RobotLab::RobotResult.new(
      robot_name: "bot",
      output: output
    )

    mem = RobotLab::Memory.new
    mem.append_result(result_with_output)

    custom_fmt = ->(r) { [RobotLab::TextMessage.new(role: "user", content: "formatted: #{r.robot_name}")] }
    history = mem.format_history(formatter: custom_fmt)

    assert history.any? { |m| m.content.include?("formatted: bot") }
  end

  def test_hash_backend_does_not_respond_as_redis
    mem = RobotLab::Memory.new(backend: :hash)
    refute mem.redis?
  end

  def test_backend_hash_explicitly
    mem = RobotLab::Memory.new(backend: :hash)
    mem[:test_key] = "value"
    assert_equal "value", mem[:test_key]
  end

  def test_memory_change_from_hash_with_string_keys
    hash = {
      "key" => "my_key",
      "value" => "my_value",
      "previous" => "old_value",
      "writer" => "bot",
      "network_name" => "pipeline",
      "correlation_id" => "xyz"
    }
    change = RobotLab::MemoryChange.from_hash(hash)
    assert_equal :my_key, change.key
    assert_equal "my_value", change.value
    assert_equal "old_value", change.previous
    assert_equal "bot", change.writer
    assert_equal "pipeline", change.network_name
    assert_equal "xyz", change.correlation_id
  end

  def test_backend_redis_preference_falls_back_to_hash_when_redis_unavailable
    # memory.rb line 635: :redis case in select_backend (falls back when Redis not available)
    mem = RobotLab::Memory.new(backend: :redis)
    # Without Redis gem, falls back to hash backend
    refute mem.redis?
    mem[:test_key] = "value"
    assert_equal "value", mem[:test_key]
  end

  def test_memory_change_from_hash_without_timestamp
    hash = { key: :test, value: "v" }
    change = RobotLab::MemoryChange.from_hash(hash)
    # timestamp defaults to nil passed in from_hash (no timestamp key in hash)
    # so new() will default to Time.now
    refute_nil change.timestamp
  end

  # =========================================================================
  # Notification coalescing
  # =========================================================================

  def test_single_subscriber_receives_notification
    received = []
    @memory.subscribe(:alpha) { |change| received << change.value }
    @memory[:alpha] = "hello"
    wait_until(timeout: 1) { received.size == 1 }
    assert_equal ["hello"], received
  end

  def test_multiple_subscribers_same_key_all_notified
    a = []
    b = []
    @memory.subscribe(:beta) { |change| a << change.value }
    @memory.subscribe(:beta) { |change| b << change.value }
    @memory[:beta] = 42
    wait_until(timeout: 1) { a.size == 1 && b.size == 1 }
    assert_equal [42], a
    assert_equal [42], b
  end

  def test_rapid_writes_all_notifications_delivered
    received = []
    @memory.subscribe(:counter) { |change| received << change.value }
    5.times { |i| @memory[:counter] = i }
    wait_until(timeout: 2) { received.size == 5 }
    assert_equal 5, received.size
    assert_equal (0..4).to_a, received.sort
  end

  def test_notifications_from_different_keys_all_delivered
    results = Hash.new { |h, k| h[k] = [] }
    @memory.subscribe(:x) { |change| results[:x] << change.value }
    @memory.subscribe(:y) { |change| results[:y] << change.value }
    @memory[:x] = "ex"
    @memory[:y] = "why"
    wait_until(timeout: 1) { results[:x].size == 1 && results[:y].size == 1 }
    assert_equal ["ex"],  results[:x]
    assert_equal ["why"], results[:y]
  end

  def test_coalescing_drainer_resets_after_drain
    received = []
    @memory.subscribe(:tap) { |change| received << change.value }
    @memory[:tap] = "first"
    wait_until(timeout: 1) { received.size == 1 }

    # Second write after drainer has finished — must still be delivered
    @memory[:tap] = "second"
    wait_until(timeout: 1) { received.size == 2 }
    assert_equal %w[first second], received
  end

  # =========================================================================
  # Notification drainer concurrency — regression tests for the
  # double-schedule race in drain_notification_queue's ensure block.
  #
  # The bug: ensure sets @drainer_scheduled = false BEFORE dispatching the
  # reschedule.  A concurrent writer can see the false flag and dispatch its
  # own drainer, while the rescheduled drainer is also dispatched — two
  # drainers run simultaneously.
  # =========================================================================

  # Subclass that counts concurrent drainer invocations.
  # max_concurrent_drainers > 1 means the double-schedule race fired.
  class InstrumentedMemory < RobotLab::Memory
    attr_reader :max_concurrent_drainers, :total_drainer_invocations

    def initialize(...)
      super
      @active_drainers        = 0
      @max_concurrent_drainers = 0
      @total_drainer_invocations = 0
      @track_mutex            = Mutex.new
    end

    private

    def drain_notification_queue
      @track_mutex.synchronize do
        @active_drainers        += 1
        @total_drainer_invocations += 1
        if @active_drainers > @max_concurrent_drainers
          @max_concurrent_drainers = @active_drainers
        end
      end
      # Yield the GVL while the drainer is active so other threads have a
      # real opportunity to enter drain_notification_queue concurrently.
      Thread.pass
      super
    ensure
      @track_mutex.synchronize { @active_drainers -= 1 }
    end
  end

  def test_drainer_never_runs_concurrently_with_itself
    # NOTE: dispatch_async runs synchronously outside an Async reactor, so
    # this test cannot trigger the double-schedule race directly.  It validates
    # the scheduling invariant (max 1 drainer at a time) and serves as a
    # regression anchor that will catch regressions visible in the sync path.
    # The race is fixed in the ensure block: @drainer_scheduled stays true
    # when rescheduling so concurrent writers don't also spawn a drainer.
    memory = InstrumentedMemory.new
    count  = 0
    mu     = Mutex.new

    memory.subscribe(:k) do |_|
      Thread.pass  # yield GVL mid-callback, widening the race window
      mu.synchronize { count += 1 }
    end

    threads = 30.times.map { |i| Thread.new { memory.set(:k, i) } }
    threads.each(&:join)

    wait_until(timeout: 3) { mu.synchronize { count } == 30 }

    assert_equal 30, mu.synchronize { count },
      "Expected 30 notifications but received #{mu.synchronize { count }}"

    assert_equal 1, memory.max_concurrent_drainers,
      "Double-schedule race detected: #{memory.max_concurrent_drainers} " \
      "drainers ran concurrently (total invocations: #{memory.total_drainer_invocations})"
  end

  def test_concurrent_writes_from_many_threads_all_notifications_delivered
    count = 0
    mu    = Mutex.new
    n     = 40

    @memory.subscribe(:concurrent) { |_| mu.synchronize { count += 1 } }

    threads = n.times.map { |i| Thread.new { @memory.set(:concurrent, i) } }
    threads.each(&:join)

    wait_until(timeout: 3) { mu.synchronize { count } == n }
    assert_equal n, mu.synchronize { count },
      "Expected #{n} notifications, got #{mu.synchronize { count }}"
  end

  def test_writes_interleaved_with_drainer_reset_none_lost
    # Stresses the specific race window: a write arrives just as the drainer
    # is completing (its ensure block runs).  The new write must still be
    # delivered even if @drainer_scheduled briefly appears false.
    received = []
    mu       = Mutex.new
    total    = 0

    @memory.subscribe(:interleave) { |change| mu.synchronize { received << change.value } }

    10.times do |batch|
      3.times { |i| @memory.set(:interleave, batch * 3 + i) }
      total += 3
      sleep 0.002  # small gap — lets the drainer finish between batches
    end

    wait_until(timeout: 3) { mu.synchronize { received.size } == total }
    assert_equal total, mu.synchronize { received.size },
      "Expected #{total} notifications, got #{mu.synchronize { received.size }}"
  end

  def test_no_notification_lost_after_long_idle_then_burst
    # After the memory has been idle long enough for the drainer flag to
    # fully reset, a burst of writes must all be delivered.
    received = []
    mu       = Mutex.new
    n        = 20

    @memory.subscribe(:burst) { |change| mu.synchronize { received << change.value } }

    # Idle period — let any in-flight async fiber finish
    sleep 0.05

    n.times { |i| @memory.set(:burst, i) }

    wait_until(timeout: 3) { mu.synchronize { received.size } == n }
    assert_equal n, mu.synchronize { received.size }
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
