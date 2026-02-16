begin
  load File.expand_path('lib/robot_lab.rb', __dir__)
rescue LoadError => e
  $stderr.puts "[robot_lab] #{e.message}"
  $stderr.puts "[robot_lab] Run `bundle exec irb` to load RobotLab"
end
