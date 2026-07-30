# frozen_string_literal: true

require "test_helper"

module RobotLab
  class CapabilitiesTest < Minitest::Test
    def test_defaults
      cap = Capabilities.new
      assert_empty cap.fs_read
      assert_empty cap.fs_write
      refute cap.network
      assert_equal Capabilities::DEFAULT_TIMEOUT, cap.timeout
      assert_equal "external", cap.trust
    end

    def test_from_front_matter_string_keys
      cap = Capabilities.from_front_matter(
        "fs_read" => ["a"], "fs_write" => ["b"], "network" => true, "timeout" => 5, "trust" => "core"
      )
      assert_equal ["a"], cap.fs_read
      assert cap.network
      assert_equal 5, cap.timeout
      assert cap.core?
    end

    def test_from_front_matter_nil_and_unknown_trust
      cap = Capabilities.from_front_matter(nil)
      assert_equal "external", cap.trust
      assert_equal "external", Capabilities.new(trust: "bogus").trust
    end

    def test_invalid_timeout_falls_back_to_default
      assert_equal Capabilities::DEFAULT_TIMEOUT, Capabilities.new(timeout: 0).timeout
      assert_equal Capabilities::DEFAULT_TIMEOUT, Capabilities.new(timeout: -3).timeout
    end

    def test_intersect_network_requires_both
      ceiling_off = Capabilities.new(network: false)
      ceiling_on  = Capabilities.new(network: true)
      assert Capabilities.new(network: true).intersect(ceiling_on).network
      refute Capabilities.new(network: true).intersect(ceiling_off).network
      refute Capabilities.new(network: false).intersect(ceiling_on).network
    end

    def test_intersect_timeout_is_minimum
      grant = Capabilities.new(timeout: 120).intersect(Capabilities.new(timeout: 30))
      assert_equal 30, grant.timeout
    end

    def test_intersect_clamps_paths_to_ceiling
      Dir.mktmpdir do |dir|
        inside  = File.join(dir, "inside")
        outside = "/etc"
        declared = Capabilities.new(fs_read: [inside, outside])
        ceiling  = Capabilities.new(fs_read: [dir])
        grant    = declared.intersect(ceiling)
        assert_includes grant.fs_read, File.expand_path(inside)
        refute_includes grant.fs_read, File.expand_path(outside)
      end
    end

    def test_intersect_preserves_trust
      grant = Capabilities.new(trust: "core").intersect(Capabilities.new)
      assert grant.core?
    end

    def test_ceiling_from_config_double
      sandbox = Struct.new(:fs_read, :fs_write, :network, :timeout)
                      .new(["/work"], ["/work/out"], true, 42)
      config  = Struct.new(:sandbox).new(sandbox)
      ceiling = Capabilities.ceiling(config)
      assert_equal [File.expand_path("/work")], ceiling.fs_read
      assert ceiling.network
      assert_equal 42, ceiling.timeout
    end

    def test_ceiling_without_sandbox_section
      config = Object.new
      ceiling = Capabilities.ceiling(config)
      assert_equal ["."], ceiling.fs_read
    end
  end
end
