# frozen_string_literal: true

require "test_helper"

class RobotLab::AgentSkillCatalogTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/skills", __dir__)

  def setup
    @catalog = RobotLab::AgentSkillCatalog.new(FIXTURES)
  end

  def teardown
    RobotLab::AgentSkillCatalog.reset!
  end

  def test_find_returns_agent_skill_by_symbol
    skill = @catalog.find(:test_skill)
    refute_nil skill
    assert_equal "test_skill", skill.name
  end

  def test_find_returns_agent_skill_by_string
    skill = @catalog.find("test_skill")
    refute_nil skill
    assert_equal "test_skill", skill.name
  end

  def test_find_returns_nil_for_unknown_id
    assert_nil @catalog.find(:nonexistent)
  end

  def test_all_returns_all_discovered_skills
    skills = @catalog.all
    names = skills.map(&:name)
    assert_includes names, "test_skill"
    assert_includes names, "scripted_skill"
  end

  def test_bad_skill_is_skipped_not_raised
    # bad_skill has no description; catalog should skip it with a warning
    skill = @catalog.find(:bad_skill)
    assert_nil skill
  end

  def test_skill_with_unsafe_front_matter_is_skipped_and_siblings_load
    Dir.mktmpdir do |root|
      { "dated" => "created: 2025-01-01", "good" => "version: 1" }.each do |name, extra|
        Dir.mkdir(File.join(root, name))
        File.write(File.join(root, name, "SKILL.md"), "---\nname: #{name}\ndescription: d\n#{extra}\n---\nBody\n")
      end

      catalog = RobotLab::AgentSkillCatalog.new(root)
      assert_equal ["good"], catalog.all.map(&:name)
    end
  end

  def test_instance_returns_same_object
    first  = RobotLab::AgentSkillCatalog.instance
    second = RobotLab::AgentSkillCatalog.instance
    assert_same first, second
  end

  def test_reset_clears_instance
    RobotLab::AgentSkillCatalog.instance
    RobotLab::AgentSkillCatalog.reset!
    assert_instance_of RobotLab::AgentSkillCatalog, RobotLab::AgentSkillCatalog.instance
  ensure
    RobotLab::AgentSkillCatalog.reset!
  end
end
