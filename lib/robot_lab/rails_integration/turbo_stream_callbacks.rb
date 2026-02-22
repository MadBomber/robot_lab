# frozen_string_literal: true

module RobotLab
  module RailsIntegration
    # Stateless utility module that builds callback Procs for Turbo Stream broadcasting.
    #
    # Safe to require even without turbo-rails installed — checks at call time
    # via `defined?(Turbo::StreamsChannel)`.
    #
    # @example Wire streaming in a background job
    #   stream_name = "robot_lab_thread_#{thread_id}"
    #   on_content = RobotLab::RailsIntegration::TurboStreamCallbacks.build_content_callback(
    #     stream_name: stream_name
    #   )
    #   robot = MyRobot.build(on_content: on_content)
    #   robot.run(message)
    #
    module TurboStreamCallbacks
      # Check whether Turbo Streams broadcasting is available at runtime.
      #
      # @return [Boolean]
      #
      def self.available?
        defined?(Turbo::StreamsChannel) ? true : false
      end

      # Build a Proc that broadcasts content chunks via Turbo Streams.
      #
      # The returned Proc receives a chunk object (e.g. RubyLLM::Chunk) and
      # broadcasts `chunk.content` as HTML-escaped text via `broadcast_append_to`.
      #
      # @param stream_name [String] the Turbo Stream channel name
      # @param target [String] the DOM target ID (default: "robot_response")
      # @return [Proc] a callback suitable for `on_content:`
      #
      def self.build_content_callback(stream_name:, target: "robot_response")
        ->(chunk) {
          content = chunk.respond_to?(:content) ? chunk.content : chunk.to_s
          return unless content && TurboStreamCallbacks.available?

          Turbo::StreamsChannel.broadcast_append_to(
            stream_name,
            target: target,
            html: ERB::Util.html_escape(content)
          )
        }
      end

      # Build a Proc that broadcasts tool call badges via Turbo Streams.
      #
      # The returned Proc receives a tool_call object and broadcasts
      # a badge showing the tool name.
      #
      # @param stream_name [String] the Turbo Stream channel name
      # @param target [String] the DOM target ID (default: "robot_tools")
      # @return [Proc] a callback suitable for `on_tool_call:`
      #
      def self.build_tool_call_callback(stream_name:, target: "robot_tools")
        ->(tool_call) {
          return unless TurboStreamCallbacks.available?

          name = tool_call.respond_to?(:name) ? tool_call.name : tool_call.to_s
          Turbo::StreamsChannel.broadcast_append_to(
            stream_name,
            target: target,
            html: "<span class=\"tool-badge\">Using: #{ERB::Util.html_escape(name)}</span>"
          )
        }
      end
    end
  end
end
