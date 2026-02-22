# frozen_string_literal: true

class TimeTool < RobotLab::Tool
  description "Get the current date and time"

  def execute
    Time.current.strftime("%Y-%m-%d %H:%M:%S %Z")
  end
end
