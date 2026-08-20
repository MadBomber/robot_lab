# frozen_string_literal: true

require "logger"

# Fallback for when direnv has not activated examples/.envrc
ENV["ROBOT_LAB_TEMPLATE_PATH"] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

# ── Local LLM Configuration ───────────────────────────────────────────────────
#
# Every example runs against a LOCAL model served by Ollama. No API keys, no
# network egress, no per-token cost. Pull the model once before running:
#
#   ollama pull qwen3.6
#
# Ollama models are not in RubyLLM's model registry, so a `provider:` must be
# supplied alongside `model:` — that is what makes RubyLLM skip the registry
# lookup (see Robot#initialize, which sets assume_model_exists when provider is
# given). Use the `llm_opts` helper below so every robot gets both.

LlmConfig = Data.define(:provider, :model)

LLM = {
  default: LlmConfig.new(provider: "ollama", model: "qwen3.6:latest"),
  small:   LlmConfig.new(provider: "ollama", model: "qwen2.5:7b"),
  large:   LlmConfig.new(provider: "ollama", model: "llama3.3:latest")
}.freeze

OLLAMA_API_BASE = ENV.fetch("OLLAMA_API_BASE", "http://localhost:11434/v1")

# ORDER MATTERS. The first touch of RobotLab.config runs Config#after_load,
# which calls RubyLLM.configure itself and would clobber anything set before
# it. So configure RobotLab first, then RubyLLM — the later block wins.
RobotLab.configure do |c|
  c.logger = Logger.new(File::NULL)
end

RubyLLM.configure do |c|
  c.logger          = Logger.new(File::NULL)
  c.default_model   = LLM[:default].model
  c.ollama_api_base = OLLAMA_API_BASE

  # A large local model on consumer hardware is far slower than a hosted API,
  # and robot_lab's bundled 120s default is comfortably exceeded by a long
  # answer from a 20B+ model — which surfaces mid-run as Net::ReadTimeout.
  #
  # Integer(), not the raw env string: this value reaches Net::HTTP directly,
  # and a String raises "can't convert String into time interval". That is
  # also why the ROBOT_LAB_RUBY_LLM__REQUEST_TIMEOUT env var is the wrong
  # lever here — env values arrive as strings.
  c.request_timeout = Integer(ENV.fetch("LLM_REQUEST_TIMEOUT", "900"))
  c.max_retries     = 1
end

# Which LLM entry an unqualified llm_opts resolves to. Lets you run any
# example against a faster model without editing it — worth knowing for the
# multi-robot demos (14, 15, 16), which are 30+ sequential LLM calls and take
# over half an hour on a 20B+ model:
#
#   LLM_PROFILE=small bundle exec ruby examples/14_rusty_circuit/open_mic.rb
LLM_PROFILE = ENV.fetch("LLM_PROFILE", "default").to_sym

unless LLM.key?(LLM_PROFILE)
  abort "Unknown LLM_PROFILE #{LLM_PROFILE.inspect}. Choose one of: #{LLM.keys.join(', ')}"
end

# Provider + model keyword pair for RobotLab.build / Robot.new.
#
# Both are required for a local Ollama model. Splat it into any robot
# constructor:
#
#   RobotLab.build(name: "helper", **llm_opts)          # honors LLM_PROFILE
#   RobotLab.build(name: "cheap",  **llm_opts(:small))  # pinned regardless
#
# @param key [Symbol, nil] which entry of LLM to use; defaults to LLM_PROFILE
# @return [Hash] { provider:, model: }
def llm_opts(key = nil)
  cfg = LLM.fetch(key || LLM_PROFILE)
  { provider: cfg.provider, model: cfg.model }
end

# Fail fast with an actionable message when Ollama isn't reachable, instead of
# letting every example die inside an HTTP adapter.
def require_ollama!
  require "net/http"
  uri = URI(OLLAMA_API_BASE.sub(%r{/v1/?$}, "") + "/api/tags")
  Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 2) { |h| h.get(uri.request_uri) }
rescue StandardError => e
  abort <<~ERROR
    Cannot reach Ollama at #{OLLAMA_API_BASE} (#{e.class}).

    Start it and pull the model used by the examples:
      ollama serve
      ollama pull #{LLM[:default].model.sub(/:latest\z/, "")}
  ERROR
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
