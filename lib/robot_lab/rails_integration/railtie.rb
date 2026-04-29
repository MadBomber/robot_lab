# frozen_string_literal: true

module RobotLab
  module RailsIntegration
    # Railtie for RobotLab Rails integration
    #
    # Provides configuration hooks and initialization for
    # Rails applications using RobotLab.
    #
    class Railtie < ::Rails::Railtie
      config.robot_lab = ActiveSupport::OrderedOptions.new

      initializer "robot_lab.configuration" do |app|
        RobotLab.configure do |config|
          # Apply Rails-specific configuration
          rails_config = app.config.robot_lab

          config.default_model = rails_config.default_model if rails_config.default_model
          config.default_provider = rails_config.default_provider if rails_config.default_provider
          config.logger = ::Rails.logger
        end
      end

      initializer "robot_lab.active_record" do
        ActiveSupport.on_load(:active_record) do
          # Extend ActiveRecord with RobotLab concerns if needed
        end
      end

      rake_tasks do
        # Load RobotLab rake tasks
        path = File.expand_path("../tasks", __dir__)
        Dir.glob("#{path}/**/*.rake").each { |f| load f }
      end

      # TODO: Add fiber isolation warning once Solid Queue fiber mode lands in a
      # mainline release. PR rails/solid_queue#728 (branch crmne/solid_queue
      # async-worker-execution-mode) introduces the `fibers:` worker key but has
      # not yet been merged or released. When a released version is detectable,
      # add an initializer here that warns when:
      #   defined?(SolidQueue) &&
      #   app.config.active_support.isolation_level != :fiber

      generators do
        require "generators/robot_lab/install_generator"
        require "generators/robot_lab/robot_generator"
        require "generators/robot_lab/job_generator"
      end
    end
  end
end
