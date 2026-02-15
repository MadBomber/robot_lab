# frozen_string_literal: true

module RobotLab
  # LLM-powered robot built on RubyLLM::Agent
  #
  # Robot is a subclass of RubyLLM::Agent that adds:
  # - Template-based prompts via prompt_manager
  # - Shared memory (standalone or network)
  # - Tool integration with hierarchical MCP configuration
  # - SimpleFlow pipeline integration
  #
  # == Memory Behavior
  #
  # *Standalone*: Robot uses its own inherent memory (`robot.memory`).
  # *In a Network*: Robot uses the network's shared memory.
  #
  # @example Simple robot with template
  #   robot = Robot.new(name: "helper", template: :helper)
  #   result = robot.run("Hello!")
  #
  # @example Robot with inline system prompt
  #   robot = Robot.new(name: "bot", system_prompt: "You are helpful.")
  #   result = robot.run("What is 2+2?")
  #
  # @example Bare robot configured via chaining
  #   robot = Robot.new(name: "bot")
  #   robot.with_instructions("Be concise.").run("Hello")
  #
  # @example Robot with tools
  #   robot = Robot.new(
  #     name: "support",
  #     template: :support,
  #     local_tools: [OrderLookup, RefundProcessor]
  #   )
  #
  class Robot < RubyLLM::Agent
    # Front matter keys that map to chat configuration methods
    FRONT_MATTER_CONFIG_KEYS = %i[
      model temperature top_p top_k max_tokens
      presence_penalty frequency_penalty stop
    ].freeze

    # @!attribute [r] name
    #   @return [String] the unique identifier for the robot
    # @!attribute [r] description
    #   @return [String, nil] an optional description of the robot's purpose
    # @!attribute [r] template
    #   @return [Symbol, nil] the prompt_manager template for the robot's prompt
    # @!attribute [r] system_prompt
    #   @return [String, nil] inline system prompt (used alone or appended to template)
    # @!attribute [r] local_tools
    #   @return [Array] the locally defined tools for this robot
    # @!attribute [r] mcp_clients
    #   @return [Hash<String, MCP::Client>] connected MCP clients by server name
    # @!attribute [r] mcp_tools
    #   @return [Array<Tool>] tools discovered from MCP servers
    # @!attribute [r] memory
    #   @return [Memory] the robot's inherent memory (used when standalone, not in network)
    attr_reader :name, :description, :template, :system_prompt,
                :local_tools, :mcp_clients, :mcp_tools, :memory,
                :bus, :outbox

    # @!attribute [r] mcp_config
    #   @return [Symbol, Array] build-time MCP configuration (raw, unresolved)
    # @!attribute [r] tools_config
    #   @return [Symbol, Array] build-time tools configuration (raw, unresolved)
    attr_reader :mcp_config, :tools_config

    # Creates a new Robot instance.
    #
    # @param name [String] the unique identifier for the robot
    # @param template [Symbol, nil] the prompt_manager template
    # @param system_prompt [String, nil] inline system prompt
    # @param context [Hash, Proc] variables to pass to the template
    # @param description [String, nil] optional description
    # @param local_tools [Array] tools defined locally
    # @param model [String, nil] the LLM model to use
    # @param mcp_servers [Array] legacy parameter for MCP server configurations
    # @param mcp [Symbol, Array] hierarchical MCP config
    # @param tools [Symbol, Array] hierarchical tools config
    # @param on_tool_call [Proc, nil] callback invoked when a tool is called
    # @param on_tool_result [Proc, nil] callback invoked when a tool returns a result
    # @param enable_cache [Boolean] whether to enable semantic caching
    # @param bus [TypedBus::MessageBus, nil] optional message bus for inter-robot communication
    # @param temperature [Float, nil] controls randomness
    # @param top_p [Float, nil] nucleus sampling threshold
    # @param top_k [Integer, nil] top-k sampling
    # @param max_tokens [Integer, nil] maximum tokens in response
    # @param presence_penalty [Float, nil] penalize based on presence
    # @param frequency_penalty [Float, nil] penalize based on frequency
    # @param stop [String, Array, nil] stop sequences
    def initialize(
      name:,
      template: nil,
      system_prompt: nil,
      context: {},
      description: nil,
      local_tools: [],
      model: nil,
      mcp_servers: [],
      mcp: :none,
      tools: :none,
      on_tool_call: nil,
      on_tool_result: nil,
      enable_cache: true,
      bus: nil,
      temperature: nil,
      top_p: nil,
      top_k: nil,
      max_tokens: nil,
      presence_penalty: nil,
      frequency_penalty: nil,
      stop: nil
    )
      @name = name.to_s
      @template = template
      @system_prompt = system_prompt
      @build_context = context
      @description = description
      @local_tools = Array(local_tools)
      @on_tool_call = on_tool_call
      @on_tool_result = on_tool_result

      # Store raw config values for hierarchical resolution
      @mcp_config = mcp_servers.any? ? mcp_servers : mcp
      @tools_config = tools

      # MCP state
      @mcp_clients = {}
      @mcp_tools = []
      @mcp_initialized = false

      # Bus state (optional inter-robot communication)
      @bus = bus
      @message_counter = 0
      @outbox = {}
      @message_handler = nil

      # Inherent memory (used when standalone, not in a network)
      @memory = Memory.new(enable_cache: enable_cache)

      # Ensure config is loaded (triggers PM setup, RubyLLM config, etc.)
      config = RobotLab.config

      # Build chat kwargs for Agent's super
      resolved_model = model || config.ruby_llm.model
      chat_kwargs = { model: resolved_model }

      # Create the persistent chat via Agent's initialize
      super(chat: nil, **chat_kwargs)

      # Apply template first (includes front matter config like model, temperature)
      # then constructor params override — constructor is more specific than template.
      apply_template_to_chat(context) if @template
      @chat.with_instructions(@system_prompt) if @system_prompt

      # Constructor params override template front matter
      apply_chat_option(:with_temperature, temperature)
      apply_chat_option(:with_top_p, top_p)
      apply_chat_option(:with_top_k, top_k)
      apply_chat_option(:with_max_tokens, max_tokens)
      apply_chat_option(:with_presence_penalty, presence_penalty)
      apply_chat_option(:with_frequency_penalty, frequency_penalty)
      apply_chat_option(:with_stop, stop)

      # Apply callbacks
      @chat.on_tool_call(&@on_tool_call) if @on_tool_call
      @chat.on_tool_result(&@on_tool_result) if @on_tool_result

      # Set up bus channel if a bus was provided
      setup_bus_channel if @bus
    end


    # Returns the model identifier
    #
    # @return [String, nil] the LLM model ID string
    def model
      return nil unless @chat.respond_to?(:model)

      m = @chat.model
      m.respond_to?(:id) ? m.id : m.to_s
    end

    # Forward with_* methods to the persistent chat, returning self for chaining
    %i[
      with_model with_temperature with_top_p with_top_k with_max_tokens
      with_presence_penalty with_frequency_penalty with_stop
      with_instructions with_tool with_tools with_params
      with_headers with_schema with_context with_thinking
    ].each do |method|
      define_method(method) do |*args, **kwargs, &block|
        @chat.public_send(method, *args, **kwargs, &block)
        self
      end
    end

    # Apply a prompt_manager template to the robot's chat
    #
    # @param template_id [Symbol, String] the template identifier
    # @param context [Hash] variables to pass to the template
    # @return [self]
    def with_template(template_id, **context)
      @template = template_id.to_sym
      @build_context = context
      apply_template_to_chat(context)
      self
    end


    # Send a message and get a response, with Robot's extended capabilities
    #
    # @param message [String] the user message
    # @param network [NetworkRun, nil] network context (legacy)
    # @param network_memory [Memory, nil] shared network memory
    # @param memory [Memory, Hash, nil] runtime memory to merge
    # @param mcp [Symbol, Array, nil] runtime MCP override
    # @param tools [Symbol, Array, nil] runtime tools override
    # @return [RobotResult]
    def run(message = nil, network: nil, network_memory: nil, memory: nil, mcp: :none, tools: :none,
            **kwargs)
      # Determine which memory to use
      run_memory = resolve_active_memory(network: network, network_memory: network_memory)

      # Merge runtime memory if provided
      case memory
      when Memory
        run_memory = memory
      when Hash
        run_memory.merge!(memory)
      end

      # Set current_writer so memory notifications know who wrote the value
      previous_writer = run_memory.current_writer
      run_memory.current_writer = @name

      begin
        # Resolve hierarchical MCP and tools configuration
        resolved_mcp = resolve_mcp_hierarchy(mcp, network: network)
        resolved_tools = resolve_tools_hierarchy(tools, network: network)

        # Initialize or update MCP clients based on resolved config
        ensure_mcp_clients(resolved_mcp)

        # Apply filtered tools to the persistent chat
        filtered = filtered_tools(resolved_tools)
        @chat.with_tools(*filtered) if filtered.any?

        # Re-render template with run-time context merged into build-time context.
        # Template parameters (e.g. customer: null) may require values that are
        # only available at run time — the robot gathers them before rendering.
        run_context = kwargs.except(:with)
        rerender_template(run_context) if @template && run_context.any?

        # Delegate to Agent's ask (which calls @chat.ask)
        ask_kwargs = kwargs.slice(:with)
        response = ask(message, **ask_kwargs)

        build_result(response, run_memory)
      ensure
        run_memory.current_writer = previous_writer
      end
    end


    # Reconfigure the robot for a new context
    #
    # @param template [Symbol, nil] new template to apply
    # @param context [Hash, nil] new context for the template
    # @param system_prompt [String, nil] new system prompt
    # @param model [String, nil] new model
    # @param temperature [Float, nil] new temperature
    # @return [self]
    def update(template: nil, context: nil, system_prompt: nil, model: nil, temperature: nil, **kwargs)
      if template
        @template = template
        ctx = context || @build_context
        apply_template_to_chat(ctx)
      end

      @chat.with_instructions(system_prompt) if system_prompt
      @chat.with_model(model) if model
      apply_chat_option(:with_temperature, temperature)

      kwargs.each do |key, value|
        method = :"with_#{key}"
        @chat.public_send(method, value) if value && @chat.respond_to?(method)
      end

      self
    end


    # SimpleFlow step interface
    #
    # @param result [SimpleFlow::Result] incoming result from previous step
    # @return [SimpleFlow::Result] result with robot output
    def call(result)
      run_context = extract_run_context(result)

      # Extract the message from run context
      message = run_context.delete(:message)

      robot_result = run(message, **run_context)

      result
        .with_context(@name.to_sym, robot_result)
        .continue(robot_result)
    end


    # Reset the robot's inherent memory
    #
    # @return [self]
    def reset_memory
      @memory.reset
      self
    end


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


    # Convenience method to reply to a RobotMessage.
    #
    # @param message [RobotMessage] the message to reply to
    # @param content [String, Hash] reply payload
    # @return [RobotMessage] the reply message
    def reply(message, content)
      send_reply(to: message.from.to_sym, content: content, in_reply_to: message.key)
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


    # Disconnect all MCP clients and bus channel.
    #
    # @return [self]
    def disconnect
      @mcp_clients.each_value(&:disconnect)
      teardown_bus_channel if @bus
      self
    end


    # Converts the robot to a hash representation
    #
    # @return [Hash]
    def to_h
      {
        name: name,
        description: description,
        template: template,
        system_prompt: system_prompt,
        local_tools: local_tools.map { |t| t.respond_to?(:name) ? t.name : t.to_s },
        mcp_tools: mcp_tools.map(&:name),
        mcp_config: @mcp_config,
        tools_config: @tools_config,
        mcp_servers: @mcp_clients.keys,
        model: model,
        bus: @bus ? true : nil
      }.compact
    end

    private

    # Apply a chat option if the value is non-nil
    def apply_chat_option(method, value)
      @chat.public_send(method, value) if value
    end


    # Apply a prompt_manager template to the persistent chat.
    # If required parameters are missing, applies front matter config but
    # defers rendering until run time when all values are available.
    def apply_template_to_chat(context)
      parsed = PM.parse(@template)

      # Extract and apply front matter config to the chat
      apply_front_matter_config(parsed.metadata)

      # Resolve context (could be a Proc)
      resolved_ctx = resolve_context(context, network: nil)

      # Render the template body with context
      begin
        rendered = parsed.to_s(**resolved_ctx)
        @chat.with_instructions(rendered)
      rescue ArgumentError => e
        raise unless e.message.start_with?("Missing required parameters:")

        # Required parameters not yet available; template will be
        # fully rendered at run time via rerender_template.
      end
    end


    # Re-render the template with run-time context merged into build-time context.
    # prompt_manager parameters may be required (null) and only available at run time.
    def rerender_template(run_context)
      merged = (@build_context || {}).merge(run_context)
      parsed = PM.parse(@template)
      resolved_ctx = resolve_context(merged, network: nil)
      rendered = parsed.to_s(**resolved_ctx)
      @chat.with_instructions(rendered)
    end


    # Extract whitelisted config from front matter and apply to chat
    def apply_front_matter_config(metadata)
      FRONT_MATTER_CONFIG_KEYS.each do |key|
        value = metadata.respond_to?(key) ? metadata.send(key) : nil
        next unless value

        method = :"with_#{key}"
        @chat.public_send(method, value) if @chat.respond_to?(method)
      end

      # Handle model specially (may need with_model)
      return unless metadata.respond_to?(:model) && metadata.model

      @chat.with_model(metadata.model)

    end


    # Determine which memory to use
    def resolve_active_memory(network: nil, network_memory: nil)
      network_memory || network&.memory || @memory
    end


    # Extract run context from SimpleFlow::Result
    def extract_run_context(result)
      run_params = result.context[:run_params] || {}

      # Extract robot-specific params
      mcp = run_params.delete(:mcp) || :none
      tools = run_params.delete(:tools) || :none
      memory = run_params.delete(:memory)
      network_memory = run_params.delete(:network_memory)

      # Build base context from remaining run params
      base = run_params.dup

      # Merge current value into context
      merged = case result.value
               when Hash
                 base.merge(result.value.transform_keys(&:to_sym))
               when RobotResult
                 base.merge(message: result.value.last_text_content)
               when String
                 base.merge(message: result.value)
               else
                 base.merge(message: result.value.to_s)
               end

      # Add back the special params
      merged[:mcp] = mcp
      merged[:tools] = tools
      merged[:memory] = memory if memory
      merged[:network_memory] = network_memory if network_memory

      merged
    end


    def resolve_context(context, network:)
      case context
      when Proc then context.call(network: network)
      when Hash then context
      else {}
      end
    end


    def build_result(response, _memory)
      output = if response.respond_to?(:content) && response.content
                 [TextMessage.new(role: 'assistant', content: response.content)]
               else
                 []
               end

      tool_calls = response.respond_to?(:tool_calls) ? (response.tool_calls || []) : []

      RobotResult.new(
        robot_name: @name,
        output: output,
        tool_calls: normalize_tool_calls(tool_calls),
        stop_reason: response.respond_to?(:stop_reason) ? response.stop_reason : nil
      )
    end


    def normalize_tool_calls(tool_calls)
      return [] unless tool_calls

      tool_calls.map do |tc|
        if tc.is_a?(Hash)
          ToolResultMessage.new(
            tool: tc,
            content: tc[:result] || tc['result']
          )
        else
          tc
        end
      end
    end


    # Resolve MCP hierarchy: runtime -> robot build -> network -> config
    def resolve_mcp_hierarchy(runtime_value, network:)
      parent_value = network&.network&.mcp || RobotLab.config.mcp
      build_resolved = ToolConfig.resolve_mcp(@mcp_config, parent_value: parent_value)
      ToolConfig.resolve_mcp(runtime_value, parent_value: build_resolved)
    end


    # Resolve tools hierarchy: runtime -> robot build -> network -> config
    def resolve_tools_hierarchy(runtime_value, network:)
      parent_value = network&.network&.tools || RobotLab.config.tools
      build_resolved = ToolConfig.resolve_tools(@tools_config, parent_value: parent_value)
      ToolConfig.resolve_tools(runtime_value, parent_value: build_resolved)
    end


    # Ensure MCP clients are initialized for the given server configs
    def ensure_mcp_clients(mcp_servers)
      return if mcp_servers.empty?

      needed_servers = mcp_servers.map { |s| s.is_a?(Hash) ? s[:name] : s.to_s }.compact
      return if @mcp_initialized && (@mcp_clients.keys.sort == needed_servers.sort)

      disconnect if @mcp_initialized

      @mcp_clients = {}
      @mcp_tools = []

      mcp_servers.each do |server_config|
        init_mcp_client(server_config)
      end

      @mcp_initialized = true
    end


    def init_mcp_client(server_config)
      client = MCP::Client.new(server_config)
      client.connect

      if client.connected?
        server_name = client.server.name
        @mcp_clients[server_name] = client
        discover_mcp_tools(client, server_name)
      else
        RobotLab.config.logger.warn(
          "Robot '#{@name}' failed to connect to MCP server: #{server_config[:name] || server_config}"
        )
      end
    end


    def discover_mcp_tools(client, server_name)
      tools = client.list_tools

      tools.each do |tool_def|
        tool_name = tool_def[:name]
        mcp_client = client

        tool = Tool.new(
          name: tool_name,
          description: tool_def[:description],
          parameters: tool_def[:inputSchema],
          mcp: server_name,
          handler: ->(input, **_opts) { mcp_client.call_tool(tool_name, input) }
        )

        @mcp_tools << tool
      end

      RobotLab.config.logger.info(
        "Robot '#{@name}' discovered #{tools.size} tools from MCP server '#{server_name}'"
      )
    end


    def all_tools
      @local_tools + @mcp_tools
    end


    def filtered_tools(allowed_names)
      available = all_tools
      return available if allowed_names.empty?

      ToolConfig.filter_tools(available, allowed_names: allowed_names)
    end


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
    # Auto-ack when the handler takes 1 arg (message only);
    # manual ack/nack when the handler takes 2 args (delivery, message).
    def handle_incoming_delivery(delivery)
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
