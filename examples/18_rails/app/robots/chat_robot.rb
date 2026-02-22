# frozen_string_literal: true

class ChatRobot
  SYSTEM_PROMPT = "You are a friendly assistant. Be concise."

  def self.build(**options)
    RobotLab.build(
      name: "chat",
      system_prompt: SYSTEM_PROMPT,
      local_tools: [TimeTool],
      **options
    )
  end
end
