# frozen_string_literal: true

# Base writer that runs LLM and stores its draft in shared memory.
# Used by mac_writer and win_writer directly; LinuxWriter extends this.
#
# NOTE: We bypass extract_run_context for network_memory access because
# its delete() pattern mutates the shared run_params hash — in parallel
# pipeline steps, only the first step to run would get the memory object.
# Instead, each robot holds a direct reference via shared_memory=.
class OsWriter < RobotLab::Robot
  attr_accessor :shared_memory

  def initialize(memory_key:, **opts)
    super(**opts)
    @memory_key = memory_key
  end

  def call(result)
    message = extract_message(result)

    robot_result = run(message, network_memory: @shared_memory)

    if @shared_memory
      draft = robot_result.reply.to_s
      @shared_memory.current_writer = @name
      @shared_memory.set(@memory_key, draft)

      path = File.join(OUTPUT_DIR, "#{@memory_key}.md")
      File.write(path, "# #{@name} Draft\n\n#{draft}\n")
      puts "  [#{@name}] Draft written to memory[:#{@memory_key}] and #{path}"
    end

    result.with_context(@name.to_sym, robot_result).continue(robot_result)
  end

  private

  def extract_message(result)
    case result.value
    when Hash then result.value[:message]
    when RobotLab::RobotResult then result.value.reply
    when String then result.value
    else result.value.to_s
    end
  end
end
