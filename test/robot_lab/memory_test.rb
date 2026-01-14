# frozen_string_literal: true

require "test_helper"

class RobotLab::MemoryTest < Minitest::Test
  def setup
    @memory = RobotLab::Memory.new
  end

  # Basic remember/recall operations
  def test_remember_and_recall
    @memory.remember(:user_name, "Alice")
    assert_equal "Alice", @memory.recall(:user_name)
  end

  def test_remember_with_string_key
    @memory.remember("key", "value")
    assert_equal "value", @memory.recall(:key)
  end

  def test_recall_nonexistent_key_returns_nil
    assert_nil @memory.recall(:nonexistent)
  end

  def test_recall_with_default_value
    assert_equal "default", @memory.recall(:nonexistent, default: "default")
  end

  def test_bracket_alias_for_remember
    @memory[:key] = "value"
    assert_equal "value", @memory.recall(:key)
  end

  def test_bracket_alias_for_recall
    @memory.remember(:key, "value")
    assert_equal "value", @memory[:key]
  end

  # Namespace operations
  def test_remember_with_namespace
    @memory.remember(:finding, "user prefers email", namespace: "classifier")
    assert_equal "user prefers email", @memory.recall(:finding, namespace: "classifier")
  end

  def test_namespace_isolation
    @memory.remember(:key, "shared_value")
    @memory.remember(:key, "namespaced_value", namespace: "robot1")

    assert_equal "shared_value", @memory.recall(:key)
    assert_equal "namespaced_value", @memory.recall(:key, namespace: "robot1")
  end

  def test_recall_from_wrong_namespace_returns_nil
    @memory.remember(:key, "value", namespace: "robot1")
    assert_nil @memory.recall(:key, namespace: "robot2")
    assert_nil @memory.recall(:key) # shared namespace
  end

  # Existence checks
  def test_exists_returns_true_for_existing_key
    @memory.remember(:key, "value")
    assert @memory.exists?(:key)
  end

  def test_exists_returns_false_for_nonexistent_key
    refute @memory.exists?(:nonexistent)
  end

  def test_exists_with_namespace
    @memory.remember(:key, "value", namespace: "robot1")

    assert @memory.exists?(:key, namespace: "robot1")
    refute @memory.exists?(:key, namespace: "robot2")
    refute @memory.exists?(:key)
  end

  def test_has_alias_for_exists
    @memory.remember(:key, "value")
    assert @memory.has?(:key)
  end

  # Forget operations
  def test_forget_removes_key
    @memory.remember(:key, "value")
    @memory.forget(:key)

    assert_nil @memory.recall(:key)
    refute @memory.exists?(:key)
  end

  def test_forget_returns_removed_value
    @memory.remember(:key, "value")
    assert_equal "value", @memory.forget(:key)
  end

  def test_forget_nonexistent_returns_nil
    assert_nil @memory.forget(:nonexistent)
  end

  def test_forget_with_namespace
    @memory.remember(:key, "value", namespace: "robot1")
    @memory.forget(:key, namespace: "robot1")

    refute @memory.exists?(:key, namespace: "robot1")
  end

  # All and namespaces
  def test_all_returns_shared_namespace_by_default
    @memory.remember(:key1, "value1")
    @memory.remember(:key2, "value2")

    all = @memory.all
    assert_equal "value1", all[:key1][:value]
    assert_equal "value2", all[:key2][:value]
  end

  def test_all_with_namespace
    @memory.remember(:key, "value", namespace: "robot1")

    all = @memory.all(namespace: "robot1")
    assert_equal "value", all[:key][:value]
  end

  def test_all_returns_empty_hash_for_empty_namespace
    assert_equal({}, @memory.all(namespace: "nonexistent"))
  end

  def test_namespaces_returns_all_namespace_names
    @memory.remember(:key1, "value1")
    @memory.remember(:key2, "value2", namespace: "robot1")
    @memory.remember(:key3, "value3", namespace: "robot2")

    namespaces = @memory.namespaces
    assert_includes namespaces, RobotLab::Memory::SHARED_NAMESPACE
    assert_includes namespaces, :robot1
    assert_includes namespaces, :robot2
  end

  # Clear operations
  def test_clear_removes_all_in_namespace
    @memory.remember(:key1, "value1")
    @memory.remember(:key2, "value2")
    @memory.clear

    assert_equal({}, @memory.all)
  end

  def test_clear_with_namespace
    @memory.remember(:shared_key, "shared")
    @memory.remember(:robot_key, "namespaced", namespace: "robot1")

    @memory.clear(namespace: "robot1")

    assert_equal "shared", @memory.recall(:shared_key)
    assert_nil @memory.recall(:robot_key, namespace: "robot1")
  end

  def test_clear_returns_self
    assert_equal @memory, @memory.clear
  end

  def test_clear_all_removes_everything
    @memory.remember(:key1, "value1")
    @memory.remember(:key2, "value2", namespace: "robot1")

    @memory.clear_all

    assert_equal({}, @memory.all)
    assert_equal({}, @memory.all(namespace: "robot1"))
  end

  # Search operations
  def test_search_finds_matching_values
    @memory.remember(:email, "alice@example.com")
    @memory.remember(:phone, "555-1234")

    results = @memory.search("alice")
    assert_equal 1, results.size
    assert results.key?(:email)
  end

  def test_search_with_regexp
    @memory.remember(:email1, "alice@example.com")
    @memory.remember(:email2, "bob@example.com")
    @memory.remember(:phone, "555-1234")

    results = @memory.search(/@example\.com/)
    assert_equal 2, results.size
  end

  def test_search_is_case_insensitive_for_strings
    @memory.remember(:name, "Alice")
    results = @memory.search("ALICE")
    assert_equal 1, results.size
  end

  def test_search_with_namespace
    @memory.remember(:key, "target", namespace: "robot1")
    @memory.remember(:key, "different", namespace: "robot2")

    results = @memory.search("target", namespace: "robot1")
    assert_equal 1, results.size
  end

  # Metadata tracking
  def test_stores_timestamp_metadata
    @memory.remember(:key, "value")
    entry = @memory.all[:key]

    assert entry[:stored_at].is_a?(Time)
    assert entry[:updated_at].is_a?(Time)
  end

  def test_tracks_access_count
    @memory.remember(:key, "value")

    @memory.recall(:key)
    @memory.recall(:key)
    @memory.recall(:key)

    entry = @memory.all[:key]
    assert_equal 3, entry[:access_count]
  end

  def test_tracks_last_accessed_at
    @memory.remember(:key, "value")
    @memory.recall(:key)

    entry = @memory.all[:key]
    assert entry[:last_accessed_at].is_a?(Time)
  end

  def test_stores_custom_metadata
    @memory.remember(:key, "value", source: "api", importance: :high)
    entry = @memory.all[:key]

    assert_equal "api", entry[:source]
    assert_equal :high, entry[:importance]
  end

  # Stats
  def test_stats_returns_memory_statistics
    @memory.remember(:key1, "value1")
    @memory.remember(:key2, "value2")
    @memory.remember(:key3, "value3", namespace: "robot1")

    stats = @memory.stats

    assert_equal 3, stats[:total_entries]
    assert_equal 2, stats[:namespaces]
    assert_equal 2, stats[:shared_entries]
    assert_equal({ shared: 2, robot1: 1 }, stats[:by_namespace])
  end

  # Serialization
  def test_to_h_exports_memory
    @memory.remember(:key, "value")
    hash = @memory.to_h

    assert hash[:shared].key?(:key)
    assert_equal "value", hash[:shared][:key][:value]
  end

  def test_to_json_serializes_memory
    @memory.remember(:key, "value")
    json = @memory.to_json

    assert json.is_a?(String)
    parsed = JSON.parse(json)
    assert_equal "value", parsed["shared"]["key"]["value"]
  end

  def test_from_hash_imports_memory
    hash = {
      "shared" => {
        "key" => { "value" => "test_value", "access_count" => 5 }
      },
      "robot1" => {
        "finding" => { "value" => "important" }
      }
    }

    memory = RobotLab::Memory.from_hash(hash)

    assert_equal "test_value", memory.recall(:key)
    assert_equal "important", memory.recall(:finding, namespace: "robot1")
  end

  # Scoped memory
  def test_scoped_returns_scoped_accessor
    scoped = @memory.scoped(:robot1)
    assert scoped.is_a?(RobotLab::ScopedMemory)
  end

  def test_scoped_memory_remember_and_recall
    scoped = @memory.scoped(:robot1)
    scoped.remember(:key, "value")

    assert_equal "value", scoped.recall(:key)
    assert_equal "value", @memory.recall(:key, namespace: "robot1")
  end

  def test_scoped_memory_bracket_aliases
    scoped = @memory.scoped(:robot1)
    scoped[:key] = "value"

    assert_equal "value", scoped[:key]
  end

  def test_scoped_memory_exists
    scoped = @memory.scoped(:robot1)
    scoped.remember(:key, "value")

    assert scoped.exists?(:key)
    assert scoped.has?(:key)
  end

  def test_scoped_memory_forget
    scoped = @memory.scoped(:robot1)
    scoped.remember(:key, "value")
    scoped.forget(:key)

    refute scoped.exists?(:key)
  end

  def test_scoped_memory_all
    scoped = @memory.scoped(:robot1)
    scoped.remember(:key1, "value1")
    scoped.remember(:key2, "value2")

    all = scoped.all
    assert_equal 2, all.size
  end

  def test_scoped_memory_clear
    scoped = @memory.scoped(:robot1)
    scoped.remember(:key, "value")
    scoped.clear

    assert_equal({}, scoped.all)
  end

  def test_scoped_memory_search
    scoped = @memory.scoped(:robot1)
    scoped.remember(:email, "test@example.com")

    results = scoped.search("test")
    assert_equal 1, results.size
  end

  def test_scoped_memory_shared_accessor
    @memory.remember(:shared_key, "shared_value")
    scoped = @memory.scoped(:robot1)

    assert_equal "shared_value", scoped.shared.recall(:shared_key)
  end

  def test_scoped_memory_to_h
    scoped = @memory.scoped(:robot1)
    scoped.remember(:key, "value")

    assert scoped.to_h.key?(:key)
  end

  # Thread safety (basic verification)
  def test_concurrent_access
    threads = 10.times.map do |i|
      Thread.new do
        100.times do |j|
          @memory.remember("key_#{i}_#{j}", "value_#{i}_#{j}")
          @memory.recall("key_#{i}_#{j}")
        end
      end
    end

    threads.each(&:join)

    # Verify some data survived
    assert @memory.stats[:total_entries] > 0
  end
end
