# frozen_string_literal: true

# Factory for the chat robot. RobotLab::RailsIntegration::Job calls
# ChatRobot.build(on_content:, on_tool_call:) to wire Turbo streaming.
#
# The model is served locally by Ollama. Ollama models are absent from
# RubyLLM's registry, so provider: must accompany model: — that is what makes
# RubyLLM skip the registry lookup.
class ChatRobot
  SYSTEM_PROMPT = "You are a friendly assistant. Be concise."

  PROVIDER = ENV.fetch("ROBOT_LAB_PROVIDER", "ollama")
  MODEL    = ENV.fetch("ROBOT_LAB_MODEL", "qwen3.6:latest")

  def self.build(**options)
    RobotLab.build(
      name: "chat",
      provider: PROVIDER,
      model: MODEL,
      system_prompt: SYSTEM_PROMPT,
      local_tools: [TimeTool],
      **options
    )
  end
end
