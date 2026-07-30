# frozen_string_literal: true

module RobotLab
  class HookContext
    attr_reader :event, :metadata

    def initialize(event:, metadata: nil)
      @event = event.to_sym
      @metadata = metadata || ExtensionState.new
    end

    def ext(name)
      metadata.ext(name)
    end

    def local
      raise ArgumentError, "No hook namespace active" unless @namespace

      ext(@namespace)
    end

    def with_namespace(namespace)
      previous = @namespace
      @namespace = namespace&.to_sym
      yield self
    ensure
      @namespace = previous
    end

    def to_h
      public_snapshot.merge(metadata: metadata.to_h)
    end

    private

    def public_snapshot
      public_methods(false)
        .grep_v(/=\z/)
        .reject { |name| %i[to_h local].include?(name) }
        .sort
        .to_h { |name| [name, public_send(name)] }
    end
  end

  class RunHookContext < HookContext
    attr_reader :robot, :network, :task, :memory, :config
    attr_accessor :request, :response, :error

    def initialize(robot:, request:, network: nil, task: nil, memory: nil, config: nil, response: nil, error: nil, **)
      super(event: :run, **)
      @robot = robot
      @network = network
      @task = task
      @memory = memory
      @config = config
      @request = request
      @response = response
      @error = error
    end
  end

  class LlmGenerationHookContext < RunHookContext
    attr_reader :iteration
    attr_accessor :generation_response

    def initialize(iteration: 0, generation_response: nil, **)
      super(**)
      @iteration = iteration
      @generation_response = generation_response
    end
  end

  class ToolCallHookContext < HookContext
    attr_reader :tool, :tool_name, :tool_args, :robot
    attr_accessor :tool_result, :tool_error

    def initialize(tool:, tool_args:, robot: nil, tool_result: nil, tool_error: nil, **)
      super(event: :tool_call, **)
      @tool = tool
      @tool_name = tool.respond_to?(:name) ? tool.name : tool.class.name
      @tool_args = tool_args
      @robot = robot
      @tool_result = tool_result
      @tool_error = tool_error
    end
  end

  class NetworkRunHookContext < HookContext
    attr_reader :network, :memory, :config
    attr_accessor :context, :result, :error

    def initialize(network:, context:, memory: nil, config: nil, result: nil, error: nil, **)
      super(event: :network_run, **)
      @network = network
      @context = context
      @memory = memory
      @config = config
      @result = result
      @error = error
    end
  end

  class TaskHookContext < HookContext
    attr_reader :network, :task, :task_name, :robot, :memory, :config
    attr_accessor :result, :error

    def initialize(task:, network: nil, robot: nil, memory: nil, config: nil, result: nil, error: nil, **)
      super(event: :task, **)
      @network = network
      @task = task
      @task_name = task.name
      @robot = robot || task.robot
      @memory = memory
      @config = config
      @result = result
      @error = error
    end
  end

  class LearnHookContext < HookContext
    attr_reader :robot, :text, :learnings_before
    attr_accessor :stored, :error

    def initialize(robot:, text:, learnings_before:, **)
      super(event: :learn, **)
      @robot            = robot
      @text             = text
      @learnings_before = learnings_before.freeze
      @stored           = false
    end
  end

  class CompactionHookContext < HookContext
    attr_reader :robot, :messages_before, :config, :strategy
    attr_accessor :compacted_messages, :error

    def initialize(robot:, messages_before:, config:, strategy:, **)
      super(event: :compaction, **)
      @robot            = robot
      @messages_before  = messages_before.freeze
      @config           = config
      @strategy         = strategy
      @compacted_messages = nil
    end

    # True once an on_compaction handler has supplied a replacement message set.
    def handled?
      !@compacted_messages.nil?
    end
  end

  class ExtensionState
    def initialize
      @states = Hash.new { |h, key| h[key] = DotState.new }
    end

    def ext(name)
      @states[name.to_sym]
    end

    def to_h
      @states.transform_values(&:to_h)
    end
  end

  class DotState
    def initialize
      @data = {}
    end

    def merge_defaults(hash)
      hash.each { |k, v| @data[k.to_sym] = v unless @data.key?(k.to_sym) }
      self
    end

    def method_missing(name, *args)
      key = name.to_s.delete_suffix('=').to_sym

      if name.to_s.end_with?('=')
        @data[key] = args.first
      else
        @data[key]
      end
    end

    def respond_to_missing?(*)
      true
    end

    def to_h
      @data.dup
    end
  end
end
