# frozen_string_literal: true

require "rails/generators"

module RobotLab
  module Generators
    # Generates a new RobotLab robot
    #
    # Usage:
    #   rails generate robot_lab:robot NAME [options]
    #
    # Examples:
    #   rails generate robot_lab:robot Support
    #   rails generate robot_lab:robot Billing --description="Handles billing queries"
    #
    class RobotGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :description, type: :string, default: nil,
                                 desc: "Robot description"
      class_option :routing, type: :boolean, default: false,
                             desc: "Generate a routing robot"
      class_option :tools, type: :array, default: [],
                           desc: "List of tools to include"

      # Creates the robot class file.
      #
      # @return [void]
      def create_robot_file
        if options[:routing]
          template "routing_robot.rb.tt", "app/robots/#{file_name}_robot.rb"
        else
          template "robot.rb.tt", "app/robots/#{file_name}_robot.rb"
        end
      end

      # Creates the robot test file.
      #
      # @return [void]
      def create_test_file
        template "robot_test.rb.tt", "test/robots/#{file_name}_robot_test.rb"
      end

      private

      def robot_description
        options[:description] || "A helpful #{class_name.titleize} robot"
      end

      def robot_tools
        options[:tools]
      end
    end
  end
end
