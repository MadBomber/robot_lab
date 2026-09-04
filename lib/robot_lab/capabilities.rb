# frozen_string_literal: true

module RobotLab
  # Declared execution capabilities for a skill script: which paths it may read
  # and write, whether it may use the network, how long it may run, and how much
  # it is trusted.
  #
  # A skill declares what it *wants* in SKILL.md front matter; the global config
  # declares the *ceiling* of what any skill may have. The effective grant is the
  # intersection of the two (see {#intersect}) — anything the skill asks for that
  # the ceiling does not permit is dropped.
  class Capabilities
    DEFAULT_TIMEOUT = 60
    TRUST_LEVELS    = %w[core external].freeze

    attr_reader :fs_read, :fs_write, :network, :timeout, :trust

    # :reek:BooleanParameter -- `network` is a declared capability value (part of the data model), not a mode switch.
    # :reek:ControlParameter -- `network ? true : false` is boolean coercion of untrusted front-matter input, not behavior selection.
    def initialize(fs_read: [], fs_write: [], network: false, timeout: DEFAULT_TIMEOUT, trust: "external")
      @fs_read  = Array(fs_read).map(&:to_s)
      @fs_write = Array(fs_write).map(&:to_s)
      @network  = network ? true : false
      @timeout  = timeout.to_i.positive? ? timeout.to_i : DEFAULT_TIMEOUT
      @trust    = TRUST_LEVELS.include?(trust.to_s) ? trust.to_s : "external"
    end

    # Build from a SKILL.md front matter hash (string or symbol keys).
    # :reek:ControlParameter -- `front_matter || {}` is a nil-safe default, not control coupling.
    def self.from_front_matter(front_matter)
      fm = front_matter || {}
      new(
        fs_read:  fm_value(fm, :fs_read, []),
        fs_write: fm_value(fm, :fs_write, []),
        network:  fm_value(fm, :network, false),
        timeout:  fm_value(fm, :timeout, DEFAULT_TIMEOUT),
        trust:    fm_value(fm, :trust, "external")
      )
    end

    # Look up a front-matter key tolerating string or symbol keys.
    def self.fm_value(front_matter, key, default)
      value = front_matter[key.to_s]
      value = front_matter[key] if value.nil?
      value.nil? ? default : value
    end

    # Build the ceiling from the global config's sandbox section.
    def self.ceiling(config = RobotLab.config)
      section = config.respond_to?(:sandbox) ? config.sandbox : nil
      return new(fs_read: ["."]) unless section

      new(
        fs_read:  section.fs_read  || ["."],
        fs_write: section.fs_write || [],
        network:  section.network  || false,
        timeout:  section.timeout  || DEFAULT_TIMEOUT
      )
    end

    def core? = trust == "core"

    # Effective grant = this (declared) ∩ ceiling. Paths survive only when
    # inside a ceiling root; network requires both; timeout is the smaller;
    # trust stays as declared.
    def intersect(ceiling)
      self.class.new(
        fs_read:  clamp_paths(@fs_read, ceiling.fs_read),
        fs_write: clamp_paths(@fs_write, ceiling.fs_write),
        network:  @network && ceiling.network,
        timeout:  [@timeout, ceiling.timeout].min,
        trust:    @trust
      )
    end

    private

    # :reek:NestedIterators -- 2-deep select/any? over two small path lists is idiomatic Ruby.
    def clamp_paths(requested, allowed)
      roots = expand(allowed)
      expand(requested).select { |p| roots.any? { |r| p == r || p.start_with?("#{r}/") } }
    end

    def expand(paths)
      Array(paths).map { |p| File.expand_path(p.to_s) }
    end
  end
end
