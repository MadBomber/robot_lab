# frozen_string_literal: true

RobotLab.config.logger = Rails.logger

# Runs against a local Ollama server — no API keys required.
#   ollama serve
#   ollama pull qwen3.6
RubyLLM.configure do |c|
  c.logger          = Rails.logger
  c.ollama_api_base = ENV.fetch("OLLAMA_API_BASE", "http://localhost:11434/v1")
end
