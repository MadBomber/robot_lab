# frozen_string_literal: true

# Reads all three drafts from memory, synthesizes a combined article.
# Also handles revision requests from the chief via bus.
#
# Like OsWriter, uses a direct shared_memory reference to avoid the
# extract_run_context mutation issue with parallel pipeline steps.
class OsEditor < RobotLab::Robot
  attr_accessor :shared_memory
  attr_reader :article

  def initialize(**opts)
    super(**opts)
    @article = nil
  end

  def call(result)
    # Read all three drafts from shared memory
    mac_draft     = @shared_memory&.get(:mac_draft)     || "No draft available."
    windows_draft = @shared_memory&.get(:windows_draft) || "No draft available."
    linux_draft   = @shared_memory&.get(:linux_draft)   || "No draft available."

    composite_prompt = <<~PROMPT
      Here are three advocacy drafts for different operating systems for home AI research labs.
      Synthesize them into a balanced article.

      ## macOS Advocacy
      #{mac_draft}

      ## Windows Advocacy
      #{windows_draft}

      ## Linux/BSD Advocacy
      #{linux_draft}
    PROMPT

    robot_result = run(composite_prompt, network_memory: @shared_memory)
    @article = robot_result.last_text_content.to_s

    path = File.join(OUTPUT_DIR, "combined_article.md")
    File.write(path, "# Combined Article (Editor Draft)\n\n#{@article}\n")
    puts "  [#{@name}] Combined article written to #{path}"

    result.with_context(@name.to_sym, robot_result).continue(robot_result)
  end
end
