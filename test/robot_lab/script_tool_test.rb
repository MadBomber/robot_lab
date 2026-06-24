# frozen_string_literal: true

require 'test_helper'

module RobotLab
  class ScriptToolTest < Minitest::Test
    FIXTURE_SCRIPT = File.expand_path(
      '../fixtures/skills/scripted_skill/scripts/hello.sh', __dir__
    )

    def test_from_path_returns_tool_instance
      tool = ScriptTool.from_path(FIXTURE_SCRIPT)
      refute_nil tool
      assert_respond_to tool, :name
    end

    def test_tool_name_derived_from_filename
      tool = ScriptTool.from_path(FIXTURE_SCRIPT)
      assert_equal 'hello', tool.name
    end

    def test_tool_description_from_first_comment
      tool = ScriptTool.from_path(FIXTURE_SCRIPT)
      assert_equal 'Say hello to the world', tool.description
    end

    def test_tool_execution_returns_script_output
      tool = ScriptTool.from_path(FIXTURE_SCRIPT)
      output = tool.call({})
      assert_includes output, 'Hello from AgentSkills script!'
    end

    def test_from_path_returns_nil_for_nonexecutable_script
      Tempfile.create(['nonexec', '.sh']) do |f|
        f.write("#!/bin/bash\necho hello")
        f.flush
        FileUtils.chmod(0o644, f.path)
        result = ScriptTool.from_path(f.path)
        assert_nil result
      end
    end

    def test_tool_name_with_hyphens_converted_to_underscores
      Dir.mktmpdir do |tmpdir|
        script_path = File.join(tmpdir, 'check-style.sh')
        File.write(script_path, "#!/bin/bash\necho ok")
        FileUtils.chmod(0o755, script_path)
        tool = ScriptTool.from_path(script_path)
        assert_equal 'check_style', tool.name
      end
    end

    def test_format_result_success_failure_and_timeout
      _o, ok   = Open3.capture2e('bash', '-c', 'exit 0')
      _o, fail = Open3.capture2e('bash', '-c', 'exit 3')
      assert_equal 'hi', ScriptTool.format_result('hi', ok)
      assert_includes ScriptTool.format_result('boom', fail), 'exit 3'
      assert_includes ScriptTool.format_result('partial', nil), 'timed out'
    end

    def test_run_with_timeout_kills_long_command
      output, status = ScriptTool.run_with_timeout(%w[sleep 5], 0.2)
      assert_nil status
      assert_includes output, 'killed'
    end

    def test_run_with_timeout_returns_output_within_budget
      output, status = ScriptTool.run_with_timeout(['bash', '-c', 'echo quick'], 10)
      assert status.success?
      assert_includes output, 'quick'
    end

    def test_execute_unconfined_when_sandbox_disabled
      # Default config: sandbox off -> unconfined, output unchanged.
      refute RobotLab::Sandbox.enabled?
      out = ScriptTool.execute(['bash', '-c', 'echo plain'],
                               capabilities: RobotLab::Capabilities.new, skill_dir: Dir.pwd)
      assert_includes out, 'plain'
    end

    def test_execute_confined_when_sandbox_enabled
      skip 'Seatbelt is macOS-only' unless RobotLab::Sandbox.macos?

      RobotLab.config.sandbox.enabled = true
      tool   = ScriptTool.from_path(FIXTURE_SCRIPT)
      output = tool.call({})
      assert_includes output, 'Hello from AgentSkills script!'
    ensure
      RobotLab.config.sandbox.enabled = false
    end
  end
end
