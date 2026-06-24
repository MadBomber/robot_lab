# frozen_string_literal: true

require "tempfile"

module RobotLab
  module Sandbox
    # macOS strategy: generates a deny-by-default sandbox-exec profile from the
    # effective grant and wraps the command as
    #   sandbox-exec -f <profile> <cmd...>
    #
    # The profile allows process exec plus reads of system locations (so the
    # interpreter can load), reads of the skill bundle and granted paths, writes
    # only to granted paths (and the standard /dev sinks), and network only when
    # granted. Everything else -- notably $HOME, so SSH/cloud credentials --
    # is denied. Interpreters installed under $HOME (e.g. rbenv) are not visible;
    # declare them in fs_read or mark the skill trust: core.
    class Seatbelt
      # System locations a typical interpreter needs to read to start up.
      SYSTEM_READ = %w[/usr /bin /sbin /System /Library /opt /private/etc /dev /var/select].freeze
      DEV_WRITE   = %w[/dev/null /dev/stdout /dev/stderr /dev/dtracehelper /dev/tty].freeze

      def initialize(grant, skill_dir:)
        @grant     = grant
        @skill_dir = File.expand_path(skill_dir.to_s)
        @profile   = nil
      end

      def wrap(cmd)
        @profile = write_profile
        ["sandbox-exec", "-f", @profile, *cmd]
      end

      def cleanup
        File.unlink(@profile) if @profile && File.exist?(@profile)
      rescue StandardError
        nil
      end

      # The generated Seatbelt profile text (public for testing).
      def profile_text
        reads  = canonicalize(SYSTEM_READ + [@skill_dir] + @grant.fs_read)
        writes = canonicalize(@grant.fs_write)
        lines = [
          "(version 1)",
          # bsd.sb supplies the base rules a process needs to start (dyld, mach
          # bootstrap, etc.); without it a deny-default profile aborts the binary.
          '(import "bsd.sb")',
          "(deny default)",
          "(allow process-fork)",
          "(allow process-exec)",
          "(allow sysctl-read)",
          "(allow mach-lookup)",
          # Metadata (stat/lookup) on any path so the interpreter can traverse to
          # granted files; reading file *contents* stays restricted below.
          "(allow file-read-metadata)",
          read_rule(reads),
          write_rule(DEV_WRITE.map { |p| [:literal, p] } + writes.map { |p| [:subpath, p] })
        ]
        lines << "(allow network*)" if @grant.network
        "#{lines.compact.join("\n")}\n"
      end

      private

      def write_profile
        file = Tempfile.create(["robot_lab-sandbox-", ".sb"])
        file.write(profile_text)
        file.close
        file.path
      end

      # Resolve to the real (symlink-free) path the kernel matches against. macOS
      # symlinks /tmp -> /private/tmp, /var -> /private/var, etc., so logical
      # paths would never match. For not-yet-existing write targets, resolve the
      # nearest existing ancestor and re-append the remainder.
      def canonicalize(paths)
        Array(paths).map { |p| real_path(File.expand_path(p.to_s)) }.compact.uniq
      end

      def real_path(expanded)
        existing = expanded
        rest     = []
        until File.exist?(existing) || existing == "/"
          rest.unshift(File.basename(existing))
          existing = File.dirname(existing)
        end
        real = File.realpath(existing)
        rest.empty? ? real : File.join(real, *rest)
      rescue StandardError
        expanded
      end

      def read_rule(paths)
        subpaths = paths.map { |p| "(subpath #{p.inspect})" }.join(" ")
        "(allow file-read* #{subpaths})"
      end

      def write_rule(entries)
        clauses = entries.map { |kind, p| "(#{kind} #{p.inspect})" }.join(" ")
        "(allow file-write* #{clauses})"
      end
    end
  end
end
