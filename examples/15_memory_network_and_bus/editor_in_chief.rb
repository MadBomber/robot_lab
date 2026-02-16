# frozen_string_literal: true

# Editor-in-chief lives outside the pipeline, communicates only via bus.
# Reviews articles and responds with APPROVED or REVISE: feedback.
class EditorInChief < RobotLab::Robot
  attr_reader :accepted, :rounds

  def initialize(**opts)
    super(**opts)
    @accepted = false
    @rounds   = 0

    on_message do |message|
      @rounds += 1
      verdict = run("Review this article:\n\n#{message.content}").last_text_content.strip
      @accepted = verdict.start_with?("APPROVED")
      puts "  Chief   [round #{@rounds}]: #{verdict[0..120]}"

      if !@accepted && @rounds < MAX_REVISIONS
        send_message(to: :editor, content: "Revise this article. Feedback: #{verdict}")
      end
    end
  end
end
