# frozen_string_literal: true

require "rainbow"
require "unicode/display_width"
require "io/console"

# ── Display ─────────────────────────────────────────────────
#
# Terminal formatting for the Rusty Circuit demo.
#
#   - Comic output: left-aligned, cyan, word-wrapped
#   - Heckler output: right-indented, yellow, word-wrapped
#   - Scout observations: written to a markdown file (silent on STDOUT)
#   - Tool annotations: dimmed, indented under the triggering speaker
#   - Final verdict: green on STDOUT and appended to scout file
#
class Display
  def initialize(scout_path:, log_path: nil)
    @term_width = (IO.console&.winsize&.last || 80)
    @comic_width = (@term_width * 0.56).to_i
    @heckler_width = (@term_width * 0.52).to_i
    @scout_file = File.open(scout_path, "w")
    @scout_file.puts "# Scout Notes — The Rusty Circuit\n\n"
    @log_file = log_path ? File.open(log_path, "w") : nil
  end

  # ── Comic (left, cyan) ──────────────────────────────────

  def comic(label, text)
    puts
    puts Rainbow("  #{label}:").cyan.bright
    wrap(text, @comic_width).each do |line|
      puts Rainbow("    #{line}").cyan
    end
    puts

    log("\n  #{label}:")
    wrap(text, @comic_width).each { |line| log("    #{line}") }
    log("")
  end

  def comic_tool(text)
    puts Rainbow("           #{text}").darkgray
    log("           #{text}")
  end

  # ── Heckler (right, yellow) ─────────────────────────────

  def heckler(label, text)
    indent = [(@term_width - @heckler_width - 4), 4].max
    pad = " " * indent

    puts
    puts Rainbow("#{pad}#{label}:").yellow.bright
    wrap(text, @heckler_width).each do |line|
      puts Rainbow("#{pad}  #{line}").yellow
    end
    puts

    log("\n  #{label}:")
    wrap(text, @heckler_width).each { |line| log("    #{line}") }
    log("")
  end

  def heckler_note(text)
    indent = [(@term_width - @heckler_width - 4), 4].max
    pad = " " * indent
    puts Rainbow("#{pad}  #{text}").yellow.faint
    log("    #{text}")
  end

  # ── Liveness ────────────────────────────────────────────
  #
  # The scout writes its notes to a file, so a scout turn produces NO
  # terminal output at all — and a scout turn is 1-4 sequential LLM calls
  # (observe, then any tool round-trips, then a spawned analyst's own run).
  # On a local model that is minutes of dead-silent terminal, which reads
  # as a hang. These lines prove the show is still moving.

  def working(who, what)
    puts Rainbow("  · #{who} #{what}…").darkgray
    $stdout.flush
    log("  · #{who} #{what}...")
  end

  # ── Scout (file only) ───────────────────────────────────

  def scout(round_num, notes)
    @scout_file.puts "## Round #{round_num}\n\n#{notes}\n\n"
    @scout_file.flush
    log("  Scout [Round #{round_num}]: #{notes}")
  end

  def scout_analyst(name, text)
    @scout_file.puts "### Analyst: #{name}\n\n#{text}\n\n"
    @scout_file.flush
    log("           [#{name}_analyst] #{text}")
  end

  def scout_criteria(text)
    @scout_file.puts "### Criteria Refinement\n\n#{text}\n\n"
    @scout_file.flush
    log("           [refine_criteria] -> #{text}")
  end

  # ── Verdict (STDOUT green + file) ───────────────────────

  def verdict(label, text)
    puts
    puts Rainbow("  #{label}:").green.bright
    wrap(text, @term_width - 8).each do |line|
      puts Rainbow("    #{line}").green
    end
    puts

    @scout_file.puts "---\n\n## Final Verdict\n\n#{text}\n"
    @scout_file.flush

    log("\n  #{label}:")
    text.each_line { |line| log("    #{line.chomp}") }
    log("")
  end

  # ── Chrome ──────────────────────────────────────────────

  def banner(text)
    puts
    text.each_line { |line| puts Rainbow(line.chomp).bright }
    puts

    log("")
    text.each_line { |line| log(line.chomp) }
    log("")
  end

  def separator
    puts Rainbow("  #{"─" * (@term_width - 4)}").darkgray
    puts
    log("  #{"─" * 56}")
    log("")
  end

  def stats(text)
    puts
    text.each_line { |line| puts Rainbow(line.chomp).bright }

    log("")
    text.each_line { |line| log(line.chomp) }
  end

  def close
    @scout_file.close unless @scout_file.closed?
    @log_file&.close
  end

  private

  def log(line)
    return unless @log_file

    @log_file.puts line
    @log_file.flush
  end

  # Word-wrap text to fit within max_width display columns.
  # Uses Unicode::DisplayWidth for correct CJK / emoji handling.
  # Force-breaks any single word longer than max_width.
  def wrap(text, max_width)
    lines = []

    text.each_line do |paragraph|
      paragraph = paragraph.strip
      next(lines << "") if paragraph.empty?

      words = paragraph.split(/\s+/)
      current = +""

      words.each do |word|
        word_w = Unicode::DisplayWidth.of(word)

        # Force-break words wider than max_width
        if word_w > max_width
          unless current.empty?
            lines << current
            current = +""
          end
          chars = word.chars
          buf = +""
          chars.each do |ch|
            if Unicode::DisplayWidth.of(buf + ch) > max_width
              lines << buf
              buf = +ch
            else
              buf << ch
            end
          end
          current = buf
          next
        end

        cur_w = Unicode::DisplayWidth.of(current)
        if current.empty?
          current = +word
        elsif cur_w + 1 + word_w <= max_width
          current << " " << word
        else
          lines << current
          current = +word
        end
      end

      lines << current unless current.empty?
    end

    lines
  end
end
