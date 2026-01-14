# frozen_string_literal: true

require_relative "lib/robot_lab/version"

Gem::Specification.new do |spec|
  spec.name = "robot_lab"
  spec.version = RobotLab::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dewayne@vanhoozer.me"]

  spec.summary = "Multi-robot orchestration framework for LLM-powered workflows"
  spec.description = <<~DESC
    RobotLab is a Ruby framework for building and orchestrating multi-robot LLM workflows.
    Built on ruby_llm, it provides robots with tools and lifecycle hooks, networks for
    coordinating multiple robots with intelligent routing, MCP (Model Context Protocol)
    integration for external tool servers, streaming support for real-time updates, and
    seamless Rails integration with generators and ActiveRecord-backed conversation history.
  DESC
  spec.homepage = "https://github.com/MadBomber/robot_lab"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/MadBomber/robot_lab"
  spec.metadata["changelog_uri"] = "https://github.com/MadBomber/robot_lab/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://github.com/MadBomber/robot_lab#readme"
  spec.metadata["bug_tracker_uri"] = "https://github.com/MadBomber/robot_lab/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core dependencies
  spec.add_dependency "zeitwerk", "~> 2.6"
  spec.add_dependency "ruby_llm", "~> 1.0"
  spec.add_dependency "ruby_llm-mcp"
  spec.add_dependency "ruby_llm-template"
  spec.add_dependency "ruby_llm-schema"
  spec.add_dependency "ruby_llm-semantic_cache"
  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "simple_flow"
  spec.add_dependency "state_machines"
  spec.add_dependency "state_machines-activemodel"
  spec.add_dependency "state_machines-activerecord"

  # Optional MCP transport dependencies (loaded on demand)
  spec.add_dependency "async-http", "~> 0.60"
  spec.add_dependency "async-websocket", "~> 0.30"

  # Rails integration (optional - loaded when Rails is present)
  spec.add_dependency "railties", ">= 7.0"
  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
end
