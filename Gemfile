# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in robot_lab.gemspec
gemspec

group :development, :test do
  gem 'ractor_queue'
  gem 'ractor-wrapper'
  gem 'aigcm'
  gem "robot_lab-document_store", path: "../robot_lab-document_store"
  gem "robot_lab-ractor", path: "../robot_lab-ractor"
  gem "robot_lab-durable", path: "../robot_lab-durable"
  gem "robot_lab-rails", path: "../robot_lab-rails"
  gem 'amazing_print'
  gem 'classifier', '~> 2.3'
  gem 'debug_me'
  gem 'hashdiff'
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
  gem "activesupport", ">= 7.0"
  gem "activerecord", ">= 7.0"
  gem "railties", ">= 7.0"
  gem "state_machines"
  gem "state_machines-activemodel"
  gem "state_machines-activerecord"
  gem "simplecov", require: false
end
