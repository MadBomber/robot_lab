# frozen_string_literal: true

require "test_helper"

class RobotLab::StateProxyTest < Minitest::Test
  def setup
    @proxy = RobotLab::StateProxy.new({ count: 0, name: "test" })
  end

  # Initialization tests
  def test_initialization_with_hash
    proxy = RobotLab::StateProxy.new({ key: "value" })
    assert_equal "value", proxy[:key]
  end

  def test_initialization_with_empty_hash
    proxy = RobotLab::StateProxy.new
    assert proxy.empty?
  end

  def test_initialization_transforms_string_keys_to_symbols
    proxy = RobotLab::StateProxy.new({ "string_key" => "value" })
    assert_equal "value", proxy[:string_key]
    # String key lookup also works because getter converts to symbol
    assert_equal "value", proxy["string_key"]
    # Verify internally stored as symbol
    assert_includes proxy.keys, :string_key
    refute_includes proxy.keys, "string_key"
  end

  def test_initialization_with_on_change_callback
    changes = []
    proxy = RobotLab::StateProxy.new({}, on_change: ->(key, old, new_val) { changes << [key, old, new_val] })
    proxy[:key] = "value"

    assert_equal [[:key, nil, "value"]], changes
  end

  # Bracket access tests
  def test_bracket_getter
    assert_equal 0, @proxy[:count]
    assert_equal "test", @proxy[:name]
  end

  def test_bracket_getter_with_string_key
    assert_equal 0, @proxy["count"]
    assert_equal "test", @proxy["name"]
  end

  def test_bracket_getter_returns_nil_for_missing_key
    assert_nil @proxy[:missing]
  end

  def test_bracket_setter
    @proxy[:count] = 10
    assert_equal 10, @proxy[:count]
  end

  def test_bracket_setter_with_string_key
    @proxy["count"] = 20
    assert_equal 20, @proxy[:count]
  end

  def test_bracket_setter_returns_value
    result = (@proxy[:new_key] = "new_value")
    assert_equal "new_value", result
  end

  # Key existence tests
  def test_key_returns_true_for_existing_key
    assert @proxy.key?(:count)
    assert @proxy.key?(:name)
  end

  def test_key_returns_false_for_missing_key
    refute @proxy.key?(:missing)
  end

  def test_key_accepts_string_argument
    assert @proxy.key?("count")
  end

  def test_has_key_alias
    assert @proxy.has_key?(:count)
    refute @proxy.has_key?(:missing)
  end

  def test_include_alias
    assert @proxy.include?(:count)
    refute @proxy.include?(:missing)
  end

  # Keys and values tests
  def test_keys
    keys = @proxy.keys
    assert_includes keys, :count
    assert_includes keys, :name
  end

  def test_values
    values = @proxy.values
    assert_includes values, 0
    assert_includes values, "test"
  end

  # Each iteration test
  def test_each_iterates_over_key_value_pairs
    pairs = []
    @proxy.each { |k, v| pairs << [k, v] }

    assert_includes pairs, [:count, 0]
    assert_includes pairs, [:name, "test"]
  end

  # Delete test
  def test_delete_removes_key
    @proxy.delete(:count)
    refute @proxy.key?(:count)
  end

  def test_delete_returns_removed_value
    result = @proxy.delete(:count)
    assert_equal 0, result
  end

  def test_delete_with_string_key
    @proxy.delete("name")
    refute @proxy.key?(:name)
  end

  def test_delete_nonexistent_key_returns_nil
    assert_nil @proxy.delete(:nonexistent)
  end

  # Merge tests
  def test_merge_adds_new_keys
    @proxy.merge!({ new_key: "new_value" })
    assert_equal "new_value", @proxy[:new_key]
  end

  def test_merge_updates_existing_keys
    @proxy.merge!({ count: 100 })
    assert_equal 100, @proxy[:count]
  end

  def test_merge_returns_self
    result = @proxy.merge!({ key: "value" })
    assert_same @proxy, result
  end

  def test_merge_triggers_on_change_for_each_key
    changes = []
    proxy = RobotLab::StateProxy.new({ a: 1 }, on_change: ->(k, o, n) { changes << [k, o, n] })
    proxy.merge!({ a: 2, b: 3 })

    assert_equal 2, changes.size
    assert_includes changes, [:a, 1, 2]
    assert_includes changes, [:b, nil, 3]
  end

  # to_h tests
  def test_to_h_returns_hash
    hash = @proxy.to_h
    assert hash.is_a?(Hash)
    assert_equal 0, hash[:count]
    assert_equal "test", hash[:name]
  end

  def test_to_h_returns_copy
    hash = @proxy.to_h
    hash[:count] = 999
    assert_equal 0, @proxy[:count]
  end

  def test_to_hash_alias
    assert_equal @proxy.to_h, @proxy.to_hash
  end

  # Dup tests
  def test_dup_creates_independent_copy
    copy = @proxy.dup
    copy[:count] = 999

    assert_equal 999, copy[:count]
    assert_equal 0, @proxy[:count]
  end

  def test_dup_preserves_on_change_callback
    changes = []
    proxy = RobotLab::StateProxy.new({}, on_change: ->(k, o, n) { changes << [k, o, n] })
    copy = proxy.dup
    copy[:key] = "value"

    assert_equal 1, changes.size
  end

  def test_dup_deep_copies_nested_hashes
    proxy = RobotLab::StateProxy.new({ nested: { inner: "value" } })
    copy = proxy.dup
    copy[:nested][:inner] = "modified"

    assert_equal "modified", copy[:nested][:inner]
    assert_equal "value", proxy[:nested][:inner]
  end

  def test_dup_deep_copies_arrays
    proxy = RobotLab::StateProxy.new({ arr: [1, 2, 3] })
    copy = proxy.dup
    copy[:arr] << 4

    assert_equal [1, 2, 3, 4], copy[:arr]
    assert_equal [1, 2, 3], proxy[:arr]
  end

  # Empty and size tests
  def test_empty_returns_false_for_nonempty_proxy
    refute @proxy.empty?
  end

  def test_empty_returns_true_for_empty_proxy
    proxy = RobotLab::StateProxy.new
    assert proxy.empty?
  end

  def test_size
    assert_equal 2, @proxy.size
  end

  def test_length_alias
    assert_equal 2, @proxy.length
  end

  # Method missing tests
  def test_method_access_getter
    assert_equal 0, @proxy.count
    assert_equal "test", @proxy.name
  end

  def test_method_access_setter
    @proxy.count = 50
    assert_equal 50, @proxy[:count]
  end

  def test_method_access_raises_for_undefined_key
    assert_raises(NoMethodError) do
      @proxy.undefined_key
    end
  end

  def test_method_setter_creates_new_key
    @proxy.new_attribute = "value"
    assert_equal "value", @proxy[:new_attribute]
  end

  # respond_to_missing tests
  def test_respond_to_for_existing_key
    assert @proxy.respond_to?(:count)
    assert @proxy.respond_to?(:name)
  end

  def test_respond_to_for_setter
    assert @proxy.respond_to?(:count=)
  end

  def test_respond_to_for_missing_key
    refute @proxy.respond_to?(:undefined_key)
  end

  # On change callback tests
  def test_on_change_callback_receives_key_old_new_values
    changes = []
    proxy = RobotLab::StateProxy.new({ key: "old" }, on_change: ->(k, o, n) { changes << [k, o, n] })
    proxy[:key] = "new"

    assert_equal [[:key, "old", "new"]], changes
  end

  def test_on_change_not_called_when_value_unchanged
    changes = []
    proxy = RobotLab::StateProxy.new({ key: "same" }, on_change: ->(k, o, n) { changes << [k, o, n] })
    proxy[:key] = "same"

    assert_empty changes
  end

  def test_on_change_called_for_nil_to_value
    changes = []
    proxy = RobotLab::StateProxy.new({}, on_change: ->(k, o, n) { changes << [k, o, n] })
    proxy[:new_key] = "value"

    assert_equal [[:new_key, nil, "value"]], changes
  end

  # Inspect test
  def test_inspect
    result = @proxy.inspect
    assert_includes result, "RobotLab::StateProxy"
    assert_includes result, "count"
    assert_includes result, "name"
  end
end
