# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RobotLab
  module Generators
    # Installs RobotLab into a Rails application
    #
    # Usage:
    #   rails generate robot_lab:install
    #
    class InstallGenerator < ::Rails::Generators::Base
      include ::Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :skip_migration, type: :boolean, default: false,
                                    desc: "Skip database migration generation"

      # Returns the next migration number for ActiveRecord migrations.
      #
      # @param dirname [String] the migrations directory
      # @return [String] the next migration number
      def self.next_migration_number(dirname)
        ::ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      # Creates the RobotLab initializer file.
      #
      # @return [void]
      def create_initializer
        template "initializer.rb.tt", "config/initializers/robot_lab.rb"
      end

      # Creates the database migration for RobotLab tables.
      #
      # @return [void]
      def create_migration
        return if options[:skip_migration]

        migration_template "migration.rb.tt", "db/migrate/create_robot_lab_tables.rb"
      end

      # Creates the ActiveRecord model files.
      #
      # @return [void]
      def create_models
        return if options[:skip_migration]

        template "thread_model.rb.tt", "app/models/robot_lab_thread.rb"
        template "result_model.rb.tt", "app/models/robot_lab_result.rb"
      end

      # Creates the robots and tools directories.
      #
      # @return [void]
      def create_directories
        empty_directory "app/robots"
        empty_directory "app/tools"
      end

      # Displays post-installation instructions.
      #
      # @return [void]
      def display_post_install
        say ""
        say "RobotLab installed successfully!", :green
        say ""
        say "Next steps:"
        say "  1. Run migrations: rails db:migrate"
        say "  2. Configure your LLM API keys in config/initializers/robot_lab.rb"
        say "  3. Generate your first robot: rails g robot_lab:robot MyRobot"
        say ""
      end
    end
  end
end
