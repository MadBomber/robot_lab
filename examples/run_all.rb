#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs every executable NN_*.rb demo in this directory serially, printing a
# banner to STDOUT before each one so the outputs are easy to tell apart.

module RunAll
  module_function

  # Executable NN_*.rb demos in +dir+, in numeric order.
  def demo_files(dir = __dir__)
    Dir.glob(File.join(dir, "[0-9][0-9]_*.rb"))
       .select { File.executable?(it) }
       .sort
  end

  def banner(path)
    bar = "=" * 70
    <<~BANNER

      #{bar}
      ==  #{File.basename(path)}
      #{bar}
    BANNER
  end

  # Absolute path to the gem root's Gemfile, honoring the prod/dev choice
  # (Gemfile vs Gemfile.local) carried by BUNDLE_GEMFILE. The inherited value
  # is relative, so left alone it would resolve against the demo's cwd.
  def bundle_gemfile(dir = __dir__)
    name = File.basename(ENV.fetch("BUNDLE_GEMFILE", "Gemfile"))
    File.expand_path("../#{name}", dir)
  end

  # Runs one demo with this Ruby interpreter; returns true on success.
  def run_demo(path)
    system({ "BUNDLE_GEMFILE" => bundle_gemfile }, RbConfig.ruby, path)
  end

  # True when the last demo was killed by Ctrl-C (SIGINT).
  def interrupted?(status = Process.last_status)
    !status.nil? && status.signaled? && status.termsig == Signal.list["INT"]
  end

  # Ctrl-C reaches the whole foreground process group. A proc trap (unlike
  # "IGNORE") is reset to DEFAULT in the exec'd child, so the demo dies while
  # this runner survives and moves on to the next one.
  def run(files = demo_files)
    previous = trap("INT") { nil }
    files.each do |file|
      puts banner(file)
      run_demo(file)
      puts "--  #{File.basename(file)} interrupted (Ctrl-C); moving on" if interrupted?
    end
  ensure
    trap("INT", previous || "DEFAULT")
  end
end

RunAll.run if $PROGRAM_NAME == __FILE__
