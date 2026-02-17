# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    # Inter-robot communication via TypedBus.
    #
    # Expects the including class to provide:
    #   @bus, @message_counter, @outbox, @message_handler,
    #   @bus_subscriber_id, @bus_processing, @bus_queue, @name
    #   and the `run` instance method
    #
    # == Processing Guard
    #
    # TypedBus delivers messages in concurrent Async fibers. When a robot's
    # +run()+ yields during HTTP I/O, the Async scheduler can switch to
    # another fiber delivering a new bus message to the same robot. This
    # would interleave user messages between +tool_use+ / +tool_result+
    # pairs in +@chat+, corrupting Anthropic API message ordering.
    #
    # The processing guard serializes delivery handling: deliveries that
    # arrive while the robot is already processing are queued and drained
    # sequentially after the current one completes.
    #
    module BusMessaging
      # Send a message to another robot via the bus.
      #
      # @param to [String, Symbol] target robot's channel name
      # @param content [String, Hash] message payload
      # @return [RobotMessage] the sent message
      # @raise [BusError] if no bus is configured
      def send_message(to:, content:)
        raise BusError, "No bus configured on robot '#{@name}'" unless @bus

        @message_counter += 1
        message = RobotMessage.build(id: @message_counter, from: @name, content: content)
        @outbox[message.key] = { message: message, status: :sent, replies: [] }
        publish_to_bus(to.to_sym, message)
        message
      end


      # Send a reply to a specific message via the bus.
      #
      # @param to [String, Symbol] target robot's channel name
      # @param content [String, Hash] reply payload
      # @param in_reply_to [String] composite key of the message being replied to
      # @return [RobotMessage] the reply message
      # @raise [BusError] if no bus is configured
      def send_reply(to:, content:, in_reply_to:)
        raise BusError, "No bus configured on robot '#{@name}'" unless @bus

        @message_counter += 1
        reply = RobotMessage.build(id: @message_counter, from: @name, content: content, in_reply_to: in_reply_to)
        publish_to_bus(to.to_sym, reply)
        reply
      end


      # Register a custom handler for incoming bus messages.
      #
      # Block arity controls delivery handling:
      # - 1 argument `|message|`: auto-acks before calling, auto-nacks on exception
      # - 2 arguments `|delivery, message|`: manual mode, you call ack!/nack!
      #
      # @yield [message] or [delivery, message]
      # @return [self]
      def on_message(&block)
        @message_handler = block
        self
      end


      # Spawn a new robot on a shared bus.
      #
      # Creates a new Robot instance that shares this robot's bus,
      # allowing it to immediately send and receive messages with
      # all other robots on the bus. If no bus exists yet, one is
      # created automatically and the parent robot is connected to it.
      #
      # @param name [String] unique name for the new robot
      # @param system_prompt [String, nil] inline system prompt
      # @param template [Symbol, nil] prompt_manager template
      # @param local_tools [Array] tools for the new robot
      # @param options [Hash] additional options passed to RobotLab.build
      # @return [Robot] the newly created robot
      #
      # @example Spawn from a bus-less robot (bus and name created automatically)
      #   bot  = RobotLab.build
      #   bot2 = bot.spawn(system_prompt: "You are helpful.")
      #
      # @example Spawn a specialist from a message handler
      #   on_message do |message|
      #     specialist = spawn(
      #       name: "fact_checker",
      #       system_prompt: "You verify factual claims. Be concise."
      #     )
      #     specialist.send_message(to: name.to_sym, content: specialist.run(message.content).last_text_content)
      #   end
      #
      def spawn(name: "robot", system_prompt: nil, template: nil, local_tools: [], **options)
        ensure_bus

        RobotLab.build(
          name: name,
          system_prompt: system_prompt,
          template: template,
          local_tools: local_tools,
          bus: @bus,
          **options
        )
      end


      # Connect this robot to a message bus.
      #
      # If a bus is provided, the robot joins it. If no bus is provided
      # and the robot doesn't already have one, a new bus is created.
      # No-op if the robot is already on the given bus.
      #
      # @param bus [TypedBus::MessageBus, nil] bus to join (creates one if nil)
      # @return [self]
      #
      # @example Join an existing bus
      #   bot = RobotLab.build.with_bus(some_bus)
      #
      # @example Create a bus on demand
      #   bot = RobotLab.build.with_bus
      #
      def with_bus(bus = nil)
        return self if bus && @bus == bus

        teardown_bus_channel if @bus
        @bus = bus || @bus || TypedBus::MessageBus.new
        setup_bus_channel
        self
      end

      private

      # Create a bus if one doesn't exist and connect this robot to it
      def ensure_bus
        with_bus unless @bus
      end


      # Create a typed channel on the bus and subscribe to it
      def setup_bus_channel
        channel_name = @name.to_sym
        @bus.add_channel(channel_name, type: RobotMessage) unless @bus.channel?(channel_name)
        @bus_subscriber_id = @bus.subscribe(channel_name) { |delivery| handle_incoming_delivery(delivery) }
      end


      # Unsubscribe from the bus channel
      def teardown_bus_channel
        channel_name = @name.to_sym
        @bus.unsubscribe(channel_name, @bus_subscriber_id) if @bus_subscriber_id
        @bus_subscriber_id = nil
      end


      # Dispatch incoming bus delivery to handler.
      #
      # Uses a processing guard to serialize delivery handling. When
      # the robot is already processing a delivery (e.g., inside a
      # run() call that yields during HTTP I/O), new deliveries are
      # queued and drained sequentially after the current one completes.
      #
      # Auto-ack when the handler takes 1 arg (message only);
      # manual ack/nack when the handler takes 2 args (delivery, message).
      def handle_incoming_delivery(delivery)
        if @bus_processing
          @bus_queue << delivery
          return
        end

        process_delivery(delivery)
        drain_bus_queue
      end


      # Process a single delivery (called under the processing guard)
      def process_delivery(delivery)
        @bus_processing = true

        message = delivery.message

        # Correlate replies with outbox entries
        if message.reply? && @outbox.key?(message.in_reply_to)
          entry = @outbox[message.in_reply_to]
          entry[:status] = :replied
          entry[:replies] << message
        end

        if @message_handler
          if @message_handler.arity == 1
            delivery.ack!
            @message_handler.call(message)
          else
            @message_handler.call(delivery, message)
          end
        else
          handle_message_via_llm(delivery, message)
        end
      rescue => e
        delivery.nack! if delivery.pending?
        raise BusError, "Error handling bus message on robot '#{@name}': #{e.message}"
      ensure
        @bus_processing = false
      end


      # Drain queued deliveries sequentially
      def drain_bus_queue
        while (queued = @bus_queue.shift)
          process_delivery(queued)
        end
      end


      # Default handler: interpret message via LLM and reply
      def handle_message_via_llm(delivery, message)
        delivery.ack!
        result = run(message.content.to_s)
        send_reply(to: message.from.to_sym, content: result.last_text_content, in_reply_to: message.key)
      end


      # Publish a RobotMessage to a bus channel
      def publish_to_bus(channel_name, message)
        if defined?(Async::Task) && Async::Task.current?
          @bus.publish(channel_name, message)
        else
          Async { @bus.publish(channel_name, message) }
        end
      end
    end
  end
end
