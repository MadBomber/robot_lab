# frozen_string_literal: true

module RobotLab
  # Tool that lets a robot ask the user a question via the terminal.
  #
  # The LLM decides when human input is needed and calls this tool
  # with a question. Supports open-ended text, multiple choice,
  # and default values for confirmation-style prompts.
  #
  # IO is sourced from the owning robot's +input+ / +output+ accessors,
  # falling back to +$stdin+ / +$stdout+.
  #
  # @example Open-ended question
  #   # LLM calls: ask_user(question: "What is your name?")
  #   # Terminal shows:
  #   #   [helper] What is your name?
  #   #   >
  #
  # @example Multiple choice
  #   # LLM calls: ask_user(question: "Pick a language:", choices: ["Ruby", "Python", "Go"])
  #   # Terminal shows:
  #   #   [helper] Pick a language:
  #   #     1. Ruby
  #   #     2. Python
  #   #     3. Go
  #   #   >
  #
  # @example With default
  #   # LLM calls: ask_user(question: "Continue?", default: "yes")
  #   # Terminal shows:
  #   #   [helper] Continue?
  #   #   > [yes]
  #
  class AskUser < Tool
    description "Ask the user a question and wait for their typed response"
    param :question, type: "string",  desc: "The question to ask the user"
    param :choices,  type: "array",   desc: "Optional list of choices to present", required: false
    param :default,  type: "string",  desc: "Default value if user presses Enter",  required: false

    def execute(question:, choices: nil, default: nil)
      out = output_io
      label = robot&.name || "Robot"

      out.puts "\n[#{label}] #{question}"

      if choices.is_a?(Array) && choices.any?
        choices.each_with_index { |c, i| out.puts "  #{i + 1}. #{c}" }
      end

      prompt = default ? "> [#{default}] " : "> "
      out.print prompt
      out.flush

      response = input_io.gets&.chomp || ""
      response = default if response.empty? && default

      if choices.is_a?(Array) && choices.any? && response.match?(/\A\d+\z/)
        idx = response.to_i - 1
        response = choices[idx] if idx >= 0 && idx < choices.size
      end

      response
    end

    private

    def input_io
      robot.respond_to?(:input) && robot.input ? robot.input : $stdin
    end

    def output_io
      robot.respond_to?(:output) && robot.output ? robot.output : $stdout
    end
  end
end
