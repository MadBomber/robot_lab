# frozen_string_literal: true

require "test_helper"

module RobotLab
  class SandboxTest < Minitest::Test
    def enabled_config(flag)
      sandbox = Struct.new(:enabled).new(flag)
      Struct.new(:sandbox).new(sandbox)
    end

    def test_enabled_false_by_default_real_config
      refute Sandbox.enabled?
    end

    def test_enabled_reads_config_flag
      assert Sandbox.enabled?(enabled_config(true))
      refute Sandbox.enabled?(enabled_config(false))
      refute Sandbox.enabled?(Object.new)
    end

    def test_macos_matches_platform
      assert_equal RUBY_PLATFORM.include?("darwin"), Sandbox.macos?
    end

    def test_core_trust_gets_null_strategy_even_on_macos
      grant = Capabilities.new(trust: "core")
      assert_instance_of Sandbox::Null, Sandbox.for(grant, skill_dir: "/tmp")
    end

    def test_non_macos_gets_null_strategy
      grant = Capabilities.new(trust: "external")
      assert_instance_of Sandbox::Null, Sandbox.for(grant, skill_dir: "/tmp", macos: false)
    end

    def test_macos_external_gets_seatbelt
      grant = Capabilities.new(trust: "external")
      assert_instance_of Sandbox::Seatbelt, Sandbox.for(grant, skill_dir: "/tmp", macos: true)
    end

    def test_null_is_passthrough
      null = Sandbox::Null.new
      assert_equal %w[bash script], null.wrap(%w[bash script])
      assert_nil null.cleanup
    end

    def test_seatbelt_profile_structure
      grant = Capabilities.new(fs_read: ["/etc"], fs_write: [], network: false)
      text  = Sandbox::Seatbelt.new(grant, skill_dir: "/tmp").profile_text
      assert_includes text, "(deny default)"
      assert_includes text, '(import "bsd.sb")'
      assert_includes text, "(allow file-read*"
      assert_includes text, "(allow file-write*"
      refute_includes text, "(allow network*)"
    end

    def test_seatbelt_network_clause_only_when_granted
      granted = Sandbox::Seatbelt.new(Capabilities.new(network: true), skill_dir: "/tmp").profile_text
      assert_includes granted, "(allow network*)"
    end

    def test_seatbelt_canonicalizes_symlinked_paths
      # /tmp is a symlink to /private/tmp on macOS; the profile must use the
      # resolved path the kernel matches against.
      skip "macOS-specific path canonicalization" unless Sandbox.macos?

      text = Sandbox::Seatbelt.new(Capabilities.new(fs_write: ["/tmp/x"]), skill_dir: "/tmp").profile_text
      assert_includes text, "/private/tmp/x"
    end

    def test_seatbelt_wrap_and_cleanup
      sb = Sandbox::Seatbelt.new(Capabilities.new, skill_dir: "/tmp")
      wrapped = sb.wrap(%w[bash -c true])
      assert_equal "sandbox-exec", wrapped[0]
      assert_equal "-f", wrapped[1]
      profile = wrapped[2]
      assert File.exist?(profile)
      assert_equal %w[bash -c true], wrapped[3..]
      sb.cleanup
      refute File.exist?(profile)
    end

    # --- real confinement (macOS only) ---

    def test_seatbelt_confines_execution
      skip "Seatbelt is macOS-only" unless Sandbox.macos?
      require "open3"

      Dir.mktmpdir do |work|
        grant = Capabilities.new(fs_write: [work], timeout: 10)
        sb    = Sandbox::Seatbelt.new(grant, skill_dir: work)

        # write inside the grant succeeds
        out, st = Open3.capture2e(*sb.wrap(["bash", "-c", "echo ok > #{work}/f && echo WROTE"]))
        sb.cleanup
        assert st.success?, out
        assert_includes out, "WROTE"

        # write outside the grant is denied
        sb2 = Sandbox::Seatbelt.new(grant, skill_dir: work)
        denied = File.join(Dir.tmpdir, "rl_denied_#{Process.pid}.txt")
        _o, st2 = Open3.capture2e(*sb2.wrap(["bash", "-c", "echo x > #{denied}"]))
        sb2.cleanup
        refute st2.success?
        refute File.exist?(denied)
      end
    end
  end
end
