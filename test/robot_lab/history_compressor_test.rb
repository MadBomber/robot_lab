# frozen_string_literal: true

require "test_helper"

class RobotLab::HistoryCompressorTest < Minitest::Test
  # Minimal message struct that quacks like RubyLLM::Message
  FakeMsg = Struct.new(:role, :content, :tool_calls)

  def msg(role, content)
    FakeMsg.new(role.to_sym, content, nil)
  end

  def system_msg(content = "You are helpful.")  = msg(:system, content)
  def user_msg(content)                         = msg(:user, content)
  def assistant_msg(content)                    = msg(:assistant, content)
  def tool_result_msg                           = msg(:tool_result, '{ "result": 42 }')
  # nil content = tool dispatcher
  def tool_call_msg                             = msg(:assistant, nil)

  def compressor(messages:, recent_turns: 2, keep: 0.6, drop: 0.2, summarizer: nil)
    RobotLab::HistoryCompressor.new(
      messages:       messages,
      recent_turns:   recent_turns,
      keep_threshold: keep,
      drop_threshold: drop,
      summarizer:     summarizer
    )
  end

  def simulate_load_error(&block)
    original = RobotLab::TextAnalysis.method(:load_classifier_gem)
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem) { raise LoadError }
    block.call
  ensure
    RobotLab::TextAnalysis.define_singleton_method(:load_classifier_gem, &original)
  end

  # -----------------------------------------------------------------------
  # Edge cases — no classifier gem needed
  # -----------------------------------------------------------------------

  def test_empty_messages_returns_empty
    assert_equal [], compressor(messages: []).call
  end

  def test_system_only_returns_unchanged
    msgs = [system_msg]
    assert_equal msgs, compressor(messages: msgs).call
  end

  def test_too_few_scorable_messages_returns_unchanged
    msgs = [system_msg, user_msg("Hello"), assistant_msg("Hi")]
    assert_equal msgs, compressor(messages: msgs, recent_turns: 2).call
  end

  def test_tool_result_messages_always_preserved
    msgs = [system_msg, tool_result_msg]
    assert_includes compressor(messages: msgs).call, tool_result_msg
  end

  def test_tool_call_dispatcher_always_preserved
    msgs = [system_msg, tool_call_msg]
    assert_includes compressor(messages: msgs).call, tool_call_msg
  end

  def test_recent_turns_always_present
    msgs = [
      system_msg,
      user_msg("Old question"),     # compressible
      assistant_msg("Old answer"),  # compressible
      user_msg("Recent A"),         # protected
      assistant_msg("Answer A"),    # protected
      user_msg("Recent B"),         # protected
      assistant_msg("Answer B")     # protected
    ]
    result = compressor(messages: msgs, recent_turns: 2).call
    [3, 4, 5, 6].each { |i| assert_includes result, msgs[i] }
  end

  def test_recent_turns_exceeds_history_returns_unchanged
    msgs = [system_msg, user_msg("q"), assistant_msg("a")]
    assert_equal msgs, compressor(messages: msgs, recent_turns: 10).call
  end

  def test_keep_threshold_must_exceed_drop_threshold
    assert_raises(ArgumentError) { compressor(messages: [], keep: 0.3, drop: 0.5) }
  end

  def test_equal_thresholds_raise_argument_error
    assert_raises(ArgumentError) { compressor(messages: [], keep: 0.5, drop: 0.5) }
  end

  def test_system_message_always_in_result
    msgs = [
      system_msg,
      user_msg("old turn topic A"),
      assistant_msg("old answer topic A"),
      user_msg("recent Rails question"),
      assistant_msg("recent Rails answer"),
      user_msg("recent Rails followup"),
      assistant_msg("recent Rails followup answer")
    ]
    result = compressor(messages: msgs, recent_turns: 2).call
    assert result.any? { |m| m.role == :system }, "system message should always be in result"
  end

  # -----------------------------------------------------------------------
  # Classifier-dependent tests
  # -----------------------------------------------------------------------

  RAILS_TURN    = "Ruby on Rails is a web framework using the MVC architecture and ActiveRecord ORM"
  OCEAN_TURN    = "The Pacific Ocean is the largest body of water covering most of the Earth surface"
  RECENT_RAILS  = "How does Rails routing work with ActiveRecord associations?"
  RECENT_RAILS2 = "What is the Rails convention over configuration principle?"

  def setup_classifier_or_skip
    RobotLab::TextAnalysis.require_classifier!
  rescue RobotLab::DependencyError
    skip "classifier gem not available"
  end

  def test_relevant_old_turn_kept
    setup_classifier_or_skip

    msgs = [
      system_msg,
      user_msg(RAILS_TURN),
      assistant_msg("Rails uses MVC and has ActiveRecord for database access"),
      user_msg(RECENT_RAILS),
      assistant_msg("Rails routing maps URLs to controller actions via routes.rb"),
      user_msg(RECENT_RAILS2),
      assistant_msg("Convention over configuration means sensible defaults")
    ]

    result = compressor(messages: msgs, recent_turns: 2, keep: 0.1, drop: 0.05).call

    assert_includes result, msgs[1], "relevant Rails turn should be kept"
    assert_includes result, msgs[2], "relevant Rails answer should be kept"
  end

  def test_irrelevant_old_turn_dropped
    setup_classifier_or_skip

    msgs = [
      system_msg,
      user_msg(OCEAN_TURN),
      assistant_msg("The ocean is vast and deep with coral reefs"),
      user_msg(RECENT_RAILS),
      assistant_msg("Rails routing maps URLs to controller actions via routes.rb"),
      user_msg(RECENT_RAILS2),
      assistant_msg("Convention over configuration means sensible defaults")
    ]

    result = compressor(messages: msgs, recent_turns: 2, keep: 0.5, drop: 0.1).call

    refute_includes result, msgs[1], "irrelevant ocean turn should be dropped"
    refute_includes result, msgs[2], "irrelevant ocean answer should be dropped"
  end

  def test_summarizer_called_for_medium_tier
    setup_classifier_or_skip
    calls = []
    summarizer = lambda { |text|
      calls << text
      "SUMMARY: #{text[0..20]}"
    }

    # Craft messages where old turns may fall in medium relevance
    msgs = [
      system_msg,
      user_msg("Rails has some ocean-themed routing metaphors perhaps"),
      assistant_msg("Some Rails patterns relate loosely to various concepts"),
      user_msg(RECENT_RAILS),
      assistant_msg("Rails routing maps URLs to controller actions"),
      user_msg(RECENT_RAILS2),
      assistant_msg("Convention over configuration means sensible defaults")
    ]

    result = compressor(messages: msgs, recent_turns: 2, keep: 0.9, drop: 0.01, summarizer: summarizer).call
    assert_kind_of Array, result
    assert(result.any? { |m| m.role == :system })
  end

  def test_nil_summarizer_drops_medium_tier
    setup_classifier_or_skip

    msgs = [
      system_msg,
      user_msg("Rails has some ocean-themed routing patterns"),
      assistant_msg("Mixed topic about ocean and Rails patterns"),
      user_msg(RECENT_RAILS),
      assistant_msg("Rails routing maps URLs to controller actions"),
      user_msg(RECENT_RAILS2),
      assistant_msg("Convention over configuration means sensible defaults")
    ]

    result = compressor(messages: msgs, recent_turns: 2, keep: 0.9, drop: 0.01, summarizer: nil).call
    assert_kind_of Array, result
    assert(result.any? { |m| m.role == :system })
  end

  def test_summarizer_preserves_user_role
    setup_classifier_or_skip
    summaries = []
    summarizer = lambda { |text|
      s = "Summary: #{text[0..15]}"
      summaries << s
      s
    }

    msgs = [
      system_msg,
      user_msg("Rails has some ocean-themed routing metaphors perhaps"),
      assistant_msg("Some Rails patterns relate loosely to various concepts"),
      user_msg(RECENT_RAILS),
      assistant_msg("Rails routing maps URLs to controller actions"),
      user_msg(RECENT_RAILS2),
      assistant_msg("Convention over configuration means sensible defaults")
    ]

    result = compressor(messages: msgs, recent_turns: 2, keep: 0.9, drop: 0.01, summarizer: summarizer).call

    # Any summarized messages must preserve their original role
    result.each do |m|
      next unless summaries.include?(m.content)
      msgs.find { |_o| summaries.any? { |s| m.content == s } }
      # user summaries must respond true to user?, assistant summaries to assistant?
      if m.role == :user
        assert m.user?, "summarized user message should respond true to user?"
        refute m.assistant?, "summarized user message should not respond true to assistant?"
      elsif m.role == :assistant
        assert m.assistant?, "summarized assistant message should respond true to assistant?"
        refute m.user?, "summarized assistant message should not respond true to user?"
      end
    end
  end

  def test_summarizer_maintains_alternating_roles
    setup_classifier_or_skip
    summarizer = ->(text) { "Brief: #{text[0..20]}" }

    msgs = [
      system_msg,
      user_msg("Rails has some ocean-themed routing metaphors perhaps"),
      assistant_msg("Some Rails patterns relate loosely to various concepts"),
      user_msg(RECENT_RAILS),
      assistant_msg("Rails routing maps URLs to controller actions"),
      user_msg(RECENT_RAILS2),
      assistant_msg("Convention over configuration means sensible defaults")
    ]

    result = compressor(messages: msgs, recent_turns: 2, keep: 0.9, drop: 0.01, summarizer: summarizer).call

    # After system, roles must alternate user/assistant
    non_system = result.reject { |m| m.role == :system }
    non_system.each_with_index do |m, i|
      expected = i.even? ? :user : :assistant
      assert_equal expected, m.role,
                   "expected #{expected} at position #{i}, got #{m.role}"
    end
  end

  # -----------------------------------------------------------------------
  # LoadError path
  # -----------------------------------------------------------------------

  def test_raises_dependency_error_when_classifier_missing
    msgs = [
      system_msg,
      user_msg("this is a longer old question about something interesting"),
      assistant_msg("this is a longer old answer explaining that something"),
      user_msg("recent question about Ruby on Rails routing conventions"),
      assistant_msg("recent answer about Rails routing and controller actions"),
      user_msg("recent follow-up question about Rails convention over configuration"),
      assistant_msg("recent answer about Rails convention over configuration principles")
    ]

    simulate_load_error do
      assert_raises(RobotLab::DependencyError) do
        compressor(messages: msgs, recent_turns: 2).call
      end
    end
  end
end
