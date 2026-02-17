# frozen_string_literal: true

require_relative 'robot/template_rendering'
require_relative 'robot/mcp_management'
require_relative 'robot/bus_messaging'

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
    include Robot::TemplateRendering
    include Robot::MCPManagement
    include Robot::BusMessaging

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
    # @!attribute [rw] input
    #   @return [IO] input stream for user interaction (default: $stdin)
    # @!attribute [rw] output
    #   @return [IO] output stream for user interaction (default: $stdout)
    attr_accessor :input, :output

    attr_reader :name, :description, :template, :system_prompt,
                :local_tools, :mcp_clients, :mcp_tools, :memory,
                :bus, :outbox, :run_config

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
    # @param run_config [RunConfig, nil] shared configuration (merged with explicit kwargs)
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
      stop: nil,
      run_config: nil
    )
      @name = name.to_s
      @name_from_constructor = (name.to_s != "robot")
      @template = template
      @system_prompt = system_prompt
      @build_context = context
      @description = description
      @local_tools = Array(local_tools)

      # Build RunConfig from explicit kwargs, merged on top of passed-in run_config.
      # Explicit constructor kwargs always override the shared run_config.
      explicit_fields = {
        model: model, temperature: temperature, top_p: top_p, top_k: top_k,
        max_tokens: max_tokens, presence_penalty: presence_penalty,
        frequency_penalty: frequency_penalty, stop: stop,
        on_tool_call: on_tool_call, on_tool_result: on_tool_result,
        bus: bus, enable_cache: enable_cache
      }.compact

      # Only include mcp/tools if explicitly set (not the default :none sentinel)
      resolved_mcp = mcp_servers.any? ? mcp_servers : mcp
      explicit_fields[:mcp] = resolved_mcp unless ToolConfig.none_value?(resolved_mcp)
      explicit_fields[:tools] = tools unless ToolConfig.none_value?(tools)

      explicit_config = RunConfig.new(**explicit_fields)
      @run_config = run_config ? run_config.merge(explicit_config) : explicit_config

      # Extract values from effective config for backward compatibility
      @on_tool_call = @run_config.on_tool_call
      @on_tool_result = @run_config.on_tool_result

      # Store raw config values for hierarchical resolution
      @mcp_config = @run_config.mcp || :none
      @tools_config = @run_config.tools || :none

      # MCP state
      @mcp_clients = {}
      @mcp_tools = []
      @mcp_initialized = false

      # Bus state (optional inter-robot communication)
      @bus = @run_config.bus
      @message_counter = 0
      @outbox = {}
      @message_handler = nil
      @bus_processing = false
      @bus_queue = []

      # Inherent memory (used when standalone, not in a network)
      cache_enabled = @run_config.key?(:enable_cache) ? @run_config.enable_cache : true
      @memory = Memory.new(enable_cache: cache_enabled)

      # Ensure config is loaded (triggers PM setup, RubyLLM config, etc.)
      config = RobotLab.config

      # Build chat kwargs for Agent's super
      resolved_model = @run_config.model || config.ruby_llm.model
      chat_kwargs = { model: resolved_model }

      # Create the persistent chat via Agent's initialize
      super(chat: nil, **chat_kwargs)

      # Apply template first (includes front matter config like model, temperature)
      # then constructor params override — constructor is more specific than template.
      apply_template_to_chat(context) if @template
      @chat.with_instructions(@system_prompt) if @system_prompt

      # Constructor params override template front matter (use run_config values)
      apply_chat_option(:with_temperature, @run_config.temperature)
      apply_chat_option(:with_top_p, @run_config.top_p)
      apply_chat_option(:with_top_k, @run_config.top_k)
      apply_chat_option(:with_max_tokens, @run_config.max_tokens)
      apply_chat_option(:with_presence_penalty, @run_config.presence_penalty)
      apply_chat_option(:with_frequency_penalty, @run_config.frequency_penalty)
      apply_chat_option(:with_stop, @run_config.stop)

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


    # Send a message and get a response, with Robot's extended capabilities
    #
    # @param message [String] the user message
    # @param network [NetworkRun, nil] network context (legacy)
    # @param network_memory [Memory, nil] shared network memory
    # @param memory [Memory, Hash, nil] runtime memory to merge
    # @param mcp [Symbol, Array, nil] runtime MCP override
    # @param tools [Symbol, Array, nil] runtime tools override
    # @return [RobotResult]
    def run(message = nil, network: nil, network_memory: nil, network_run_config: nil,
            memory: nil, mcp: :none, tools: :none, **kwargs)
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
        resolved_mcp = resolve_mcp_hierarchy(mcp, network: network, network_run_config: network_run_config)
        resolved_tools = resolve_tools_hierarchy(tools, network: network, network_run_config: network_run_config)

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
        run_config: (@run_config.empty? ? nil : @run_config.to_json_hash),
        bus: @bus ? true : nil
      }.compact
    end

    private

    # Apply a chat option if the value is non-nil
    def apply_chat_option(method, value)
      @chat.public_send(method, value) if value
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
      network_run_config = run_params.delete(:network_run_config)

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
      merged[:network_run_config] = network_run_config if network_run_config

      merged
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


    def all_tools
      @local_tools + @mcp_tools
    end


    def filtered_tools(allowed_names)
      available = all_tools
      return available if allowed_names.empty?

      ToolConfig.filter_tools(available, allowed_names: allowed_names)
    end
  end
end
