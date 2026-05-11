# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    # Inter-robot communication via TypedBus.
    #
    # Expects the including class to provide:
    #   @bus, @bus_poller, @bus_poller_group, @message_counter,
    #   @outbox, @message_handler, @bus_subscriber_id, @name
    #   and the `run` instance method.
    #
    # == Delivery Serialization
    #
    # TypedBus delivers messages in concurrent Async fibers. Robots
    # enqueue deliveries into a BusPoller rather than handling them
    # inline. The BusPoller drains each group's queue sequentially on
    # a dedicated OS thread, so robot.run() calls never interleave.
    #
    # Owns:    @bus, @bus_poller, @private_bus_poller, @bus_poller_group, @bus_subscriber_id, @message_counter, @outbox, @message_handler
    # Reads:   @name
    # Contract: ivars initialized by initialize_runtime_state before first bus operation
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
      def with_bus(bus = nil)
        return self if bus && @bus == bus

        teardown_bus_channel if @bus
        @bus = bus || @bus || TypedBus::MessageBus.new
        setup_bus_channel
        self
      end

      # Assign a shared BusPoller from a Network.
      #
      # Stops any private poller this robot auto-created, then adopts
      # the network's shared poller for the given group.
      #
      # @param poller [BusPoller] the network's shared poller
      # @param group  [Symbol]    poller group for this robot (default: :default)
      # @return [void]
      #
      def assign_bus_poller(poller, group: :default)
        @private_bus_poller&.stop
        @private_bus_poller = nil
        @bus_poller       = poller
        @bus_poller_group = group
      end

      private

      # Create a bus if one doesn't exist and connect this robot to it
      def ensure_bus
        with_bus unless @bus
      end


      # Create a typed channel on the bus and subscribe to it.
      # Auto-creates a private BusPoller if none has been assigned.
      def setup_bus_channel
        unless @bus_poller
          @private_bus_poller = BusPoller.new.start
          @bus_poller         = @private_bus_poller
          @bus_poller_group   = :default
        end

        channel_name = @name.to_sym
        @bus.add_channel(channel_name, type: RobotMessage) unless @bus.channel?(channel_name)
        @bus_subscriber_id = @bus.subscribe(channel_name) { |delivery| enqueue_delivery(delivery) }
      end


      # Unsubscribe from the bus channel and stop the private poller if any.
      def teardown_bus_channel
        channel_name = @name.to_sym
        @bus.unsubscribe(channel_name, @bus_subscriber_id) if @bus_subscriber_id
        @bus_subscriber_id = nil

        @private_bus_poller&.stop
        @private_bus_poller = nil
        @bus_poller         = nil
        @bus_poller_group   = :default
      end


      # Enqueue a delivery to the robot's assigned poller.
      def enqueue_delivery(delivery)
        @bus_poller.enqueue(robot: self, delivery: delivery, group: @bus_poller_group)
      end


      # Process a single delivery (called by BusPoller drain thread).
      def process_delivery(delivery)
        message = delivery.message

        # Correlate replies with outbox entries
        if message.reply? && @outbox.key?(message.in_reply_to)
          entry = @outbox[message.in_reply_to]
          entry[:status] = :replied
          entry[:replies] << message
        end

        if @message_handler.arity == 1
          delivery.ack!
          @message_handler.call(message)
        else
          @message_handler.call(delivery, message)
        end
      rescue => e
        delivery.nack! if delivery.pending?
        raise BusError, "Error handling bus message on robot '#{@name}': #{e.message}"
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
