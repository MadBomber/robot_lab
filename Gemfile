# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in robot_lab.gemspec
gemspec

group :development, :test do
  gem 'aigcm'
  gem 'debug_me'
  gem "rake"
  gem "minitest"
  gem "minitest-reporters"
  gem "webmock"
  gem "vcr"
  gem "rubocop"
  gem "debug"
end

group :test do
  gem "sqlite3"
  gem "activerecord", ">= 7.0"
  gem "state_machines-activerecord"
  gem "simplecov", require: false
end
