# frozen_string_literal: true

require "test_helper"
require "ractor_queue"
require "ractor/wrapper"

class RobotLab::RactorMemoryProxyTest < Minitest::Test
  def setup
    @memory = RobotLab::Memory.new(enable_cache: false)
    @proxy  = RobotLab::RactorMemoryProxy.new(@memory)
  end

  def teardown
    @proxy.shutdown
  end

  def test_set_and_get_from_thread
    @proxy.set(:color, "blue")
    assert_equal "blue", @proxy.get(:color)
  end

  def test_get_returns_nil_for_missing_key
    assert_nil @proxy.get(:nonexistent)
  end

  def test_keys_returns_array
    @proxy.set(:a, "1")
    @proxy.set(:b, "2")
    assert_includes @proxy.keys, :a
    assert_includes @proxy.keys, :b
  end

  def test_set_and_get_from_ractor
    # Pass the shareable stub (not the proxy) into the Ractor
    stub = @proxy.stub

    result = Ractor.new(stub) do |s|
      s.set(:ractor_key, "ractor_value")
      s.get(:ractor_key)
    end.value

    assert_equal "ractor_value", result
    assert_equal "ractor_value", @memory.get(:ractor_key)
  end

  def test_values_must_be_shareable
    assert_raises(RobotLab::RactorBoundaryError) do
      @proxy.set(:bad, StringIO.new)
    end
  end
end
