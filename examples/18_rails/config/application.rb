# frozen_string_literal: true

require "bundler/setup"

require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"

Bundler.require(*Rails.groups)

module RobotLabDemo
  class Application < Rails::Application
    config.load_defaults 8.0

    config.eager_load = false
    config.consider_all_requests_local = true
    config.secret_key_base = "demo-secret-key-for-development-only"

    # Use async adapter for jobs — no external process needed
    config.active_job.queue_adapter = :async

    # Autoload app/robots and app/tools
    config.autoload_paths << root.join("app", "robots")
    config.autoload_paths << root.join("app", "tools")

    # Disable unused middleware
    config.api_only = false
    config.hosts.clear
  end
end
