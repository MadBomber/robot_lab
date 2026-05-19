# frozen_string_literal: true

# Linux writer spawns distro specialists before writing its draft.
# Demonstrates the spawn() pattern for dynamic robot creation.
class LinuxWriter < OsWriter
  attr_reader :specialists

  def initialize(**opts)
    super(**opts)
    @specialists = []
  end

  def call(result)
    message = extract_message(result)

    # Spawn distro specialists and collect their analyses
    distro_analyses = spawn_distro_specialists(message)

    # Build an enriched prompt with specialist input
    enriched = <<~PROMPT
      #{message}

      Your team of distro specialists has provided the following analyses.
      Incorporate their insights into your advocacy piece:

      #{distro_analyses}
    PROMPT

    robot_result = run(enriched, network_memory: @shared_memory)

    if @shared_memory
      draft = robot_result.reply.to_s
      @shared_memory.current_writer = @name
      @shared_memory.set(@memory_key, draft)

      path = File.join(OUTPUT_DIR, "#{@memory_key}.md")
      File.write(path, "# #{@name} Draft\n\n#{draft}\n")
      puts "  [#{@name}] Draft written to memory[:#{@memory_key}] and #{path} (with #{@specialists.size} specialist inputs)"
    end

    result.with_context(@name.to_sym, robot_result).continue(robot_result)
  end

  private

  def spawn_distro_specialists(topic)
    distros = [
      { name: "ubuntu_specialist",  label: "Ubuntu/Debian",
        prompt: "You are a Ubuntu/Debian specialist for AI research. Focus on apt ecosystem, CUDA support, and wide hardware compatibility." },
      { name: "fedora_specialist",  label: "Fedora/RHEL",
        prompt: "You are a Fedora/RHEL specialist for AI research. Focus on cutting-edge kernels, SELinux security, and enterprise tooling." },
      { name: "freebsd_specialist", label: "FreeBSD",
        prompt: "You are a FreeBSD specialist for AI research. Focus on ZFS, jails, bhyve virtualization, and stability for long-running experiments." }
    ]

    analyses = []

    distros.each do |distro|
      puts "  [#{@name}] Spawning #{distro[:label]} specialist..."
      specialist = spawn(name: distro[:name], model: LLM[:default].model, system_prompt: distro[:prompt])
      @specialists << specialist

      analysis = specialist.run(
        "Briefly describe why #{distro[:label]} is a strong choice for a home AI research lab. 2-3 sentences."
      ).reply.strip

      puts "  [#{distro[:name]}] #{analysis[0..80]}..."
      analyses << "### #{distro[:label]}\n#{analysis}"

      # Write each specialist's analysis to shared memory
      if @shared_memory
        memory_key = distro[:name].to_sym
        @shared_memory.current_writer = distro[:name]
        @shared_memory.set(memory_key, analysis)
      end
    end

    analyses.join("\n\n")
  end
end
