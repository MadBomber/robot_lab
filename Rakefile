# frozen_string_literal: true

# Quality gates (quality, rubocop_check, flog_check, flay_check,
# archspec_check, ...), doc *serving*, and the gem lifecycle (build, install,
# release) live in asgard — see .loki and the shared dev/*.loki files it
# imports. This Rakefile keeps the tasks asgard delegates to (tests,
# integration, examples, docs:build).

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.verbose = true
  # Load test_helper before any tests run to ensure SimpleCov starts first
  t.ruby_opts << "-rtest_helper"
end

task default: :test

desc "Run tests with verbose output"
task :test_verbose do
  ENV["TESTOPTS"] = "--verbose"
  Rake::Task[:test].invoke
end

desc "Run a single test file"
task :test_file, [:file] do |_t, args|
  ruby "test/#{args[:file]}"
end

desc "Run integration tests only"
Rake::TestTask.new(:integration) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/integration/**/*_test.rb"]
  t.verbose = true
  t.ruby_opts << "-rtest_helper"
end

namespace :examples do
  # Map of subdirectory-based demos to their entry point scripts
  SUBDIR_ENTRY_POINTS = {
    "14_rusty_circuit" => "open_mic.rb",
    "15_memory_network_and_bus" => "editorial_pipeline.rb",
    "16_writers_room" => "writers_room.rb",
    "27_incident_response" => "incident_response.rb"
  }.freeze

  # Subdirectory demos that are standalone apps (not run via `ruby`)
  STANDALONE_APPS = {
    "18_rails" => { setup: "bin/setup", run: "bin/dev" }
  }.freeze

  # Examples that require external services or user setup not guaranteed to be present
  EXTERNAL_SERVICE_EXAMPLES = {
    "33_stock_generator.rb" => "Redis server on localhost:6379",
    "33_stock_predictor.rb" => "Redis server on localhost:6379 + running 33_stock_generator",
    "34_agentskills.rb"     => "AgentSkills skill file at ~/.prompts/skills/code_reviewer/SKILL.md"
  }.freeze

  desc "Run all examples (excludes standalone apps like 18_rails)"
  task :all do
    failed = []

    # Single-file examples
    Dir.glob("examples/*.rb").each do |example|
      base = File.basename(example)

      if EXTERNAL_SERVICE_EXAMPLES.key?(base)
        puts "\n#{'=' * 60}"
        puts "Skipped: #{example} (requires #{EXTERNAL_SERVICE_EXAMPLES[base]})"
        puts '=' * 60
        next
      end

      puts "\n#{'=' * 60}"
      puts "Running: #{example}"
      puts '=' * 60
      begin
        ruby example
      rescue RuntimeError => e
        puts "FAILED: #{example} — #{e.message}"
        failed << example
      end
    end

    # Subdirectory-based demos
    SUBDIR_ENTRY_POINTS.each do |dir, entry|
      path = "examples/#{dir}/#{entry}"
      next unless File.exist?(path)

      puts "\n#{'=' * 60}"
      puts "Running: #{path}"
      puts '=' * 60
      begin
        ruby path
      rescue RuntimeError => e
        puts "FAILED: #{path} — #{e.message}"
        failed << path
      end
    end

    # Remind about standalone apps
    STANDALONE_APPS.each do |dir, commands|
      puts "\n#{'=' * 60}"
      puts "Skipped: examples/#{dir} (standalone app)"
      puts "  Setup: cd examples/#{dir} && #{commands[:setup]}"
      puts "  Run:   cd examples/#{dir} && #{commands[:run]}"
      puts '=' * 60
    end

    if failed.any?
      puts "\n#{'=' * 60}"
      puts "#{failed.size} example(s) failed:"
      failed.each { |f| puts "  #{f}" }
      puts '=' * 60
      exit 1
    end
  end

  desc "Run a specific example by number (e.g., rake examples:run[1])"
  task :run, [:num] do |_t, args|
    padded = args[:num].rjust(2, '0')

    # Try single-file example first
    example = Dir.glob("examples/#{padded}_*.rb").first
    if example
      ruby example
      next
    end

    # Try subdirectory-based demo
    dir = Dir.glob("examples/#{padded}_*/").first
    if dir
      dir_name = File.basename(dir)

      # Check if it's a standalone app
      if STANDALONE_APPS.key?(dir_name)
        commands = STANDALONE_APPS[dir_name]
        puts "Example #{args[:num]} is a standalone app (#{dir_name})."
        puts "  Setup: cd examples/#{dir_name} && #{commands[:setup]}"
        puts "  Run:   cd examples/#{dir_name} && #{commands[:run]}"
        next
      end

      entry = SUBDIR_ENTRY_POINTS[dir_name]
      if entry && File.exist?(File.join(dir, entry))
        ruby File.join(dir, entry)
      else
        puts "Example #{args[:num]} directory found (#{dir_name}) but no entry point configured"
      end
    else
      puts "Example #{args[:num]} not found"
    end
  end

  desc "Setup the Rails demo app (example 18)"
  task :rails_setup do
    Dir.chdir("examples/18_rails") do
      sh "bin/setup"
    end
  end

  desc "Start the Rails demo app (example 18)"
  task :rails do
    Dir.chdir("examples/18_rails") do
      sh "bin/dev"
    end
  end
end

namespace :docs do
  desc "Build all documentation (YARD and MkDocs)"
  task build: %i[yard mkdocs]

  desc "Clean generated documentation"
  task :clean do
    rm_rf "doc"
    rm_rf "site"
  end

  desc "Build YARD API documentation"
  task :yard do
    sh "yard doc"
  end

  desc "Build MkDocs documentation"
  task :mkdocs do
    sh "mkdocs build"
  end
end
