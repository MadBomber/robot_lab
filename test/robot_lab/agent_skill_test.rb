# frozen_string_literal: true

require "test_helper"

class RobotLab::AgentSkillTest < Minitest::Test
  FIXTURES = Pathname.new(File.expand_path("../fixtures/skills", __dir__))

  def test_parses_name_and_description
    skill = RobotLab::AgentSkill.new(FIXTURES.join("test_skill", "SKILL.md"))
    assert_equal "test_skill", skill.name
    assert_equal "A test skill for verifying AgentSkills.io integration", skill.description
  end

  def test_parses_instructions_body
    skill = RobotLab::AgentSkill.new(FIXTURES.join("test_skill", "SKILL.md"))
    assert_includes skill.instructions, "rigorous testing practices"
  end

  def test_path_is_the_skill_directory
    skill = RobotLab::AgentSkill.new(FIXTURES.join("test_skill", "SKILL.md"))
    assert_equal FIXTURES.join("test_skill"), skill.path
  end

  def test_raises_configuration_error_when_description_missing
    assert_raises(RobotLab::ConfigurationError) do
      RobotLab::AgentSkill.new(FIXTURES.join("bad_skill", "SKILL.md"))
    end
  end

  def test_raises_configuration_error_when_name_missing
    assert_raises(RobotLab::ConfigurationError) do
      RobotLab::AgentSkill.new(FIXTURES.join("no_name_skill", "SKILL.md"))
    end
  end

  def test_scripts_returns_empty_when_no_scripts_directory
    skill = RobotLab::AgentSkill.new(FIXTURES.join("test_skill", "SKILL.md"))
    assert_equal [], skill.scripts
  end

  def test_scripts_returns_files_from_scripts_directory
    skill = RobotLab::AgentSkill.new(FIXTURES.join("scripted_skill", "SKILL.md"))
    assert_equal 1, skill.scripts.length
    assert_equal "hello.sh", skill.scripts.first.basename.to_s
  end

  def test_script_tools_returns_empty_for_no_scripts
    skill = RobotLab::AgentSkill.new(FIXTURES.join("test_skill", "SKILL.md"))
    assert_equal [], skill.script_tools
  end

  def test_script_tools_wraps_executable_scripts
    skill = RobotLab::AgentSkill.new(FIXTURES.join("scripted_skill", "SKILL.md"))
    tools = skill.script_tools
    assert_equal 1, tools.length
    assert_equal "hello", tools.first.name
  end
end
