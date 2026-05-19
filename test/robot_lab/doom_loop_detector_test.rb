# frozen_string_literal: true

require "test_helper"

class RobotLab::DoomLoopDetectorTest < Minitest::Test
  def setup
    @detector = RobotLab::DoomLoopDetector.new(threshold: 3)
  end

  # --- Basic tracking ---

  def test_fresh_detector_is_not_in_doom_loop
    refute @detector.doom_loop?
  end

  def test_single_call_is_not_doom_loop
    @detector.track("search")
    refute @detector.doom_loop?
  end

  def test_two_identical_calls_not_doom_loop_with_threshold_3
    2.times { @detector.track("search") }
    refute @detector.doom_loop?
  end

  # --- Consecutive (period-1) detection ---

  def test_three_identical_consecutive_calls_is_doom_loop
    3.times { @detector.track("search") }
    assert @detector.doom_loop?
  end

  def test_four_identical_calls_is_doom_loop
    4.times { @detector.track("search") }
    assert @detector.doom_loop?
  end

  def test_different_tool_names_not_consecutive_doom_loop
    @detector.track("search")
    @detector.track("write")
    @detector.track("search")
    refute @detector.doom_loop?
  end

  # --- Cyclic (period-N) detection ---

  def test_two_tool_cycle_detected_after_three_repetitions
    # A,B, A,B, A,B
    3.times do
      @detector.track("search")
      @detector.track("write")
    end
    assert @detector.doom_loop?
  end

  def test_three_tool_cycle_detected_after_three_repetitions
    # A,B,C, A,B,C, A,B,C
    3.times do
      @detector.track("read")
      @detector.track("analyze")
      @detector.track("write")
    end
    assert @detector.doom_loop?
  end

  def test_partial_cycle_not_detected
    # A,B, A,B, A — only 2.5 cycles, not 3
    2.times do
      @detector.track("read")
      @detector.track("write")
    end
    @detector.track("read")
    refute @detector.doom_loop?
  end

  def test_different_interleaved_pattern_not_cyclic
    @detector.track("read")
    @detector.track("write")
    @detector.track("search")
    @detector.track("read")
    @detector.track("write")
    @detector.track("analyze")
    refute @detector.doom_loop?
  end

  # --- Reset ---

  def test_reset_clears_sequence
    3.times { @detector.track("search") }
    assert @detector.doom_loop?
    @detector.reset
    refute @detector.doom_loop?
    assert_empty @detector.sequence
  end

  def test_detection_resumes_correctly_after_reset
    3.times { @detector.track("search") }
    @detector.reset
    2.times { @detector.track("search") }
    refute @detector.doom_loop?
    @detector.track("search")
    assert @detector.doom_loop?
  end

  # --- Warning message ---

  def test_consecutive_warning_names_the_tool
    3.times { @detector.track("file_search") }
    msg = @detector.warning_message
    assert_includes msg, "file_search"
    assert_includes msg, "loop"
  end

  def test_cyclic_warning_names_the_pattern
    3.times do
      @detector.track("read")
      @detector.track("write")
    end
    msg = @detector.warning_message
    assert_includes msg, "→"
    assert_includes msg, "loop"
  end

  # --- Custom threshold ---

  def test_custom_threshold_of_2
    detector = RobotLab::DoomLoopDetector.new(threshold: 2)
    2.times { detector.track("search") }
    assert detector.doom_loop?
  end

  def test_custom_threshold_of_5_requires_five_repetitions
    detector = RobotLab::DoomLoopDetector.new(threshold: 5)
    4.times { detector.track("search") }
    refute detector.doom_loop?
    detector.track("search")
    assert detector.doom_loop?
  end
end
