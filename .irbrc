begin
  load File.expand_path('lib/robot_lab.rb', __dir__)
rescue LoadError => e
  warn "[robot_lab] #{e.message}"
  warn "[robot_lab] Run `bundle exec irb` to load RobotLab"
end
