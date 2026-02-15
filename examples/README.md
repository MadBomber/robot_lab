# RobotLab Examples

Working demonstrations of RobotLab features, from single-robot basics to multi-robot orchestration and message bus communication.

## Prerequisites

- Ruby >= 3.2
- `bundle install` (from the project root)
- An LLM API key (e.g., `ANTHROPIC_API_KEY`)

## Running Examples

```bash
# Run a specific example by number
bundle exec rake examples:run[1]

# Run all examples
bundle exec rake examples:all

# Run directly
bundle exec ruby examples/01_simple_robot.rb
```

## Directory Structure

```
examples/
  01_simple_robot.rb          # Basic robot with template
  02_tools.rb                 # Robot with custom tools
  03_network.rb               # Multi-robot network with routing
  04_mcp.rb                   # MCP server integration (GitHub)
  05_streaming.rb             # Real-time streaming events
  06_prompt_templates.rb      # Template-based e-commerce support
  07_network_memory.rb        # Shared memory with concurrent robots
  08_llm_config.rb            # Configuration hierarchy demo
  09_chaining.rb              # with_* method chaining & reconfiguration
  10_memory.rb                # Advanced Memory API operations
  11_network_introspection.rb # Network visualization & inspection
  12_message_bus.rb           # Bidirectional robot communication
  prompts/                    # Prompt templates (.md with YAML front matter)
```

## Examples

### 01 — Simple Robot

Create and run a basic robot using a prompt template. Sends a single message and displays the response.

**Requires:** LLM API key

### 02 — Tools

Give a robot custom tools (`Calculator`, `FortuneCookie`) defined as `RubyLLM::Tool` subclasses. The LLM decides when to call each tool based on the user's request.

**Requires:** LLM API key

### 03 — Multi-Robot Network

Build a customer support network with a classifier robot that routes requests to billing, technical, or general specialists. Uses SimpleFlow's optional task activation for conditional routing.

**Requires:** LLM API key

### 04 — MCP Integration

Connect to the GitHub MCP server via stdio transport. Part 1 demonstrates direct `MCP::Client` usage (listing tools, calling `search_repositories`). Part 2 wraps the MCP server inside a robot for natural-language queries.

**Requires:** LLM API key, `GITHUB_PERSONAL_ACCESS_TOKEN`, `github-mcp-server` installed

### 05 — Streaming

Real-time streaming of robot responses using `RobotLab::Streaming::Context`. Simulates text deltas with timing to demonstrate the streaming event model, then shows the code pattern for streaming with a robot or network.

**Requires:** None (simulated events, no LLM calls)

### 06 — Prompt Templates

Full e-commerce support system using prompt_manager templates with YAML front matter. A triage robot classifies customer requests and routes to order, product, or escalation specialists. Demonstrates build-time context (company info, policies) and run-time context (customer data, order history).

**Requires:** LLM API key

### 07 — Network Memory

Reactive shared memory with concurrent robots. Multiple analysis robots (sentiment, entity extraction, keywords) run in parallel and write to shared memory. A synthesizer robot waits for all results using blocking reads, then produces a combined analysis. Demonstrates subscriptions, notifications, and network broadcast.

**Requires:** LLM API key

### 08 — LLM Configuration

Walks through the full configuration hierarchy without making LLM calls:

1. Bundled defaults
2. Environment-specific overrides
3. XDG user config
4. Project config
5. Environment variables
6. Template front matter
7. Constructor parameters
8. `with_*` method chaining
9. Run-time context

**Requires:** None (no LLM calls)

### 09 — Chaining & Reconfiguration

Demonstrates the Robot API surface for runtime configuration: `with_*` method chaining, `update()` for reconfiguration, `to_h` introspection, config diffs between steps, and how constructor params override template front matter.

**Requires:** None (no LLM calls)

### 10 — Advanced Memory

Comprehensive Memory API demo: `StateProxy` for method-style access, key and pattern subscriptions, `MemoryChange` objects, key enumeration, serialization round-trips, clone for isolated copies, delete with reserved key protection, and clear vs reset.

**Requires:** None (no LLM calls)

### 11 — Network Introspection

Network visualization and inspection tools: `to_mermaid()` for diagram export, `to_dot()` for Graphviz, `execution_plan()` for text output, `visualize()` for ASCII pipelines, robot access by name, dynamic `add_robot()`, `to_h()` introspection, task-specific config, and `broadcast()`.

**Requires:** None (no LLM calls)

### 12 — Message Bus

Bidirectional robot communication via TypedBus. A comedy critic (Alice) tasks a comedian (Bob) to tell robot jokes. Alice evaluates each joke with her LLM; if it's not funny, she sends Bob back for another attempt. Bob's temperature ramps from 0.2 to 1.0 across retries for increasing creativity. The loop continues until Alice approves or `MAX_ATTEMPTS` is reached.

Demonstrates: Robot subclasses, prompt templates, auto-ack `on_message`, `reply()` convenience, temperature ramping, convergence patterns.

**Requires:** LLM API key

## Prompt Templates

Templates live in `examples/prompts/` as `.md` files with YAML front matter. Each template defines a robot's personality and behavior:

```markdown
---
description: Simple helpful assistant
temperature: 0.7
parameters:
  company_name: null
---
You are a helpful assistant for <%= company_name %>.
```

Front matter keys like `model`, `temperature`, `top_p`, `max_tokens` are applied to the robot's chat automatically. Parameters with `null` values are required and must be provided via `context:` at build time.

### Template Inventory

| Template | Used By | Description |
|----------|---------|-------------|
| `helper.md` | 01 | Simple helpful assistant |
| `assistant.md` | 02 | Assistant with tool access |
| `classifier.md` | 03 | Request classifier (billing/technical/general) |
| `billing.md` | 03 | Billing specialist |
| `technical.md` | 03 | Technical support specialist |
| `general.md` | 03 | General support |
| `github_assistant.md` | 04 | GitHub-aware assistant |
| `triage.md` | 06 | E-commerce request triage |
| `order_support.md` | 06 | Order inquiry specialist |
| `product_support.md` | 06 | Product questions specialist |
| `escalation.md` | 06 | Complex issue handler |
| `sentiment_analyzer.md` | 07 | Sentiment analysis |
| `entity_extractor.md` | 07 | Entity extraction |
| `keyword_extractor.md` | 07 | Keyword extraction |
| `synthesizer.md` | 07 | Multi-source synthesis |
| `llm_config_demo.md` | 08 | Configuration demo |
| `configurable.md` | 09 | Configurable template with front matter |
| `comedian.md` | 12 | Robot joke teller |
| `comedy_critic.md` | 12 | Joke evaluator (FUNNY/NOT_FUNNY) |
