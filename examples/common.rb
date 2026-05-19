# frozen_string_literal: true

require "logger"

# Fallback for when direnv has not activated examples/.envrc
ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

LlmConfig = Data.define(:provider, :model)

LLM = {
  default:   LlmConfig.new(provider: "openai",    model: "gpt-5.4"),
  local:     LlmConfig.new(provider: "ollama",    model: "llama3.2"),
  anthropic: LlmConfig.new(provider: "anthropic", model: "claude-opus-4-7")
}.freeze

RubyLLM.configure do |c|
  c.logger        = Logger.new(File::NULL)
  c.default_model = LLM[:default].model
end

RobotLab.configure do |c|
  c.logger = Logger.new(File::NULL)
end

# ── Example Output Helpers ─────────────────────────────────────────────────────

module ExOut
  WIDTH = 68
  RESET = "\e[0m"
  BOLD  = "\e[1m"
  DIM   = "\e[2m"
  CYAN  = "\e[36m"
end

# Prints a bold top-level header. Extracts the example number from $0
# automatically so callers only supply the title.
def banner(title)
  num   = File.basename($0, ".rb")[/^\d+/]&.to_i
  label = num ? "Example #{num}: #{title}" : title
  puts
  puts "#{ExOut::BOLD}#{"=" * ExOut::WIDTH}#{ExOut::RESET}"
  puts "#{ExOut::BOLD} #{label}#{ExOut::RESET}"
  puts "#{ExOut::BOLD}#{"=" * ExOut::WIDTH}#{ExOut::RESET}"
  puts
end

# Prints a named section divider with a cyan rule.
def section(title)
  puts
  tail = "─" * [ExOut::WIDTH - title.length - 4, 2].max
  puts "#{ExOut::BOLD}#{ExOut::CYAN}── #{title} #{tail}#{ExOut::RESET}"
  puts
end

# Prints a plain dim horizontal rule.
def hr
  puts "#{ExOut::DIM}#{"─" * ExOut::WIDTH}#{ExOut::RESET}"
end

# Prints a Rouge-highlighted Ruby code block with a framed border.
def show_code(ruby_string, label: "ruby")
  require "rouge"
  w      = ExOut::WIDTH - 2
  border = "#{ExOut::DIM}  #{"─" * w}#{ExOut::RESET}"
  output = Rouge::Formatters::Terminal256.new
            .format(Rouge::Lexers::Ruby.new.lex(ruby_string))
  output += "\n" unless output.end_with?("\n")
  puts
  puts "#{ExOut::DIM}  #{label}#{ExOut::RESET}"
  puts border
  output.each_line { |l| print "  #{l}" }
  puts border
  puts
end
