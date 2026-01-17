# frozen_string_literal: true

require "bundler/gem_tasks"
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

desc "Check code style with RuboCop"
task :rubocop do
  sh "bundle exec rubocop"
end

desc "Auto-correct RuboCop offenses"
task :rubocop_fix do
  sh "bundle exec rubocop -a"
end

namespace :examples do
  desc "Run all examples"
  task :all do
    Dir.glob("examples/*.rb").sort.each do |example|
      puts "\n#{'=' * 60}"
      puts "Running: #{example}"
      puts '=' * 60
      ruby example
    end
  end

  desc "Run a specific example by number (e.g., rake examples:run[1])"
  task :run, [:num] do |_t, args|
    example = Dir.glob("examples/#{args[:num].rjust(2, '0')}_*.rb").first
    if example
      ruby example
    else
      puts "Example #{args[:num]} not found"
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

  namespace :yard do
    desc "Serve YARD documentation locally"
    task :serve do
      sh "yard server --reload"
    end
  end

  desc "Build MkDocs documentation"
  task :mkdocs do
    sh "mkdocs build"
  end

  namespace :mkdocs do
    desc "Serve MkDocs documentation locally"
    task :serve do
      sh "mkdocs serve"
    end
  end
end
