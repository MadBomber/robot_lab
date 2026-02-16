# frozen_string_literal: true

require "test_helper"
require "stringio"

class RobotLab::AskUserTest < Minitest::Test
  def setup
    @robot = RobotLab::Robot.new(name: "helper", template: :assistant)
    @input = StringIO.new
    @output = StringIO.new
    @robot.input = @input
    @robot.output = @output
    @tool = RobotLab::AskUser.new(robot: @robot)
  end

  # ── Open-ended questions ──────────────────────────────────

  def test_returns_user_input
    @input.string = "Alice\n"

    result = @tool.call("question" => "What is your name?")

    assert_equal "Alice", result
  end

  def test_displays_robot_name_and_question
    @input.string = "yes\n"

    @tool.call("question" => "Continue?")

    output = @output.string
    assert_includes output, "[helper]"
    assert_includes output, "Continue?"
  end

  def test_displays_prompt_marker
    @input.string = "ok\n"

    @tool.call("question" => "Ready?")

    assert_includes @output.string, "> "
  end

  def test_returns_empty_string_on_empty_input
    @input.string = "\n"

    result = @tool.call("question" => "Name?")

    assert_equal "", result
  end

  # ── Default values ────────────────────────────────────────

  def test_default_used_on_empty_input
    @input.string = "\n"

    result = @tool.call("question" => "Continue?", "default" => "yes")

    assert_equal "yes", result
  end

  def test_default_shown_in_prompt
    @input.string = "no\n"

    @tool.call("question" => "Continue?", "default" => "yes")

    assert_includes @output.string, "> [yes]"
  end

  def test_user_input_overrides_default
    @input.string = "no\n"

    result = @tool.call("question" => "Continue?", "default" => "yes")

    assert_equal "no", result
  end

  # ── Multiple choice ──────────────────────────────────────

  def test_choices_displayed_numbered
    @input.string = "1\n"

    @tool.call("question" => "Pick:", "choices" => ["Ruby", "Python", "Go"])

    output = @output.string
    assert_includes output, "1. Ruby"
    assert_includes output, "2. Python"
    assert_includes output, "3. Go"
  end

  def test_numeric_input_maps_to_choice
    @input.string = "2\n"

    result = @tool.call("question" => "Pick:", "choices" => ["Ruby", "Python", "Go"])

    assert_equal "Python", result
  end

  def test_text_input_with_choices_returned_as_is
    @input.string = "Ruby\n"

    result = @tool.call("question" => "Pick:", "choices" => ["Ruby", "Python", "Go"])

    assert_equal "Ruby", result
  end

  def test_out_of_range_number_returned_as_is
    @input.string = "9\n"

    result = @tool.call("question" => "Pick:", "choices" => ["Ruby", "Python"])

    assert_equal "9", result
  end

  def test_zero_input_returned_as_is
    @input.string = "0\n"

    result = @tool.call("question" => "Pick:", "choices" => ["Ruby", "Python"])

    assert_equal "0", result
  end

  # ── Without robot ────────────────────────────────────────

  def test_works_without_robot
    input = StringIO.new("test\n")
    output = StringIO.new

    tool = RobotLab::AskUser.new

    # Stub $stdin/$stdout for this call
    original_stdin = $stdin
    original_stdout = $stdout
    begin
      $stdin = input
      $stdout = output
      result = tool.call("question" => "Name?")
    ensure
      $stdin = original_stdin
      $stdout = original_stdout
    end

    assert_equal "test", result
    assert_includes output.string, "[Robot]"
  end

  # ── Choices with default ─────────────────────────────────

  def test_choices_with_default_on_empty_input
    @input.string = "\n"

    result = @tool.call("question" => "Pick:", "choices" => ["A", "B"], "default" => "A")

    assert_equal "A", result
  end

  # ── Edge cases ───────────────────────────────────────────

  def test_nil_choices_treated_as_open_ended
    @input.string = "hello\n"

    result = @tool.call("question" => "Say something:", "choices" => nil)

    assert_equal "hello", result
    refute_includes @output.string, "1."
  end

  def test_empty_choices_array_treated_as_open_ended
    @input.string = "hello\n"

    result = @tool.call("question" => "Say something:", "choices" => [])

    assert_equal "hello", result
    refute_includes @output.string, "1."
  end
end
