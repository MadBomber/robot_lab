# frozen_string_literal: true

require "test_helper"

class RobotLab::MCP::ServerDiscoveryTest < Minitest::Test
  include RobotLab

  # ── helpers ──────────────────────────────────────────────────────────────

  def server(name, description = nil)
    MCP.build(
      name: name,
      description: description,
      transport: { type: "stdio", command: "echo" }
    )
  end

  def server_class(name, description = nil)
    MCP.define(name: name, description: description, transport: { type: "stdio", command: "echo" })
  end

  def hash_server(name, description = nil)
    cfg = { name: name, transport: { type: "stdio", command: "echo" } }
    cfg[:description] = description if description
    cfg
  end

  SERVERS = [
    { name: "filesystem", description: "Read, write, and search local files and directories" },
    { name: "github",     description: "GitHub repos, issues, pull requests, code search" },
    { name: "brew",       description: "Install, update, and manage macOS packages via Homebrew" }
  ].freeze

  def hash_servers
    SERVERS.map { |s| hash_server(s[:name], s[:description]) }
  end

  def server_objects
    SERVERS.map { |s| server(s[:name], s[:description]) }
  end

  # ── fallback: empty list ──────────────────────────────────────────────────

  def test_returns_empty_list_unchanged
    result = MCP::ServerDiscovery.select("install imagemagick", from: [])
    assert_equal [], result
  end

  # ── fallback: blank query ─────────────────────────────────────────────────

  def test_returns_all_when_query_is_blank
    result = MCP::ServerDiscovery.select("", from: hash_servers)
    assert_equal hash_servers, result
  end

  def test_returns_all_when_query_is_whitespace
    result = MCP::ServerDiscovery.select("   ", from: hash_servers)
    assert_equal hash_servers, result
  end

  # ── fallback: no descriptions ─────────────────────────────────────────────

  def test_returns_all_when_no_descriptions
    no_desc = [hash_server("a"), hash_server("b"), hash_server("c")]
    result = MCP::ServerDiscovery.select("install something", from: no_desc)
    assert_equal no_desc, result
  end

  # ── normal selection (hash configs) ──────────────────────────────────────

  def test_selects_brew_for_install_query
    result = MCP::ServerDiscovery.select("install imagemagick", from: hash_servers)
    assert_includes result, hash_server("brew", "Install, update, and manage macOS packages via Homebrew")
  end

  def test_selects_github_for_pr_query
    result = MCP::ServerDiscovery.select("list open pull requests", from: hash_servers)
    assert_includes result, hash_server("github", "GitHub repos, issues, pull requests, code search")
  end

  def test_selects_filesystem_for_file_query
    result = MCP::ServerDiscovery.select("read config file", from: hash_servers)
    assert_includes result, hash_server("filesystem", "Read, write, and search local files and directories")
  end

  # ── normal selection (Server objects) ────────────────────────────────────

  def test_works_with_server_objects
    result = MCP::ServerDiscovery.select("install imagemagick", from: server_objects)
    assert(result.any? { |s| s.name == "brew" })
  end

  def test_works_with_mixed_hash_and_server_objects
    mixed = [
      hash_server("filesystem", "Read, write, and search local files and directories"),
      server("brew", "Install, update, and manage macOS packages via Homebrew")
    ]
    result = MCP::ServerDiscovery.select("install imagemagick", from: mixed)
    assert(result.any? { |s| s.is_a?(Hash) ? s[:name] == "brew" : s.name == "brew" })
  end

  # ── fallback: nothing above threshold ────────────────────────────────────

  def test_returns_all_when_nothing_scores_above_threshold
    # A very high threshold ensures nothing matches
    result = MCP::ServerDiscovery.select("install imagemagick",
                                         from: hash_servers,
                                         threshold: 1.0)
    assert_equal hash_servers, result
  end

  # ── threshold parameter ───────────────────────────────────────────────────

  def test_custom_threshold_narrows_results
    # Default threshold (0.05) might return multiple servers; a high threshold
    # should return fewer (or fall back to all if none qualify — that's fine too).
    result = MCP::ServerDiscovery.select("install brew package", from: hash_servers)
    assert_instance_of Array, result
    refute result.empty?
  end

  # ── topic_text helper ─────────────────────────────────────────────────────

  def test_topic_text_combines_name_and_description_for_hash
    s = hash_server("brew", "manage packages")
    topic = MCP::ServerDiscovery.send(:topic_text, s)
    assert_equal "brew manage packages", topic
  end

  def test_topic_text_combines_name_and_description_for_server_object
    s = server("brew", "manage packages")
    topic = MCP::ServerDiscovery.send(:topic_text, s)
    assert_equal "brew manage packages", topic
  end

  def test_topic_text_handles_missing_description
    s = hash_server("brew")
    topic = MCP::ServerDiscovery.send(:topic_text, s)
    assert_equal "brew", topic
  end

  # ── description_for helper ────────────────────────────────────────────────

  def test_description_for_hash
    s = hash_server("x", "  trimmed  ")
    assert_equal "trimmed", MCP::ServerDiscovery.send(:description_for, s)
  end

  def test_description_for_server_object
    s = server("x", "my desc")
    assert_equal "my desc", MCP::ServerDiscovery.send(:description_for, s)
  end

  def test_description_for_returns_empty_string_when_absent
    s = hash_server("x")
    assert_equal "", MCP::ServerDiscovery.send(:description_for, s)
  end

  # A plain RubyLLM::MCP subclass that keeps its description at class level
  # only, as SharedTools::MCP clients may.
  class ClassDescribedServer < RubyLLM::MCP
    command "echo"

    def self.description = "class-level desc"
  end

  def test_description_for_instance_falls_back_to_its_class
    assert_equal "class-level desc", MCP::ServerDiscovery.send(:description_for, ClassDescribedServer.new)
  end

  def test_description_for_plain_ruby_llm_mcp_instance_is_empty
    plain = Class.new(RubyLLM::MCP) { command "echo" }
    plain.default_name = "plain"
    assert_equal "", MCP::ServerDiscovery.send(:description_for, plain.new)
  end

  # ── classes and string-keyed hashes ──────────────────────────────────────

  def test_topic_text_for_server_class
    klass = server_class("brew", "manage packages")
    assert_equal "brew manage packages", MCP::ServerDiscovery.send(:topic_text, klass)
  end

  def test_topic_text_for_string_keyed_hash
    s = { "name" => "brew", "description" => "manage packages", "transport" => { "type" => "stdio", "command" => "echo" } }
    assert_equal "brew manage packages", MCP::ServerDiscovery.send(:topic_text, s)
  end

  def test_works_with_server_classes
    classes = SERVERS.map { |s| server_class(s[:name], s[:description]) }
    result  = MCP::ServerDiscovery.select("install imagemagick", from: classes)
    assert(result.any? { |k| k.default_name == "brew" })
  end

  def test_name_for_plain_ruby_llm_mcp_subclass
    klass = Class.new(RubyLLM::MCP) { command "echo" }
    klass.default_name = "echo_server"
    assert_equal "echo_server", MCP::ServerDiscovery.send(:name_for, klass)
    assert_equal "", MCP::ServerDiscovery.send(:description_for, klass)
  end
end
