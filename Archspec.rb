# rubocop:disable Naming/FileName -- archspec's own CLI hardcodes this exact
# filename (`archspec init` creates it, `archspec check` looks for it); it
# cannot be renamed to snake_case.

component :robot,         in: "lib/robot_lab/robot.rb"
component :robot_support, in: "lib/robot_lab/robot/**/*.rb"
component :network,       in: ["lib/robot_lab/network.rb", "lib/robot_lab/bus_poller.rb"]
component :memory,        in: ["lib/robot_lab/memory.rb", "lib/robot_lab/memory_change.rb"]
component :mcp,           in: "lib/robot_lab/mcp/**/*.rb"
component :sandbox,       in: ["lib/robot_lab/sandbox.rb", "lib/robot_lab/sandbox/**/*.rb"]
component :streaming,     in: "lib/robot_lab/streaming/**/*.rb"
component :budget,        in: "lib/robot_lab/budget/**/*.rb"
component :hooks,         in: %w[
  lib/robot_lab/hook.rb
  lib/robot_lab/hook_context.rb
  lib/robot_lab/hook_registry.rb
  lib/robot_lab/hooks.rb
]
component :tools, in: %w[
  lib/robot_lab/tool.rb
  lib/robot_lab/tool_config.rb
  lib/robot_lab/tool_manifest.rb
  lib/robot_lab/script_tool.rb
]
component :config, in: ["lib/robot_lab/config.rb", "lib/robot_lab/run_config.rb"]

# NOTE: every file here reopens `module RobotLab`, so a `dependencies.forbid`
# rule keyed on components (e.g. `memory.cannot_use :robot`) treats a plain
# `RobotLab.config` call as "depends on every component" — every file
# "defines" the bare RobotLab constant. Naming the actual target constants
# instead of components sidesteps that ambiguity.

# Memory is a low-level primitive shared by Robot and Network; it must not
# depend back on the things that depend on it.
memory.cannot_reference_constants "RobotLab::Robot", "RobotLab::Network"

# MCP is an external-tool integration layer that Robot/Network consume; it
# must not reach back into the objects that use it.
mcp.cannot_reference_constants "RobotLab::Robot", "RobotLab::Network"

# Sandbox runs untrusted/generated code paths and should have the smallest
# possible surface area — no reaching into orchestration or memory internals.
sandbox.cannot_reference_constants "RobotLab::Robot", "RobotLab::Network", "RobotLab::Memory"

# Config/RunConfig sits at the bottom of the configuration cascade
# (RobotLab.config -> Network -> Robot -> template -> task -> runtime) and
# must not depend upward on the objects it configures.
config.cannot_reference_constants "RobotLab::Robot", "RobotLab::Network"
# rubocop:enable Naming/FileName
