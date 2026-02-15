#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 12: Message Bus — Converging on a Funny Robot Joke
#
# Alice tasks Bob to tell a robot joke. Alice uses her LLM to
# evaluate each joke. If she's not impressed she asks Bob to try
# again. The loop continues until Alice approves or MAX_ATTEMPTS.
#
# Usage:
#   bundle exec ruby examples/12_message_bus.rb

ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

RubyLLM.configure { |c| c.logger = Logger.new(File::NULL) }

MAX_ATTEMPTS = 5

class Comedian < RobotLab::Robot
  TEMP_START = 0.2
  TEMP_STEP  = 0.2

  def initialize(bus:)
    super(name: "bob", template: :comedian, bus: bus, temperature: TEMP_START)
    @attempts = 0
    on_message do |message|
      @attempts += 1
      temp = [TEMP_START + TEMP_STEP * (@attempts - 1), 1.0].min
      with_temperature(temp)
      joke = run(message.content.to_s).last_text_content.strip
      puts "  Bob  [##{@attempts}, t=#{"%.1f" % temp}]: #{joke}"
      reply(message, joke)
    end
  end

  attr_reader :attempts
end

class ComedyCritic < RobotLab::Robot
  def initialize(bus:)
    super(name: "alice", template: :comedy_critic, bus: bus)
    @accepted = false
    @rounds   = 0
    on_message do |message|
      @rounds += 1
      verdict = run("Evaluate this joke:\n\n#{message.content}").last_text_content.strip
      puts "  Alice: #{verdict}"
      puts
      @accepted = verdict.start_with?("FUNNY")
      send_message(to: :bob, content: "Not funny enough. Try again.") unless @accepted || @rounds >= MAX_ATTEMPTS
    end
  end

  attr_reader :accepted
end

bus   = TypedBus::MessageBus.new
bob   = Comedian.new(bus: bus)
alice = ComedyCritic.new(bus: bus)

puts "=" * 60
puts "Example 12: Tell Me a Funny Robot Joke"
puts "=" * 60
puts

puts "Alice: Tell me a funny robot joke."
puts
alice.send_message(to: :bob, content: "Tell me a funny robot joke.")

puts "-" * 60
puts "Attempts: #{bob.attempts} / #{MAX_ATTEMPTS}"
puts "Accepted: #{alice.accepted}"
