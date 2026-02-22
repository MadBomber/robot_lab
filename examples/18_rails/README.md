# RobotLab Rails 8 Demo

Minimal Rails 8 app that demonstrates RobotLab's full Rails integration:

- **ChatRobot** with a custom `TimeTool`
- **RobotRunJob** for background execution
- **Turbo Stream** token streaming to the browser
- **Persistence** via `RobotLabThread` + `RobotLabResult`
- **Conversation history** on page reload

## Prerequisites

- Ruby 3.2+
- An LLM API key (e.g. `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` in your env)

## Setup

```bash
cd examples/18_rails
bin/setup
```

## Run

```bash
bin/dev
# Open http://localhost:3000
```

## Try It

1. Type "What time is it?" — the robot will call TimeTool and stream the response
2. Refresh the page — conversation history is preserved
3. Check `db/development.sqlite3` to see persisted threads and results

## Architecture

```
app/
  controllers/chat_controller.rb  — index + create actions
  views/chat/index.html.erb       — form + Turbo Stream subscription
  models/                         — RobotLabThread, RobotLabResult
  robots/chat_robot.rb            — robot factory with system prompt + tool
  tools/time_tool.rb              — simple RobotLab::Tool subclass
  jobs/robot_run_job.rb           — enqueues robot.run() with Turbo callbacks
```

No Redis, no Solid Queue, no asset pipeline. Uses `:async` adapters for both ActiveJob and ActionCable.
