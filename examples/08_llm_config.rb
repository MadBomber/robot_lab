#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 8: LLM Configuration via MywayConfig
#
# Demonstrates how RobotLab uses MywayConfig for environment-specific
# configuration (similar to Rails database.yml).
#
# Configuration is loaded from multiple sources in priority order:
#   1. Bundled defaults (lib/robot_lab/config/defaults.yml)
#   2. Environment-specific overrides (development, test, production)
#   3. XDG user config (~/.config/robot_lab/config.yml)
#   4. Project config (./config/robot_lab.yml)
#   5. Environment variables (ROBOT_LAB_*)
#   6. Template front matter (model, temperature, etc. in .md YAML header)
#   7. Constructor parameters (model:, temperature:, etc. passed to Robot.new)
#   8. with_* methods (runtime chaining, e.g. robot.with_temperature(0.9))
#   9. Run-time context (kwargs passed to robot.run that re-render the template)
#
# Environment is determined by ROBOT_LAB_ENV, RAILS_ENV, or RACK_ENV.
#
# Environment variable examples:
#   ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...
#   ROBOT_LAB_RUBY_LLM__MODEL=gpt-4
#   ROBOT_LAB_RUBY_LLM__REQUEST_TIMEOUT=180
#
# Usage:
#   ANTHROPIC_API_KEY=your_key ruby examples/08_llm_config.rb
#   ROBOT_LAB_ENV=test ANTHROPIC_API_KEY=your_key ruby examples/08_llm_config.rb
#   ROBOT_LAB_ENV=production ANTHROPIC_API_KEY=your_key ruby examples/08_llm_config.rb

# Configure template path before loading (MywayConfig reads env vars on init)
ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

# =============================================================================
# Demonstration
# =============================================================================

puts "=" * 70
puts "Example 8: LLM Configuration via MywayConfig"
puts "=" * 70
puts

# --- Gather environment from the user via AskUser ---
ask = RobotLab::AskUser.new
env = ask.call(
  "question" => "Which environment should the demo run in?",
  "choices"  => %w[development test production],
  "default"  => ENV['ROBOT_LAB_ENV'] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || "development"
)
puts

# Display configuration values (hiding sensitive keys)
config = RobotLab.config

puts "Core Settings:"
puts "  max_iterations:     #{config.max_iterations}"
puts "  streaming_enabled:  #{config.streaming_enabled}"
puts "  template_path:      #{config.template_path || '(default)'}"
puts

puts "RubyLLM Settings:"
puts "  model:              #{config.ruby_llm.model}"
puts "  provider:           #{config.ruby_llm.provider}"
puts "  request_timeout:    #{config.ruby_llm.request_timeout}s"
puts "  max_retries:        #{config.ruby_llm.max_retries}"
puts "  log_level:          #{config.ruby_llm.log_level}"

# Show API key status without revealing values
api_key = config.ruby_llm.anthropic_api_key
puts "  anthropic_api_key:  #{api_key ? '[SET via config]' : (ENV['ANTHROPIC_API_KEY'] ? '[SET via env]' : '(not set)')}"
puts

puts "-" * 70
puts "Configuration hierarchy (highest priority first):"
puts
puts "  Per-Robot (override global settings for a specific robot):"
puts "  11. Run-time context:      kwargs to robot.run re-render template"
puts "  10. with_* methods:        robot.with_temperature(0.9).ask(...)"
puts "   9. Constructor params:    Robot.new(model: ..., temperature: ...)"
puts "   8. Template front matter: model, temperature, etc. in .md YAML header"
puts "   7. Robot RunConfig:       run_config: passed to Robot constructor"
puts
puts "  Network/Task (shared defaults for a group of robots):"
puts "   6. Task RunConfig:        run_config: passed to task() in network"
puts "   5. Network RunConfig:     run_config: passed to create_network()"
puts
puts "  Global (apply to all robots unless overridden):"
puts "   4. Environment variables: ROBOT_LAB_RUBY_LLM__MODEL, etc."
puts "   3. Project config:        ./config/robot_lab.yml"
puts "   2. User config:           ~/.config/robot_lab/config.yml"
puts "   1. Bundled defaults:      lib/robot_lab/config/defaults.yml + env overrides"
puts "-" * 70
puts

# --- RunConfig demonstration ---
puts "-" * 70
puts "RunConfig: Shared Operational Defaults"
puts "-" * 70
puts

shared = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.5)
puts "  shared = RunConfig.new(model: \"claude-sonnet-4\", temperature: 0.5)"
puts "  shared.to_h => #{shared.to_h.inspect}"
puts

creative = RobotLab::RunConfig.new(temperature: 0.9)
merged = shared.merge(creative)
puts "  creative = RunConfig.new(temperature: 0.9)"
puts "  merged = shared.merge(creative)"
puts "  merged.to_h => #{merged.to_h.inspect}"
puts "  (model inherited from shared, temperature overridden by creative)"
puts

# Create a robot using the configuration
robot = RobotLab.build(
  name: "config_demo",
  template: :llm_config_demo,
  local_tools: [RobotLab::AskUser],
  context: {
    environment: env,
    model: config.ruby_llm.model,
    provider: config.ruby_llm.provider.to_s
  }
)

puts "Running robot with #{env} configuration..."
puts "Model: #{robot.model}"
puts

# Run the robot
result = robot.run(
  "Briefly explain how environment-specific LLM configuration works " \
  "and why it's useful."
)

# Display the result
puts "Response:"
result.output.each do |message|
  puts message.content if message.respond_to?(:content)
end

puts <<~FOOTER

  #{"=" * 70}
  Configuration demonstrated successfully!

  Configuration flows through three layers:
    Global (MywayConfig): YAML defaults, env overrides, XDG, env vars
    Network/Task (RunConfig): shared defaults for groups of robots
    Per-Robot: RunConfig, template front matter, constructor params, with_*

  RunConfig lets you express shared defaults that flow through the hierarchy:
    shared = RobotLab::RunConfig.new(model: "claude-sonnet-4", temperature: 0.5)
    network = RobotLab.create_network(name: "team", run_config: shared) { ... }
    robot = RobotLab.build(name: "bot", run_config: shared, temperature: 0.9)

  Example environment variable overrides:
    ROBOT_LAB_RUBY_LLM__MODEL=gpt-4
    ROBOT_LAB_RUBY_LLM__REQUEST_TIMEOUT=180
    ROBOT_LAB_RUBY_LLM__ANTHROPIC_API_KEY=sk-ant-...

  Try running with different environments:
    ROBOT_LAB_ENV=test ruby examples/08_llm_config.rb
    ROBOT_LAB_ENV=production ruby examples/08_llm_config.rb
  #{"=" * 70}
FOOTER
