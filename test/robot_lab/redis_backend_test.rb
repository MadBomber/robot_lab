# frozen_string_literal: true

require "test_helper"

# In-memory fake that mimics the Redis gem API used by RedisBackend
class FakeRedis
  def initialize(**) = @store = {}
  def get(key) = @store[key]
  def set(key, value) = @store[key] = value
  def exists?(key) = @store.key?(key)
  def keys(pattern) = @store.keys.select { |k| File.fnmatch(pattern, k) }
  def del(key) = @store.delete(key)
end

class RobotLab::RedisBackendTest < Minitest::Test
  def setup
    @fake_redis = FakeRedis.new
    # Build backend, injecting the fake redis via stub
    @backend = RobotLab::RedisBackend.allocate
    @backend.instance_variable_set(:@redis, @fake_redis)
    @backend.instance_variable_set(:@namespace, "robot_lab:memory:test-ns")
  end

  # --- []= and [] round-trip ---

  def test_set_and_get_string
    @backend[:greeting] = "hello"
    assert_equal "hello", @backend[:greeting]
  end

  def test_set_and_get_hash
    @backend[:data] = { score: 0.8, tags: %w[a b] }
    result = @backend[:data]

    assert_equal 0.8, result[:score]
    assert_equal %w[a b], result[:tags]
  end

  def test_set_and_get_array
    @backend[:items] = [1, 2, 3]
    assert_equal [1, 2, 3], @backend[:items]
  end

  def test_set_and_get_integer
    @backend[:count] = 42
    assert_equal 42, @backend[:count]
  end

  def test_set_and_get_boolean
    @backend[:flag] = true
    assert_equal true, @backend[:flag]
  end

  def test_set_and_get_nil_value
    @backend[:empty] = nil
    # nil.to_json is "null", JSON.parse("null") returns nil
    assert_nil @backend[:empty]
  end

  def test_get_nonexistent_key_returns_nil
    assert_nil @backend[:nonexistent]
  end

  def test_set_returns_original_value
    original = { key: "value" }
    result = (@backend[:data] = original)
    assert_equal original, result
  end

  # --- JSON serialization ---

  def test_string_values_stored_as_is
    @backend[:name] = "Alice"
    raw = @fake_redis.get("robot_lab:memory:test-ns:name")
    assert_equal "Alice", raw
  end

  def test_non_string_values_stored_as_json
    @backend[:data] = { a: 1 }
    raw = @fake_redis.get("robot_lab:memory:test-ns:data")
    assert_equal '{"a":1}', raw
  end

  def test_get_handles_non_json_string_gracefully
    # Simulate a raw string that isn't valid JSON
    @fake_redis.set("robot_lab:memory:test-ns:raw", "not json {{{")
    result = @backend[:raw]
    assert_equal "not json {{{", result
  end

  def test_get_symbolizes_hash_keys
    @backend[:config] = { "string_key" => "value" }
    result = @backend[:config]
    assert_equal "value", result[:string_key]
  end

  # --- key? ---

  def test_key_exists_after_set
    @backend[:present] = "yes"
    assert @backend.key?(:present)
  end

  def test_key_does_not_exist_for_missing
    refute @backend.key?(:missing)
  end

  # --- keys ---

  def test_keys_returns_symbols
    @backend[:alpha] = 1
    @backend[:beta] = 2

    result = @backend.keys
    assert_includes result, :alpha
    assert_includes result, :beta
  end

  def test_keys_strips_namespace
    @backend[:mykey] = "val"
    result = @backend.keys

    result.each do |k|
      refute k.to_s.include?("robot_lab:memory"), "key should not contain namespace prefix"
    end
  end

  def test_keys_empty_when_nothing_stored
    assert_equal [], @backend.keys
  end

  # --- delete ---

  def test_delete_removes_key
    @backend[:doomed] = "bye"
    @backend.delete(:doomed)

    refute @backend.key?(:doomed)
    assert_nil @backend[:doomed]
  end

  def test_delete_returns_previous_value
    @backend[:key] = "value"
    deleted = @backend.delete(:key)
    assert_equal "value", deleted
  end

  def test_delete_returns_nil_for_missing_key
    result = @backend.delete(:nonexistent)
    assert_nil result
  end

  # --- clear ---

  def test_clear_removes_all_keys
    @backend[:a] = 1
    @backend[:b] = 2
    @backend[:c] = 3

    @backend.clear

    assert_equal [], @backend.keys
    assert_nil @backend[:a]
    assert_nil @backend[:b]
    assert_nil @backend[:c]
  end

  def test_clear_on_empty_backend
    @backend.clear
    assert_equal [], @backend.keys
  end

  # --- namespace isolation ---

  def test_different_namespaces_are_isolated
    other = RobotLab::RedisBackend.allocate
    other.instance_variable_set(:@redis, @fake_redis)
    other.instance_variable_set(:@namespace, "robot_lab:memory:other-ns")

    @backend[:shared_key] = "from_first"
    other[:shared_key] = "from_second"

    assert_equal "from_first", @backend[:shared_key]
    assert_equal "from_second", other[:shared_key]
  end
end
