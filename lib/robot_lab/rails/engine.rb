# frozen_string_literal: true

module RobotLab
  module Rails
    # Rails Engine for RobotLab integration
    #
    # Provides automatic loading of RobotLab components and
    # integration with Rails applications.
    #
    class Engine < ::Rails::Engine
      isolate_namespace RobotLab

      initializer "robot_lab.configure" do |app|
        # Load configuration from Rails config
        app.config.robot_lab ||= ActiveSupport::OrderedOptions.new
      end

      initializer "robot_lab.add_autoload_paths", before: :set_autoload_paths do |app|
        app.config.autoload_paths << root.join("app", "robots")
        app.config.autoload_paths << root.join("app", "tools")
      end

      config.generators do |g|
        g.test_framework :minitest, fixture: false
        g.fixture_replacement nil
      end
    end
  end
end
