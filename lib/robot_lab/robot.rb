# frozen_string_literal: true

require_relative 'robot/template_rendering'
require_relative 'robot/mcp_management'
require_relative 'robot/bus_messaging'
require_relative 'robot/history_search'
require_relative 'robot/agent_skill_matching'

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
    include Robot::HistorySearch
    prepend Robot::AgentSkillMatching

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
                :bus, :outbox, :config, :skills, :provider,
                :total_input_tokens, :total_output_tokens, :learnings,
                :durable_store, :learn_domain

    # @!attribute [r] mcp_config
    #   @return [Symbol, Array] build-time MCP configuration (raw, unresolved)
    # @!attribute [r] tools_config
    #   @return [Symbol, Array] build-time tools configuration (raw, unresolved)
    attr_reader :mcp_config, :tools_config

    # Returns the fully-merged configuration for this robot at runtime.
    #
    # Reflects the result of merging the RunConfig hierarchy (global → network →
    # constructor kwargs → template front matter). Nil fields are omitted.
    #
    # @return [Hash] merged config keyed by field name
    #
    # @example
    #   robot.effective_config
    #   #=> { model: "claude-sonnet-4-6", temperature: 0.7, max_tokens: 4096 }
    def effective_config
      {
        model:               @config.model,
        temperature:         @config.temperature,
        top_p:               @config.top_p,
        top_k:               @config.top_k,
        max_tokens:          @config.max_tokens,
        presence_penalty:    @config.presence_penalty,
        frequency_penalty:   @config.frequency_penalty,
        stop:                @config.stop,
        tools:               @config.tools,
        mcp:                 @config.mcp,
        max_tool_rounds:     @config.max_tool_rounds,
        doom_loop_threshold: @config.doom_loop_threshold,
        auto_compact:        @config.auto_compact,
        compact_threshold:   @config.compact_threshold,
        token_budget:        @config.token_budget
      }.reject { |_, v| v.nil? }
    end


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
    # @param on_content [Proc, nil] callback invoked with each streaming content chunk
    # @param enable_cache [Boolean] whether to enable semantic caching
    # @param bus [TypedBus::MessageBus, nil] optional message bus for inter-robot communication
    # @param temperature [Float, nil] controls randomness
    # @param top_p [Float, nil] nucleus sampling threshold
    # @param top_k [Integer, nil] top-k sampling
    # @param max_tokens [Integer, nil] maximum tokens in response
    # @param presence_penalty [Float, nil] penalize based on presence
    # @param frequency_penalty [Float, nil] penalize based on frequency
    # @param stop [String, Array, nil] stop sequences
    # @param skills [Symbol, Array<Symbol>, nil] skill templates to prepend
    # @param config [RunConfig, nil] shared configuration (merged with explicit kwargs)
    def initialize(
      name:,
      template: nil,
      system_prompt: nil,
      context: {},
      description: nil,
      local_tools: [],
      model: nil,
      provider: nil,
      mcp_servers: [],
      mcp: :none,
      tools: :none,
      on_tool_call: nil,
      on_tool_result: nil,
      on_content: nil,
      enable_cache: true,
      bus: nil,
      skills: nil,
      temperature: nil,
      top_p: nil,
      top_k: nil,
      max_tokens: nil,
      presence_penalty: nil,
      frequency_penalty: nil,
      stop: nil,
      max_tool_rounds: nil,
      token_budget: nil,
      doom_loop_threshold: nil,
      mcp_discovery: false,
      config: nil,
      learn: false,
      learn_domain: nil,
      store_path: nil
    )
      assign_identity_ivars(name: name, template: template, system_prompt: system_prompt,
                            context: context, description: description, local_tools: local_tools,
                            skills: skills, mcp_discovery: mcp_discovery)

      build_effective_config(
        model: model, temperature: temperature, top_p: top_p, top_k: top_k,
        max_tokens: max_tokens, presence_penalty: presence_penalty,
        frequency_penalty: frequency_penalty, stop: stop,
        on_tool_call: on_tool_call, on_tool_result: on_tool_result,
        on_content: on_content, bus: bus, enable_cache: enable_cache,
        max_tool_rounds: max_tool_rounds, token_budget: token_budget,
        doom_loop_threshold: doom_loop_threshold, mcp_servers: mcp_servers,
        mcp: mcp, tools: tools, config: config
      )

      extract_config_ivars
      initialize_runtime_state
      initialize_memory
      configure_learning(learn: learn, learn_domain: learn_domain, store_path: store_path)

      lab_config    = RobotLab.config
      resolved_model = @config.model || lab_config.ruby_llm.model
      chat_kwargs   = { model: resolved_model }

      # RubyLLM auto-sets assume_model_exists for local providers when provider is specified.
      @provider = provider
      if @provider
        chat_kwargs[:provider] = @provider
        chat_kwargs[:assume_model_exists] = true
      end

      super(chat: nil, **chat_kwargs)

      apply_template
      apply_system_prompt
      apply_chat_params
      register_chat_callbacks
    end


    # Returns the model identifier
    #
    # @return [String, nil] the LLM model ID string
    def model
      return nil unless @chat.respond_to?(:model)

      m = @chat.model
      m.respond_to?(:id) ? m.id : m.to_s
    end

    private def assign_identity_ivars(name:, template:, system_prompt:, context:, description:,
                                      local_tools:, skills:, mcp_discovery:)
      @name = name.to_s
      @name_from_constructor = (name.to_s != "robot")
      @template = template
      @system_prompt = system_prompt
      @build_context = context
      @description = description
      @local_tools = Array(local_tools)
      @skills = skills ? Array(skills).map(&:to_sym) : nil
      @expanded_skills = nil
      @pending_agent_skills = []
      @agent_skill_store    = nil
      @mcp_discovery = mcp_discovery
    end


    # Build RunConfig from explicit kwargs, merged on top of any passed-in config.
    # Explicit constructor kwargs always win.
    private def build_effective_config(model:, temperature:, top_p:, top_k:, max_tokens:, # rubocop:disable Metrics/ParameterLists
                                       presence_penalty:, frequency_penalty:, stop:,
                                       on_tool_call:, on_tool_result:, on_content:,
                                       bus:, enable_cache:, max_tool_rounds:, token_budget:,
                                       doom_loop_threshold:, mcp_servers:, mcp:, tools:, config:)
      explicit_fields = {
        model: model, temperature: temperature, top_p: top_p, top_k: top_k,
        max_tokens: max_tokens, presence_penalty: presence_penalty,
        frequency_penalty: frequency_penalty, stop: stop,
        on_tool_call: on_tool_call, on_tool_result: on_tool_result,
        on_content: on_content, bus: bus, enable_cache: enable_cache,
        max_tool_rounds: max_tool_rounds, token_budget: token_budget,
        doom_loop_threshold: doom_loop_threshold
      }.compact

      resolved_mcp = mcp_servers.any? ? mcp_servers : mcp
      explicit_fields[:mcp]   = resolved_mcp unless ToolConfig.none_value?(resolved_mcp)
      explicit_fields[:tools] = tools        unless ToolConfig.none_value?(tools)

      explicit_config = RunConfig.new(**explicit_fields)
      @config = config ? config.merge(explicit_config) : explicit_config
    end


    private def extract_config_ivars
      @on_tool_call   = @config.on_tool_call
      @on_tool_result = @config.on_tool_result
      @on_content     = @config.on_content
      @mcp_config     = @config.mcp   || :none
      @tools_config   = @config.tools || :none
    end


    private def initialize_runtime_state
      @mcp_clients         = {}
      @mcp_tools           = []
      @mcp_initialized     = false
      @bus                 = @config.bus
      @message_counter     = 0
      @outbox              = {}
      @message_handler     = ->(_msg) {}
      @bus_poller          = nil
      @private_bus_poller  = nil
      @bus_poller_group    = :default
      @total_input_tokens  = 0
      @total_output_tokens = 0
      @learnings           = []
    end


    private def initialize_memory
      cache_enabled = @config.key?(:enable_cache) ? @config.enable_cache : true
      @memory = Memory.new(enable_cache: cache_enabled)
      persisted = @memory.get(:learnings)
      @learnings = Array(persisted) if persisted
    end


    private def configure_learning(learn:, learn_domain:, store_path:)
      return unless learn && RobotLab.extension_loaded?(:durable)

      if learn_domain
        setup_durable_learning(domain: learn_domain, store_path: store_path)
      else
        warn "[RobotLab] Robot '#{@name}': learn: true requires learn_domain: to be set. Durable learning disabled."
      end
    end


    private def apply_template
      define_chat_delegators

      all_skill_ids = Array(@skills)
      if @template
        parsed_main = PM.parse(@template)
        fm_skills   = extract_skills_from_metadata(parsed_main.metadata)
        all_skill_ids = all_skill_ids + fm_skills
      end

      if all_skill_ids.any?
        apply_skills_and_template_to_chat(all_skill_ids, @build_context)
      elsif @template
        apply_template_to_chat(@build_context)
      end
    end


    private def apply_system_prompt
      @chat.with_instructions(@system_prompt) if @system_prompt
    end


    private def apply_chat_params
      @chat.with_temperature(@config.temperature) if @config.temperature

      extra_params = {
        top_p: @config.top_p, top_k: @config.top_k,
        max_tokens: @config.max_tokens,
        presence_penalty: @config.presence_penalty,
        frequency_penalty: @config.frequency_penalty,
        stop: @config.stop
      }.compact
      @chat.with_params(**extra_params) if extra_params.any?
    end


    private def register_chat_callbacks
      @chat.on_tool_call(&@on_tool_call)     if @on_tool_call
      @chat.on_tool_result(&@on_tool_result) if @on_tool_result
      setup_bus_channel if @bus
    end


    # Dynamically delegate all with_* methods from @chat, returning self for chaining.
    # Discovered from the actual Chat class to avoid maintenance sync issues.
    private def define_chat_delegators
      @chat.class.public_instance_methods(false)
        .select { |m| m.start_with?('with_') }
        .each do |method_name|
          define_singleton_method(method_name) do |*args, **kwargs, &block|
            @chat.public_send(method_name, *args, **kwargs, &block)
            self
          end
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
    # @yield [chunk] optional streaming block called with each content chunk
    # @return [RobotResult]
    def run(message = nil, network: nil, network_memory: nil, network_config: nil,
            memory: nil, mcp: :none, tools: :none, **kwargs, &block)
      run_memory = resolve_run_memory(memory, network: network, network_memory: network_memory)
      previous_writer = run_memory.current_writer
      run_memory.current_writer = @name

      begin
        run_context = kwargs.except(:with)
        prepare_tools(message: message, mcp: mcp, tools: tools,
                      network: network, network_config: network_config)
        rerender_template(run_context) if @template && run_context.any?
        response = invoke_ask(message: message, kwargs: kwargs, block: block)
        result = build_result(response, run_memory)
        enforce_token_budget!
        result
      ensure
        remove_doom_loop_detection
        restore_tool_call_callback if @config.max_tool_rounds
        run_reflector if @durable_store
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
      @chat.with_temperature(temperature) if temperature

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

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      robot_result = run(message, **run_context)
      robot_result.duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      result
        .with_context(@name.to_sym, robot_result)
        .continue(robot_result)
    rescue Exception => e # rubocop:disable Lint/RescueException
      # Catch all errors (including SecurityError, Timeout::Error, etc.)
      # so one failing robot doesn't crash the entire network pipeline.
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      error_result = RobotResult.new(
        robot_name: @name,
        output: [TextMessage.new(role: 'assistant', content: "Error: #{e.class}: #{e.message}")]
      )
      error_result.duration = elapsed

      result
        .with_context(@name.to_sym, error_result)
        .continue(error_result)
    end


    # Reset the robot's inherent memory
    #
    # @return [self]
    def reset_memory
      @memory.reset
      self
    end


    # Eagerly connect to configured MCP servers and discover tools.
    # Normally MCP connections are lazy (established on first run).
    # Call this to connect early, e.g. to display connection status at startup.
    #
    # @return [self]
    def connect_mcp!
      resolved_mcp = resolve_mcp_hierarchy(@mcp_config)
      ensure_mcp_clients(resolved_mcp) if resolved_mcp.is_a?(Array) && resolved_mcp.any?
      self
    end

    # Returns server names that failed to connect.
    #
    # @return [Array<String>]
    def failed_mcp_server_names
      return [] unless @failed_mcp_configs

      @failed_mcp_configs.keys
    end

    # Disconnect all MCP clients and bus channel.
    #
    # @return [self]
    def disconnect
      @mcp_clients.each_value(&:disconnect)
      teardown_bus_channel if @bus
      self
    end


    # --- Public APIs for external MCP and history management (A4) ---

    # Inject pre-connected MCP clients and their tools into this robot.
    # Used by host applications (e.g. AIA) that manage MCP connections
    # externally and need to pass them to robots without re-connecting.
    #
    # @param clients [Hash<String, MCP::Client>] connected MCP clients by server name
    # @param tools [Array<Tool>] tools discovered from the MCP servers
    # @return [self]
    def inject_mcp!(clients:, tools:)
      @mcp_clients = clients
      @mcp_tools = tools
      @mcp_initialized = true
      self
    end

    # Access the underlying RubyLLM::Chat instance.
    # Useful for checkpoint/restore operations that need direct
    # access to conversation state.
    #
    # @return [RubyLLM::Chat]
    def chat
      @chat
    end

    # Return the conversation messages from the underlying chat.
    #
    # @return [Array<RubyLLM::Message>]
    def messages
      @chat.messages
    end

    # Clear conversation messages, optionally keeping the system prompt.
    #
    # @param keep_system [Boolean] whether to preserve the system message
    # @return [self]
    def clear_messages(keep_system: true)
      if keep_system
        system_msg = @chat.messages.find { |m| m.role == :system }
        @chat.reset_messages!
        @chat.add_message(system_msg) if system_msg
      else
        @chat.reset_messages!
      end
      self
    end

    # Replace conversation messages with a saved set (for checkpoint restore).
    #
    # @param messages [Array<RubyLLM::Message>] the messages to restore
    # @return [self]
    def replace_messages(messages)
      @chat.reset_messages!
      messages.each { |m| @chat.add_message(m) }
      self
    end

    # Compress conversation history using TF-IDF relevance scoring.
    #
    # Old turns are tiered against the most recent context:
    # - High relevance (score >= keep_threshold)          → kept verbatim
    # - Medium relevance (drop_threshold..keep_threshold) → summarized or dropped
    # - Low relevance (score < drop_threshold)            → dropped
    #
    # System messages and tool call/result messages are always preserved.
    # The most recent +recent_turns+ pairs are also always kept verbatim.
    #
    # Requires the optional 'classifier' gem (~> 2.3).
    # Raises +DependencyError+ if not installed.
    #
    # @param recent_turns [Integer] turn pairs to protect at the end (default 3)
    # @param keep_threshold [Float] cosine score >= this → keep verbatim (default 0.6)
    # @param drop_threshold [Float] cosine score < this → drop (default 0.2)
    # @param summarizer [#call, nil] callable(text) -> String for medium-tier;
    #                                nil drops medium-tier instead of summarizing
    # @return [self]
    def compress_history(recent_turns: 3, keep_threshold: 0.6, drop_threshold: 0.2, summarizer: nil)
      compressed = HistoryCompressor.new(
        messages:       @chat.messages,
        recent_turns:   recent_turns,
        keep_threshold: keep_threshold,
        drop_threshold: drop_threshold,
        summarizer:     summarizer
      ).call
      replace_messages(compressed)
    end

    # Delegate a task to another robot, synchronously or asynchronously.
    #
    # **Synchronous** (default, +async: false+): blocks until the delegatee
    # finishes and returns a +RobotResult+ annotated with +delegated_by+,
    # +duration+, and token counts.
    #
    # **Asynchronous** (+async: true+): starts the delegatee in a background
    # thread and returns a +DelegationFuture+ immediately. Call +future.value+
    # to block for the result, or +future.resolved?+ to poll.
    #
    # @example Synchronous
    #   result = manager.delegate(to: analyst, task: "What are the risks?")
    #   puts result.reply          # analyst's answer
    #   puts result.delegated_by   # => "manager"
    #   puts result.duration       # => 1.43 (seconds)
    #
    # @example Async fan-out
    #   f1 = manager.delegate(to: summarizer, task: "summarize ...", async: true)
    #   f2 = manager.delegate(to: analyst,    task: "analyze ...",   async: true)
    #   summary  = f1.value          # blocks if not yet done
    #   analysis = f2.value(timeout: 30)
    #
    # @param to [Robot] the robot to delegate to
    # @param task [String] the message to send
    # @param async [Boolean] when true, returns a DelegationFuture immediately
    # @param kwargs [Hash] additional keyword args forwarded to Robot#run
    # @return [RobotResult] when async: false
    # @return [DelegationFuture] when async: true
    def delegate(to:, task:, async: false, **kwargs)
      if async
        future = DelegationFuture.new(robot_name: to.name, delegated_by: @name)
        delegator_name = @name

        Thread.new do
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = to.run(task, **kwargs)
          result.duration     = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          result.delegated_by = delegator_name
          future.resolve!(result)
        rescue => e
          future.reject!(e)
        end

        future
      else
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = to.run(task, **kwargs)
        result.duration     = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        result.delegated_by = @name
        result
      end
    end

    # Return the provider for this robot's chat.
    # Useful for displaying model/provider info without reaching
    # into chat internals.
    #
    # @return [String, nil]
    def chat_provider
      m = @chat.model
      m.respond_to?(:provider) ? m.provider : nil
    rescue StandardError
      nil
    end

    # Find an MCP client by server name.
    #
    # @param server_name [String] the MCP server name
    # @return [MCP::Client, nil]
    def mcp_client(server_name)
      @mcp_clients[server_name]
    end


    # Add a learning to this robot's accumulation store.
    #
    # Deduplicates by bidirectional substring matching: a new learning is
    # skipped if it is already contained within an existing learning, or
    # an existing learning is contained within the new one (the new one
    # wins and replaces the weaker entry).
    #
    # Learnings are persisted to the robot's inherent memory under :learnings.
    #
    # @param text [String] the insight to record
    # @return [self]
    def learn(text)
      text = text.to_s.strip
      return self if text.empty?

      # Remove any existing learning that is a substring of the new one
      @learnings.reject! { |existing| text.include?(existing) }

      # Skip if any existing learning already covers the new one
      unless @learnings.any? { |existing| existing.include?(text) }
        @learnings << text
        @memory.set(:learnings, @learnings.dup)
      end

      self
    end


    # Reset cumulative token counters to zero.
    #
    # @return [self]
    def reset_token_totals
      @total_input_tokens = 0
      @total_output_tokens = 0
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
        skills: @skills,
        system_prompt: system_prompt,
        local_tools: local_tools.map { |t| t.respond_to?(:name) ? t.name : t.to_s },
        mcp_tools: mcp_tools.map(&:name),
        mcp_config: @mcp_config,
        tools_config: @tools_config,
        mcp_servers: @mcp_clients.keys,
        model: model,
        config: (@config.empty? ? nil : @config.to_json_hash),
        bus: @bus ? true : nil
      }.compact
    end

    private

    def resolve_active_memory(network: nil, network_memory: nil)
      network_memory || network&.memory || @memory
    end


    def resolve_run_memory(memory, network:, network_memory:)
      run_memory = resolve_active_memory(network: network, network_memory: network_memory)
      case memory
      when Memory then memory
      when Hash   then run_memory.tap { |m| m.merge!(memory) }
      else             run_memory
      end
    end


    def prepare_tools(message:, mcp:, tools:, network:, network_config:)
      resolved_mcp   = resolve_mcp_hierarchy(mcp, network: network, network_config: network_config)
      resolved_tools = resolve_tools_hierarchy(tools, network: network, network_config: network_config)

      if @mcp_discovery && !@mcp_initialized && resolved_mcp.is_a?(Array)
        resolved_mcp = MCP::ServerDiscovery.select(message.to_s, from: resolved_mcp)
      end

      ensure_mcp_clients(resolved_mcp)

      filtered = filtered_tools(resolved_tools)
      @chat.with_tools(*filtered) if filtered.any?
    end


    def invoke_ask(message:, kwargs:, block:)
      effective_message = inject_learnings(message)
      maybe_compact
      install_circuit_breaker if @config.max_tool_rounds
      install_doom_loop_detection
      ask_kwargs = kwargs.slice(:with)
      streaming  = effective_streaming_block(block)
      ask(effective_message, **ask_kwargs, &streaming)
    end


    def enforce_token_budget!
      budget = @config.token_budget
      return unless budget && @total_input_tokens + @total_output_tokens > budget

      raise InferenceError,
            "Token budget exceeded: #{@total_input_tokens + @total_output_tokens} tokens used, budget is #{budget}"
    end


    # Extract run context from SimpleFlow::Result
    def extract_run_context(result)
      run_params = (result.context[:run_params] || {}).dup

      # Extract robot-specific params
      mcp = run_params.delete(:mcp) || :none
      tools = run_params.delete(:tools) || :none
      memory = run_params.delete(:memory)
      network_memory = run_params.delete(:network_memory)
      network_config = run_params.delete(:network_config)

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
      merged[:network_config] = network_config if network_config

      merged
    end


    def build_result(response, _memory)
      output = if response.respond_to?(:content) && response.content
                 [TextMessage.new(role: 'assistant', content: response.content)]
               else
                 []
               end

      tool_calls = response.respond_to?(:tool_calls) ? (response.tool_calls || []) : []

      # Extract token usage from the response
      input_toks = 0
      output_toks = 0
      if response.respond_to?(:tokens) && response.tokens
        input_toks = response.tokens.input.to_i
        output_toks = response.tokens.output.to_i
      elsif response.respond_to?(:input_tokens)
        input_toks = response.input_tokens.to_i
        output_toks = response.respond_to?(:output_tokens) ? response.output_tokens.to_i : 0
      end

      @total_input_tokens += input_toks
      @total_output_tokens += output_toks

      RobotResult.new(
        robot_name: @name,
        output: output,
        tool_calls: normalize_tool_calls(tool_calls),
        stop_reason: response.respond_to?(:stop_reason) ? response.stop_reason : nil,
        raw: response,
        input_tokens: input_toks,
        output_tokens: output_toks
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


    # Merge the stored on_content callback with a runtime streaming block.
    # If both exist, both fire (stored first, then runtime block).
    #
    # @param runtime_block [Proc, nil] block passed to run()
    # @return [Proc, nil] the effective streaming block
    def effective_streaming_block(runtime_block)
      return @on_content unless runtime_block
      return runtime_block unless @on_content

      stored = @on_content
      proc { |chunk| stored.call(chunk); runtime_block.call(chunk) }
    end


    def all_tools
      @local_tools + @mcp_tools
    end


    def filtered_tools(allowed_names)
      available = all_tools
      return available if allowed_names.empty?

      ToolConfig.filter_tools(available, allowed_names: allowed_names)
    end


    # Prepend accumulated learnings to a user message when learnings exist.
    def inject_learnings(message)
      return message if @learnings.empty? || message.nil?

      learning_block = "LEARNINGS FROM PREVIOUS RUNS:\n" +
                       @learnings.map { |l| "- #{l}" }.join("\n") +
                       "\n\n"
      "#{learning_block}#{message}"
    end


    # Install per-run doom loop detection on @chat's execute_tool.
    # Tracks tool call names; when a consecutive or cyclic repetition exceeds
    # the threshold, embeds a self-correction warning in the tool result so the
    # LLM can change strategy without requiring an external circuit breaker.
    def install_doom_loop_detection
      threshold = @config.doom_loop_threshold || DoomLoopDetector::DEFAULT_THRESHOLD
      detector = DoomLoopDetector.new(threshold: threshold)

      @chat.define_singleton_method(:execute_tool) do |tool_call|
        result = super(tool_call)
        detector.track(tool_call.name)

        if detector.doom_loop?
          warning = detector.warning_message
          detector.reset
          case result
          when RubyLLM::Tool::Halt then result
          when Hash                then result.merge(_doom_loop_warning: warning)
          when String              then "#{result}\n\n⚠️ #{warning}"
          else                          result
          end
        else
          result
        end
      end
    end

    # Remove the doom loop detection singleton method from @chat.
    def remove_doom_loop_detection
      sc = @chat.singleton_class
      sc.remove_method(:execute_tool) if sc.method_defined?(:execute_tool)
    end

    # Compact conversation history before an ask() call if auto_compact is set.
    #
    # :none (default) — no-op
    # :context_window — compress when estimated tokens exceed compact_threshold
    #                   fraction of the model's context window (default 80%)
    # Proc            — called with self; application owns the decision and strategy
    def maybe_compact
      return if @chat.messages.empty?

      compact = @config.auto_compact
      return if compact.nil? || compact == :none

      case compact
      when :context_window
        compact_if_over_context_window
      when Proc
        compact.call(self)
      end
    end

    def compact_if_over_context_window
      threshold     = (@config.compact_threshold || 0.80).to_f
      estimated_tok = @chat.messages.sum { |m| m.content.to_s.length } / 4

      window = begin
        RubyLLM.models.find(model)&.context_window || 200_000
      rescue StandardError
        200_000
      end

      return if estimated_tok < window * threshold

      begin
        compress_history
      rescue DependencyError => e
        RobotLab.config.logger.warn("[#{@name}] auto_compact: #{e.message}; skipping compaction")
      end
    end

    # Install a per-run circuit breaker on the chat's on_tool_call hook.
    # Raises ToolLoopError if tool calls exceed @config.max_tool_rounds.
    # Stores the previous callback so restore_tool_call_callback can undo it.
    def install_circuit_breaker
      @circuit_breaker_call_count = 0
      max = @config.max_tool_rounds
      original = @on_tool_call

      @chat.on_tool_call do |tool_call|
        @circuit_breaker_call_count += 1
        if @circuit_breaker_call_count > max
          raise ToolLoopError,
                "Circuit breaker triggered: #{@circuit_breaker_call_count} tool calls exceeded " \
                "max_tool_rounds (#{max})"
        end
        original&.call(tool_call)
      end
    end


    # Restore the original on_tool_call callback after a circuit-breaker run.
    def restore_tool_call_callback
      @chat.on_tool_call(&@on_tool_call)
    end
  end
end
