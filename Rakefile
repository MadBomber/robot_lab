# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.verbose = true
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
