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
    # enqueue deliveries into a shared BusPoller rather than dispatching
    # them straight to the handler. Despite the name, BusPoller runs no
    # background thread: `enqueue` processes the delivery inline in the
    # caller's own execution context (Async fiber or OS thread) when the
    # robot is idle, and otherwise queues it behind the delivery already
    # in flight and drains it once that one returns. A mutex therefore
    # serializes deliveries per robot, so a robot's run() calls never
    # interleave — but nothing makes progress while the calling fiber is
    # parked.
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

        # Counter + outbox are shared with the poller thread (reply correlation)
        # and with other senders; mutate them under the bus mutex. Publish (which
        # does I/O) stays outside the lock.
        message = @bus_mutex.synchronize do
          @message_counter += 1
          msg = RobotMessage.build(id: @message_counter, from: @name, content: content)
          @outbox[msg.key] = { message: msg, status: :sent, replies: [] }
          msg
        end
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

        reply = @bus_mutex.synchronize do
          @message_counter += 1
          RobotMessage.build(id: @message_counter, from: @name, content: content, in_reply_to: in_reply_to)
        end
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

      # Automatically respond to inbound (non-reply) bus tasks: run +responder+ to
      # produce a reply, and send it back to the sender. This is the symmetric
      # counterpart to how a Cyborg answers its human — one call makes any bus
      # member a first-class responder instead of hand-wiring {#on_message}.
      #
      # The responder runs inline in the caller's execution context (BusPoller has
      # no drain thread), and deliveries to this member are serialized, so a long
      # turn blocks both the sender and the next inbound message.
      #
      # @param auto_reply [Boolean] send the responder's result back to the sender
      # @yield [message] the inbound task; return the reply content (nil => no reply)
      # @return [self]
      def respond_to_tasks(auto_reply: true, &responder)
        on_message do |message|
          next if message.reply?

          reply = responder.call(message)
          send_reply(to: message.from, content: reply, in_reply_to: message.key) if auto_reply && reply
        end
        self
      end

      # Serve inbound bus tasks by running each through this member's #run and
      # replying with the result — the one-call way to make a Robot cooperate on
      # the bus the way a Cyborg already does out of the box.
      #
      # @param auto_reply [Boolean]
      # @return [self]
      def serve(auto_reply: true)
        respond_to_tasks(auto_reply: auto_reply) { |message| run(bus_task_content(message)).reply }
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
      def spawn(name: "robot", system_prompt: nil, template: nil, local_tools: [], **)
        ensure_bus

        RobotLab.build(
          name: name,
          system_prompt: system_prompt,
          template: template,
          local_tools: local_tools,
          bus: @bus,
          **inherited_llm_settings,
          **
        )
      end

      # Model/provider a spawned robot inherits from its parent so a specialist
      # runs on the SAME LLM as the robot that spawned it (e.g. a local Ollama
      # model) instead of falling back to the global default. Caller-supplied
      # opts override these.
      #
      # @return [Hash]
      def inherited_llm_settings
        settings = {}
        settings[:model]    = model    if model
        settings[:provider] = provider if provider
        settings
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
      # Drops any private poller this robot auto-created, then adopts
      # the network's shared poller for the given group. Called by
      # Network#task; groups are informational labels only.
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

      # Flatten a task message's content to text for #run.
      def bus_task_content(message)
        content = message.content
        content.is_a?(Hash) ? content.map { |k, v| "#{k}: #{v}" }.join("\n") : content.to_s
      end

      # Enqueue a delivery to the robot's assigned poller.
      def enqueue_delivery(delivery)
        @bus_poller.enqueue(robot: self, delivery: delivery, group: @bus_poller_group)
      end

      # Process a single delivery (called by BusPoller during its inline drain).
      def process_delivery(delivery)
        message = delivery.message
        correlate_reply(message) if message.reply?

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

      # Mark the sender's outbox entry replied. Shared with senders on other
      # threads, so guard with the bus mutex.
      def correlate_reply(message)
        @bus_mutex.synchronize do
          entry = @outbox[message.in_reply_to] or return

          entry[:status] = :replied
          entry[:replies] << message
        end
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
