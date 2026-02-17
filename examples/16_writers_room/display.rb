# frozen_string_literal: true

require "rainbow"
require "io/console"

# ── Display ─────────────────────────────────────────────────
#
# Terminal formatting for the Writers' Room demo.
#
#   - Broadcasts: white, prefixed with speaker name
#   - Direct messages: magenta, shows sender → recipient
#   - Memory writes: dimmed annotation
#   - Spawns: green annotation
#   - Completion: bright green
#   - Chapter content: cyan (when assembled)
#
class Display
  WRITER_COLORS = %i[cyan yellow blue magenta white].freeze

  def initialize(log_path: nil)
    @term_width = (IO.console&.winsize&.last || 80)
    @wrap_width = @term_width - 8
    @log_file = log_path ? File.open(log_path, "w") : nil
    @color_map = {}
    @next_color = 0
  end

  # ── Room Messages ──────────────────────────────────────────

  def broadcast(from, text)
    color = color_for(from)
    puts
    puts Rainbow("  [#{from}] (broadcast):").send(color).bright
    wrap(text, @wrap_width).each do |line|
      puts Rainbow("    #{line}").send(color)
    end

    log("\n  [#{from}] (broadcast):")
    wrap(text, @wrap_width).each { |line| log("    #{line}") }
  end

  def direct_message(from, to, text)
    puts Rainbow("    [#{from} -> #{to}]: #{text[0..100]}").magenta.faint
    log("    [#{from} -> #{to}]: #{text[0..100]}")
  end

  # ── Memory ─────────────────────────────────────────────────

  def memory_write(writer, key)
    puts Rainbow("    [memory] #{writer} wrote :#{key}").darkgray
    log("    [memory] #{writer} wrote :#{key}")
  end

  # ── Lifecycle ──────────────────────────────────────────────

  def spawn(requester, name)
    puts Rainbow("    [spawn] #{requester} recruited #{name}").green
    log("    [spawn] #{requester} recruited #{name}")
  end

  def complete(writer)
    puts
    puts Rainbow("  [#{writer}] marked the book as COMPLETE").green.bright
    log("\n  [#{writer}] marked the book as COMPLETE")
  end

  # ── Incoming message (from bus, before LLM processes) ──────

  def incoming(writer, from, content)
    puts Rainbow("    [#{writer}] heard #{from}: #{content.to_s[0..80]}...").darkgray
    log("    [#{writer}] heard #{from}: #{content.to_s[0..80]}...")
  end

  # ── Chrome ─────────────────────────────────────────────────

  def banner(text)
    puts
    text.each_line { |line| puts Rainbow(line.chomp).bright }
    puts

    log("")
    text.each_line { |line| log(line.chomp) }
  end

  def separator
    puts Rainbow("  #{"─" * (@term_width - 4)}").darkgray
    puts
    log("  #{"─" * 56}")
    log("")
  end

  def phase(text)
    puts
    puts Rainbow("  ▸ #{text}").bright
    puts
    log("\n  ▸ #{text}\n")
  end

  def info(text)
    puts Rainbow("  #{text}").darkgray
    log("  #{text}")
  end

  def stats(text)
    puts
    text.each_line { |line| puts Rainbow(line.chomp).bright }
    log("")
    text.each_line { |line| log(line.chomp) }
  end

  def close
    @log_file&.close
  end

  private

  def color_for(name)
    @color_map[name] ||= begin
      c = WRITER_COLORS[@next_color % WRITER_COLORS.size]
      @next_color += 1
      c
    end
  end

  def log(line)
    return unless @log_file

    @log_file.puts line
    @log_file.flush
  end

  def wrap(text, max_width)
    lines = []

    text.to_s.each_line do |paragraph|
      paragraph = paragraph.strip
      next(lines << "") if paragraph.empty?

      words = paragraph.split(/\s+/)
      current = +""

      words.each do |word|
        if current.empty?
          current = +word
        elsif current.length + 1 + word.length <= max_width
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
