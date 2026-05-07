# frozen_string_literal: true

require "test_helper"

module RobotLab
  class Robot
    class AgentSkillMatchingTest < Minitest::Test
      FIXTURES = File.expand_path("../../fixtures/skills", __dir__)

      def skill_for(name)
        path = File.join(FIXTURES, name.to_s, "SKILL.md")
        AgentSkill.new(path)
      end

      # Uses FakeSkillStore (defined in test_helper) — no extension gem needed.
      # Semantic score quality tests live in robot_lab-document_store gem.
      def robot_with_pending_skills(*skill_names)
        robot = build_robot(name: "test_bot")
        skills = skill_names.map { |n| skill_for(n) }
        store  = FakeSkillStore.new
        skills.each { |s| store.store(s.name.to_sym, s.description) }
        robot.instance_variable_set(:@pending_agent_skills, skills)
        robot.instance_variable_set(:@agent_skill_store, store)
        robot
      end

      def test_match_returns_empty_when_no_pending_skills
        robot = build_robot(name: "bot")
        result = robot.send(:match_agent_skills, "any message")
        assert_equal [], result
      end

      # FakeSkillStore always returns score 0.9, so threshold: 0.5 hits, threshold: 0.95 misses.
      def test_match_returns_skills_above_threshold
        robot = robot_with_pending_skills(:test_skill)
        result = robot.send(:match_agent_skills, "any message", threshold: 0.5)
        assert_equal 1, result.length
        assert_equal "test_skill", result.first.name
      end

      def test_match_returns_empty_below_threshold
        robot = robot_with_pending_skills(:test_skill)
        result = robot.send(:match_agent_skills, "any message", threshold: 0.95)
        assert_equal [], result
      end

      def test_inject_prepends_instructions_to_system_prompt
        robot = build_robot(name: "bot", system_prompt: "You are helpful.")
        skill = skill_for(:test_skill)
        robot.send(:inject_agent_skills, [skill])

        instructions = system_instructions(robot)
        assert instructions.start_with?(skill.instructions),
               "Expected system prompt to start with skill instructions"
        assert_includes instructions, "You are helpful."
      end

      def test_inject_adds_script_tools_to_local_tools
        robot = build_robot(name: "bot")
        skill = skill_for(:scripted_skill)
        robot.send(:inject_agent_skills, [skill])

        tool_names = robot.local_tools.map(&:name)
        assert_includes tool_names, "hello"
      end

      def test_restore_removes_injected_tools
        robot = build_robot(name: "bot")
        skill = skill_for(:scripted_skill)
        original_count = robot.local_tools.length

        robot.send(:inject_agent_skills, [skill])
        robot.send(:restore_after_agent_skills)

        assert_equal original_count, robot.local_tools.length
      end

      def test_restore_restores_original_system_prompt
        robot = build_robot(name: "bot", system_prompt: "You are helpful.")
        skill = skill_for(:test_skill)

        robot.send(:inject_agent_skills, [skill])
        robot.send(:restore_after_agent_skills)

        assert_equal "You are helpful.", system_instructions(robot)
      end

      def test_rerender_template_preserves_injected_skill_instructions
        robot = robot_with_pending_skills(:test_skill)
        skill = skill_for(:test_skill)

        robot.send(:inject_agent_skills, [skill])

        # Simulate rerender_template being called during a run() with runtime kwargs
        robot.send(:rerender_template, {})

        instructions = system_instructions(robot)
        assert_includes instructions, skill.instructions,
          "Expected skill instructions to survive rerender_template"
      end

      def test_match_degrades_gracefully_on_embedding_failure
        robot = build_robot(name: "bot")
        broken_store = Object.new
        def broken_store.search(*) = raise "fastembed failed"
        robot.instance_variable_set(:@pending_agent_skills, [skill_for(:test_skill)])
        robot.instance_variable_set(:@agent_skill_store, broken_store)

        result = robot.send(:match_agent_skills, "anything")
        assert_equal [], result
      end
    end
  end
end
