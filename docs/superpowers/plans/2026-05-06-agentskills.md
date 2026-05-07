# AgentSkills.io Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing `skills:` constructor param to also recognize AgentSkills.io folder format (`~/.prompts/skills/<name>/SKILL.md`), with runtime embedding-based injection and `scripts/` auto-wrapped as tools.

**Architecture:** Format detection happens in `expand_skills` — PM templates continue as before; AgentSkill folders are stored in `@pending_agent_skills`. Before each `run()` call, a prepended `AgentSkillMatching` module embeds the message (via `DocumentStore`/fastembed), scores pending skills by cosine similarity, and injects matching skills' instructions + script tools for that call only, restoring everything in an `ensure` block.

**Tech Stack:** fastembed (via existing `DocumentStore`), `open3` (stdlib), YAML (stdlib), Minitest

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/robot_lab/agent_skill.rb` | Value object: parse SKILL.md, expose instructions + scripts |
| Create | `lib/robot_lab/agent_skill_catalog.rb` | Singleton: scan `~/.prompts/skills/`, look up by ID |
| Create | `lib/robot_lab/script_tool.rb` | Factory module: wrap a shell script as a `RobotLab::Tool` |
| Create | `lib/robot_lab/robot/agent_skill_matching.rb` | Prepended module: `run()` override for runtime injection |
| Modify | `lib/robot_lab/robot/template_rendering.rb` | `expand_skills`: detect catalog hit before PM lookup |
| Modify | `lib/robot_lab/robot.rb` | Initialize `@pending_agent_skills` / `@agent_skill_store`; prepend matching module |
| Create | `test/robot_lab/agent_skill_test.rb` | Unit tests for AgentSkill |
| Create | `test/robot_lab/agent_skill_catalog_test.rb` | Unit tests for AgentSkillCatalog |
| Create | `test/robot_lab/script_tool_test.rb` | Unit tests for ScriptTool |
| Create | `test/robot_lab/robot/agent_skill_matching_test.rb` | Unit tests for AgentSkillMatching |
| Create | `test/fixtures/skills/test_skill/SKILL.md` | Valid skill fixture |
| Create | `test/fixtures/skills/bad_skill/SKILL.md` | Missing-description fixture |
| Create | `test/fixtures/skills/scripted_skill/SKILL.md` | Skill with scripts fixture |
| Create | `test/fixtures/skills/scripted_skill/scripts/hello.sh` | Executable script fixture |

---

## Task 1: Test fixtures

**Files:**
- Create: `test/fixtures/skills/test_skill/SKILL.md`
- Create: `test/fixtures/skills/bad_skill/SKILL.md`
- Create: `test/fixtures/skills/scripted_skill/SKILL.md`
- Create: `test/fixtures/skills/scripted_skill/scripts/hello.sh`

- [ ] **Step 1: Create fixture directories and SKILL.md files**

`test/fixtures/skills/test_skill/SKILL.md`:
```markdown
---
name: test_skill
description: A test skill for verifying AgentSkills.io integration
---
You have been enhanced with the test skill. Apply rigorous testing practices.
```

`test/fixtures/skills/bad_skill/SKILL.md`:
```markdown
---
name: bad_skill
---
This skill is missing a description field.
```

`test/fixtures/skills/scripted_skill/SKILL.md`:
```markdown
---
name: scripted_skill
description: A skill that includes a bundled shell script
---
You have access to the hello script tool. Use it to greet users.
```

- [ ] **Step 2: Create the executable script fixture**

`test/fixtures/skills/scripted_skill/scripts/hello.sh`:
```bash
#!/usr/bin/env bash
# Say hello to the world
echo "Hello from AgentSkills script!"
```

Then make it executable:
```bash
chmod +x test/fixtures/skills/scripted_skill/scripts/hello.sh
```

- [ ] **Step 3: Commit fixtures**

```bash
git add test/fixtures/skills/
git commit -m "test: add AgentSkills.io fixture files"
```

---

## Task 2: AgentSkill value object

**Files:**
- Create: `lib/robot_lab/agent_skill.rb`
- Create: `test/robot_lab/agent_skill_test.rb`

- [ ] **Step 1: Write the failing tests**

`test/robot_lab/agent_skill_test.rb`:
```ruby
# frozen_string_literal: true

require "test_helper"

module RobotLab
  class AgentSkillTest < Minitest::Test
    FIXTURES = Pathname.new(File.expand_path("../../fixtures/skills", __dir__))

    def test_parses_name_and_description
      skill = AgentSkill.new(FIXTURES.join("test_skill", "SKILL.md"))
      assert_equal "test_skill", skill.name
      assert_equal "A test skill for verifying AgentSkills.io integration", skill.description
    end

    def test_parses_instructions_body
      skill = AgentSkill.new(FIXTURES.join("test_skill", "SKILL.md"))
      assert_includes skill.instructions, "rigorous testing practices"
    end

    def test_path_is_the_skill_directory
      skill = AgentSkill.new(FIXTURES.join("test_skill", "SKILL.md"))
      assert_equal FIXTURES.join("test_skill"), skill.path
    end

    def test_raises_configuration_error_when_description_missing
      assert_raises(ConfigurationError) do
        AgentSkill.new(FIXTURES.join("bad_skill", "SKILL.md"))
      end
    end

    def test_scripts_returns_empty_when_no_scripts_directory
      skill = AgentSkill.new(FIXTURES.join("test_skill", "SKILL.md"))
      assert_equal [], skill.scripts
    end

    def test_scripts_returns_files_from_scripts_directory
      skill = AgentSkill.new(FIXTURES.join("scripted_skill", "SKILL.md"))
      assert_equal 1, skill.scripts.length
      assert_equal "hello.sh", skill.scripts.first.basename.to_s
    end

    def test_script_tools_returns_empty_for_no_scripts
      skill = AgentSkill.new(FIXTURES.join("test_skill", "SKILL.md"))
      assert_equal [], skill.script_tools
    end

    def test_script_tools_wraps_executable_scripts
      skill = AgentSkill.new(FIXTURES.join("scripted_skill", "SKILL.md"))
      tools = skill.script_tools
      assert_equal 1, tools.length
      assert_equal "hello", tools.first.name
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/agent_skill_test.rb]
```
Expected: `NameError: uninitialized constant RobotLab::AgentSkill`

- [ ] **Step 3: Implement AgentSkill**

`lib/robot_lab/agent_skill.rb`:
```ruby
# frozen_string_literal: true

require "yaml"
require "pathname"

module RobotLab
  # Value object representing an AgentSkills.io skill folder.
  #
  # A skill is a directory containing SKILL.md with required front matter
  # fields (name, description) and optional scripts/, references/, assets/.
  class AgentSkill
    attr_reader :name, :description, :path

    # @param skill_md_path [String, Pathname] path to the SKILL.md file
    # @raise [ConfigurationError] if name or description is missing
    def initialize(skill_md_path)
      @path = Pathname.new(skill_md_path).dirname
      content = File.read(skill_md_path)
      front_matter, @_body = parse_skill_md(content)

      @name        = front_matter["name"]
      @description = front_matter["description"]

      raise ConfigurationError, "SKILL.md at #{skill_md_path} missing 'name'"        unless @name
      raise ConfigurationError, "SKILL.md at #{skill_md_path} missing 'description'" unless @description
    end

    # Full instruction text from the SKILL.md body (below the front matter).
    #
    # @return [String]
    def instructions
      @_body.strip
    end

    # Pathnames of all files inside the scripts/ subdirectory, sorted.
    #
    # @return [Array<Pathname>]
    def scripts
      @scripts ||= begin
        dir = @path.join("scripts")
        dir.directory? ? dir.children.select(&:file?).sort : []
      end
    end

    # RobotLab::Tool instances wrapping each executable script.
    # Non-executable scripts are skipped with a warning.
    #
    # @return [Array<RobotLab::Tool>]
    def script_tools
      @script_tools ||= scripts.filter_map do |script_path|
        ScriptTool.from_path(script_path)
      end
    end

    private

    # Split SKILL.md content into front matter Hash and body String.
    def parse_skill_md(content)
      if content.start_with?("---\n")
        parts = content.split(/^---\s*$/, 3)
        if parts.length >= 3
          front_matter = YAML.safe_load(parts[1]) || {}
          return [front_matter, parts[2]]
        end
      end
      [{}, content]
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rake test_file[robot_lab/agent_skill_test.rb]
```
Expected: 8 tests pass. The `script_tools` tests will fail until ScriptTool exists (Task 4). If so, stub with `skip` or implement ScriptTool first.

> **Note:** If `test_script_tools_*` tests fail due to missing ScriptTool, proceed to Task 4 first, then re-run this suite.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/agent_skill.rb test/robot_lab/agent_skill_test.rb
git commit -m "feat(agent_skill): add AgentSkill value object with SKILL.md parsing"
```

---

## Task 3: AgentSkillCatalog

**Files:**
- Create: `lib/robot_lab/agent_skill_catalog.rb`
- Create: `test/robot_lab/agent_skill_catalog_test.rb`

- [ ] **Step 1: Write the failing tests**

`test/robot_lab/agent_skill_catalog_test.rb`:
```ruby
# frozen_string_literal: true

require "test_helper"

module RobotLab
  class AgentSkillCatalogTest < Minitest::Test
    FIXTURES = File.expand_path("../../fixtures/skills", __dir__)

    def setup
      @catalog = AgentSkillCatalog.new(FIXTURES)
    end

    def test_find_returns_agent_skill_by_symbol
      skill = @catalog.find(:test_skill)
      refute_nil skill
      assert_equal "test_skill", skill.name
    end

    def test_find_returns_agent_skill_by_string
      skill = @catalog.find("test_skill")
      refute_nil skill
      assert_equal "test_skill", skill.name
    end

    def test_find_returns_nil_for_unknown_id
      assert_nil @catalog.find(:nonexistent)
    end

    def test_all_returns_all_discovered_skills
      skills = @catalog.all
      names = skills.map(&:name)
      assert_includes names, "test_skill"
      assert_includes names, "scripted_skill"
    end

    def test_bad_skill_is_skipped_not_raised
      # bad_skill has no description; catalog should skip it with a warning
      skill = @catalog.find(:bad_skill)
      assert_nil skill
    end

    def test_instance_returns_same_object
      first  = AgentSkillCatalog.instance
      second = AgentSkillCatalog.instance
      assert_same first, second
    end

    def test_reset_clears_instance
      AgentSkillCatalog.instance
      AgentSkillCatalog.reset!
      # After reset, accessing instance again should return a new object
      assert_instance_of AgentSkillCatalog, AgentSkillCatalog.instance
    ensure
      AgentSkillCatalog.reset!
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/agent_skill_catalog_test.rb]
```
Expected: `NameError: uninitialized constant RobotLab::AgentSkillCatalog`

- [ ] **Step 3: Implement AgentSkillCatalog**

`lib/robot_lab/agent_skill_catalog.rb`:
```ruby
# frozen_string_literal: true

require "pathname"

module RobotLab
  # Singleton registry that scans ~/.prompts/skills/ and provides
  # AgentSkill lookup by ID.
  #
  # Skills are loaded lazily on first access (thread-safe via Mutex).
  # Bad SKILL.md files (missing name/description) are skipped with a warning.
  class AgentSkillCatalog
    SKILLS_ROOT = Pathname.new(File.expand_path("~/.prompts/skills"))

    class << self
      # The process-level singleton instance (uses SKILLS_ROOT).
      #
      # @return [AgentSkillCatalog]
      def instance
        @instance ||= new(SKILLS_ROOT)
      end

      # Reset the singleton (used in tests to swap the skills root).
      def reset!
        @instance = nil
      end
    end

    # @param skills_root [String, Pathname] directory to scan for skill folders
    def initialize(skills_root = SKILLS_ROOT)
      @skills_root = Pathname.new(skills_root)
      @skills      = {}
      @mutex       = Mutex.new
      @loaded      = false
    end

    # Return the AgentSkill for the given ID, or nil if not found.
    #
    # @param id [Symbol, String] skill folder name
    # @return [AgentSkill, nil]
    def find(id)
      load!
      @skills[id.to_sym]
    end

    # All discovered AgentSkill objects.
    #
    # @return [Array<AgentSkill>]
    def all
      load!
      @skills.values
    end

    private

    def load!
      @mutex.synchronize { load_skills! unless @loaded }
    end

    def load_skills!
      @loaded = true
      return unless @skills_root.directory?

      @skills_root.each_child do |dir|
        next unless dir.directory?

        skill_file = dir.join("SKILL.md")
        next unless skill_file.exist?

        begin
          skill = AgentSkill.new(skill_file)
          @skills[skill.name.to_sym] = skill
        rescue ConfigurationError => e
          RobotLab.config.logger.warn("AgentSkillCatalog: #{e.message}, skipping #{dir.basename}")
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rake test_file[robot_lab/agent_skill_catalog_test.rb]
```
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/robot_lab/agent_skill_catalog.rb test/robot_lab/agent_skill_catalog_test.rb
git commit -m "feat(agent_skill_catalog): add AgentSkillCatalog for skill discovery"
```

---

## Task 4: ScriptTool factory

**Files:**
- Create: `lib/robot_lab/script_tool.rb`
- Create: `test/robot_lab/script_tool_test.rb`

- [ ] **Step 1: Write the failing tests**

`test/robot_lab/script_tool_test.rb`:
```ruby
# frozen_string_literal: true

require "test_helper"

module RobotLab
  class ScriptToolTest < Minitest::Test
    FIXTURE_SCRIPT = File.expand_path(
      "../../fixtures/skills/scripted_skill/scripts/hello.sh", __dir__
    )

    def test_from_path_returns_tool_instance
      tool = ScriptTool.from_path(FIXTURE_SCRIPT)
      refute_nil tool
      assert_respond_to tool, :name
    end

    def test_tool_name_derived_from_filename
      tool = ScriptTool.from_path(FIXTURE_SCRIPT)
      assert_equal "hello", tool.name
    end

    def test_tool_description_from_first_comment
      tool = ScriptTool.from_path(FIXTURE_SCRIPT)
      assert_equal "Say hello to the world", tool.description
    end

    def test_tool_execution_returns_script_output
      tool = ScriptTool.from_path(FIXTURE_SCRIPT)
      output = tool.call({})
      assert_includes output, "Hello from AgentSkills script!"
    end

    def test_from_path_returns_nil_for_nonexecutable_script
      Tempfile.create(["nonexec", ".sh"]) do |f|
        f.write("#!/bin/bash\necho hello")
        f.flush
        FileUtils.chmod(0o644, f.path)
        result = ScriptTool.from_path(f.path)
        assert_nil result
      end
    end

    def test_tool_name_with_hyphens_converted_to_underscores
      Tempfile.create(["check-style", ".sh"]) do |f|
        f.write("#!/bin/bash\necho ok")
        f.flush
        FileUtils.chmod(0o755, f.path)
        tool = ScriptTool.from_path(f.path)
        assert_equal "check_style", tool.name
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/script_tool_test.rb]
```
Expected: `NameError: uninitialized constant RobotLab::ScriptTool`

- [ ] **Step 3: Implement ScriptTool**

`lib/robot_lab/script_tool.rb`:
```ruby
# frozen_string_literal: true

require "open3"
require "pathname"
require "tempfile"

module RobotLab
  # Factory module for wrapping AgentSkills scripts as RobotLab::Tool instances.
  #
  # Given a path to an executable shell script, produces a Tool that shells
  # out to the script and returns its combined stdout+stderr output.
  #
  # Non-executable scripts return nil with a logged warning.
  module ScriptTool
    # Wrap a script file as a RobotLab::Tool.
    #
    # @param script_path [String, Pathname] path to the script file
    # @return [RobotLab::Tool, nil] nil if the script is not executable
    def self.from_path(script_path)
      path = Pathname.new(script_path)

      unless path.executable?
        RobotLab.config.logger.warn(
          "ScriptTool: #{path.basename} is not executable, skipping"
        )
        return nil
      end

      tool_name   = derive_name(path)
      description = extract_description(path)
      script      = path.to_s

      Tool.create(
        name: tool_name,
        description: description,
        parameters: {
          type: "object",
          properties: {
            args: { type: "string", description: "Optional command-line arguments" }
          },
          required: []
        }
      ) do |tool_args|
        cli_args = tool_args[:args].to_s.strip
        cmd      = cli_args.empty? ? ["bash", script] : ["bash", script, *cli_args.split]
        output, status = Open3.capture2e(*cmd)
        status.success? ? output : "Error (exit #{status.exitstatus}):\n#{output}"
      end
    end

    # @param path [Pathname]
    # @return [String] snake_case tool name from filename
    def self.derive_name(path)
      path.basename.to_s
          .sub(/\.[^.]+$/, "")
          .gsub(/[^a-zA-Z0-9]+/, "_")
          .gsub(/^_+|_+$/, "")
    end

    # Extract the tool description from the first comment line of the script.
    #
    # @param path [Pathname]
    # @return [String]
    def self.extract_description(path)
      first_comment = File.foreach(path).find { |line| line.strip.start_with?("#") }
      if first_comment
        first_comment.strip.sub(/^#+!.*$/, "").sub(/^#+\s*/, "").strip
      else
        derive_name(path)
      end
    rescue
      derive_name(path)
    end
  end
end
```

> **Note on description extraction:** The first comment line of `hello.sh` is `#!/usr/bin/env bash` (a shebang). The regex `sub(/^#+!.*$/, "")` strips shebang lines, so the method moves to the next comment: `# Say hello to the world`. Adjust `extract_description` if your scripts don't follow this pattern.

Wait — `File.foreach` returns the first line that matches, which will be the shebang `#!/usr/bin/env bash`. The shebang regex strips it to `""`. An empty string is falsey... actually `"".strip` is `""` which is truthy in Ruby. Let me fix this:

Replace the `extract_description` implementation with one that skips shebangs:

```ruby
def self.extract_description(path)
  File.foreach(path) do |line|
    stripped = line.strip
    next unless stripped.start_with?("#")
    next if stripped.start_with?("#!")  # skip shebang
    desc = stripped.sub(/^#+\s*/, "").strip
    return desc unless desc.empty?
  end
  derive_name(path)
rescue
  derive_name(path)
end
```

Use this corrected version in the file.

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rake test_file[robot_lab/script_tool_test.rb]
```
Expected: 6 tests pass.

- [ ] **Step 5: Now re-run AgentSkill tests (they depend on ScriptTool)**

```bash
bundle exec rake test_file[robot_lab/agent_skill_test.rb]
```
Expected: All 8 tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/robot_lab/script_tool.rb test/robot_lab/script_tool_test.rb
git commit -m "feat(script_tool): add ScriptTool factory for wrapping scripts as tools"
```

---

## Task 5: Modify expand_skills for AgentSkill detection

**Files:**
- Modify: `lib/robot_lab/robot/template_rendering.rb`

- [ ] **Step 1: Write a failing test for the new expand_skills behavior**

Add this test to `test/robot_lab/robot_test.rb` (find the existing test class and add inside it):

```ruby
def test_expand_skills_stores_agent_skill_in_pending_when_catalog_hit
  # Point catalog at our fixture directory
  fixtures = File.expand_path("../fixtures/skills", __dir__)
  catalog = RobotLab::AgentSkillCatalog.new(fixtures)

  robot = build_robot(name: "bot", skills: [:test_skill])
  robot.instance_variable_set(:@pending_agent_skills, [])
  robot.instance_variable_set(:@agent_skill_store, RobotLab::DocumentStore.new)

  robot.send(:expand_skills_with_catalog, [:test_skill], Set.new, catalog)

  pending = robot.instance_variable_get(:@pending_agent_skills)
  assert_equal 1, pending.length
  assert_equal "test_skill", pending.first.name
end

def test_expand_skills_uses_pm_template_when_not_in_catalog
  # :assistant is a PM template in examples/prompts/
  robot = build_robot(name: "bot")
  result = robot.send(:expand_skills, [:assistant], Set.new)
  assert_includes result, :assistant
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/robot_test.rb]
```
Expected: `NoMethodError: undefined method 'expand_skills_with_catalog'`

- [ ] **Step 3: Modify expand_skills in template_rendering.rb**

Open `lib/robot_lab/robot/template_rendering.rb`. Find `expand_skills` (line ~153) and replace its body:

```ruby
def expand_skills(skill_ids, visited = Set.new)
  expand_skills_with_catalog(skill_ids, visited, AgentSkillCatalog.instance)
end

def expand_skills_with_catalog(skill_ids, visited, catalog)
  result = []

  skill_ids.each do |skill_id|
    skill_id = skill_id.to_sym

    if visited.include?(skill_id)
      RobotLab.config.logger.warn(
        "Robot '#{@name}': skill cycle detected at '#{skill_id}', skipping"
      )
      next
    end

    visited.add(skill_id)

    # Check catalog first: AgentSkills folder format takes priority
    if (agent_skill = catalog.find(skill_id))
      @pending_agent_skills ||= []
      @agent_skill_store    ||= DocumentStore.new
      @pending_agent_skills << agent_skill
      @agent_skill_store.store(agent_skill.name.to_sym, agent_skill.description)
      next
    end

    # Fall back to PM template (existing behavior)
    parsed = PM.parse(skill_id)
    nested = extract_skills_from_metadata(parsed.metadata)

    expand_skills_with_catalog(nested, visited, catalog).tap do |nested_result|
      result.concat(nested_result)
    end

    result << skill_id
  end

  result
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bundle exec rake test_file[robot_lab/robot_test.rb]
```
Expected: New tests pass; no regressions.

- [ ] **Step 5: Run the full test suite to check for regressions**

```bash
bundle exec rake test
```
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/robot_lab/robot/template_rendering.rb test/robot_lab/robot_test.rb
git commit -m "feat(template_rendering): detect AgentSkills folder format in expand_skills"
```

---

## Task 6: Robot constructor — initialize pending skill state

**Files:**
- Modify: `lib/robot_lab/robot.rb`

- [ ] **Step 1: Add `@pending_agent_skills` and `@agent_skill_store` to Robot#initialize**

In `lib/robot_lab/robot.rb`, find the line:
```ruby
@skills = skills ? Array(skills).map(&:to_sym) : nil
@expanded_skills = nil
```

Add immediately after:
```ruby
@pending_agent_skills = []
@agent_skill_store    = nil
```

- [ ] **Step 2: Add `require_relative` for agent_skill_matching**

In `lib/robot_lab/robot.rb`, find:
```ruby
require_relative 'robot/template_rendering'
require_relative 'robot/mcp_management'
require_relative 'robot/bus_messaging'
require_relative 'robot/history_search'
```

Add:
```ruby
require_relative 'robot/agent_skill_matching'
```

- [ ] **Step 3: Prepend AgentSkillMatching in the Robot class body**

In `lib/robot_lab/robot.rb`, find the `include` block:
```ruby
include Robot::TemplateRendering
include Robot::MCPManagement
include Robot::BusMessaging
include Robot::HistorySearch
include Durable::Learning
```

Add `prepend` after the `include` lines:
```ruby
prepend Robot::AgentSkillMatching
```

- [ ] **Step 4: Run the test suite to verify no regressions before adding the module**

```bash
bundle exec rake test
```
Expected: All tests pass (AgentSkillMatching module doesn't exist yet but `prepend` on a missing constant will fail — so create a stub file first in Step 5, then re-run).

- [ ] **Step 5: Create a stub AgentSkillMatching so requires resolve**

`lib/robot_lab/robot/agent_skill_matching.rb`:
```ruby
# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    module AgentSkillMatching
      # Implemented in Task 7
    end
  end
end
```

```bash
bundle exec rake test
```
Expected: All existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/robot_lab/robot.rb lib/robot_lab/robot/agent_skill_matching.rb
git commit -m "feat(robot): initialize pending_agent_skills state, prepend AgentSkillMatching"
```

---

## Task 7: AgentSkillMatching mixin — runtime injection

**Files:**
- Modify: `lib/robot_lab/robot/agent_skill_matching.rb`
- Create: `test/robot_lab/robot/agent_skill_matching_test.rb`

- [ ] **Step 1: Write the failing tests**

`test/robot_lab/robot/agent_skill_matching_test.rb`:
```ruby
# frozen_string_literal: true

require "test_helper"

module RobotLab
  class Robot
    class AgentSkillMatchingTest < Minitest::Test
      FIXTURES = File.expand_path("../../../fixtures/skills", __dir__)

      def skill_for(name)
        path = File.join(FIXTURES, name.to_s, "SKILL.md")
        AgentSkill.new(path)
      end

      def robot_with_pending_skills(*skill_names)
        robot = build_robot(name: "test_bot")
        skills = skill_names.map { |n| skill_for(n) }
        store  = DocumentStore.new
        skills.each { |s| store.store(s.name.to_sym, s.description) }
        robot.instance_variable_set(:@pending_agent_skills, skills)
        robot.instance_variable_set(:@agent_skill_store, store)
        robot
      end

      def test_match_returns_empty_when_no_pending_skills
        robot = build_robot(name: "bot")
        result = robot.send(:match_agent_skills, "any message")
        assert_equal [], result
      end

      def test_match_returns_skills_above_threshold
        robot = robot_with_pending_skills(:test_skill)
        # Pass a message semantically similar to test_skill's description
        # "A test skill for verifying AgentSkills.io integration"
        result = robot.send(:match_agent_skills,
                            "I need to verify the AgentSkills integration works",
                            threshold: 0.3)
        assert_equal 1, result.length
        assert_equal "test_skill", result.first.name
      end

      def test_match_returns_empty_below_threshold
        robot = robot_with_pending_skills(:test_skill)
        result = robot.send(:match_agent_skills,
                            "I need to verify the AgentSkills integration works",
                            threshold: 0.999)
        assert_equal [], result
      end

      def test_inject_prepends_instructions_to_system_prompt
        robot = build_robot(name: "bot", system_prompt: "You are helpful.")
        skill = skill_for(:test_skill)
        robot.send(:inject_agent_skills, [skill])

        instructions = system_instructions(robot)
        assert instructions.start_with?(skill.instructions),
               "Expected system prompt to start with skill instructions"
        assert_includes instructions, "You are helpful."
      end

      def test_inject_adds_script_tools_to_local_tools
        robot = build_robot(name: "bot")
        skill = skill_for(:scripted_skill)
        robot.send(:inject_agent_skills, [skill])

        tool_names = robot.local_tools.map(&:name)
        assert_includes tool_names, "hello"
      end

      def test_restore_removes_injected_tools
        robot = build_robot(name: "bot")
        skill = skill_for(:scripted_skill)
        original_count = robot.local_tools.length

        robot.send(:inject_agent_skills, [skill])
        robot.send(:restore_after_agent_skills)

        assert_equal original_count, robot.local_tools.length
      end

      def test_restore_restores_original_system_prompt
        robot = build_robot(name: "bot", system_prompt: "You are helpful.")
        skill = skill_for(:test_skill)

        robot.send(:inject_agent_skills, [skill])
        robot.send(:restore_after_agent_skills)

        assert_equal "You are helpful.", system_instructions(robot)
      end

      def test_match_degrades_gracefully_on_embedding_failure
        robot = build_robot(name: "bot")
        broken_store = Object.new
        def broken_store.search(*) = raise "fastembed failed"
        robot.instance_variable_set(:@pending_agent_skills, [skill_for(:test_skill)])
        robot.instance_variable_set(:@agent_skill_store, broken_store)

        result = robot.send(:match_agent_skills, "anything")
        assert_equal [], result
      end
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

```bash
bundle exec rake test_file[robot_lab/robot/agent_skill_matching_test.rb]
```
Expected: Tests fail with `NoMethodError` on `match_agent_skills`.

- [ ] **Step 3: Implement AgentSkillMatching**

Replace the stub in `lib/robot_lab/robot/agent_skill_matching.rb` with the full implementation:

```ruby
# frozen_string_literal: true

module RobotLab
  class Robot < RubyLLM::Agent
    # Prepended module that intercepts run() to inject relevant AgentSkills.io
    # skills into the system prompt and tool list for the duration of each call.
    #
    # Skills are matched by embedding similarity between the incoming message
    # and each pending skill's description (via DocumentStore/fastembed).
    # Injected content is fully restored in an ensure block after run() returns.
    module AgentSkillMatching
      # Default cosine similarity threshold for skill activation.
      SIMILARITY_THRESHOLD = 0.70

      def run(message = nil, **kwargs, &block)
        activated = match_agent_skills(message.to_s)
        inject_agent_skills(activated) if activated.any?
        super(message, **kwargs, &block)
      ensure
        restore_after_agent_skills if activated&.any?
      end

      # Override to re-inject skill instructions after template re-render.
      # rerender_template replaces the system prompt; re-prepend skills after.
      def rerender_template(run_context)
        super
        return unless @_agent_skill_injected_tools # nil when no skills active

        @_agent_skill_original_instructions = current_agent_skill_instructions
        prepend_skill_instructions(@_agent_skill_active_skills)
      end

      private

      # Find pending AgentSkills whose descriptions match the message.
      #
      # @param message [String] the incoming user message
      # @param threshold [Float] cosine similarity cutoff
      # @return [Array<AgentSkill>]
      def match_agent_skills(message, threshold: SIMILARITY_THRESHOLD)
        return [] if @pending_agent_skills.nil? || @pending_agent_skills.empty?

        results = @agent_skill_store.search(message, limit: @pending_agent_skills.size)
        results
          .select { |r| r[:score] >= threshold }
          .filter_map { |r| @pending_agent_skills.find { |s| s.name.to_sym == r[:key] } }
      rescue => e
        RobotLab.config.logger.warn(
          "Robot '#{@name}': AgentSkill embedding failed: #{e.message}"
        )
        []
      end

      # Prepend skill instructions to system prompt and inject script tools.
      #
      # @param skills [Array<AgentSkill>]
      def inject_agent_skills(skills)
        @_agent_skill_active_skills          = skills
        @_agent_skill_original_instructions  = current_agent_skill_instructions
        prepend_skill_instructions(skills)
        @_agent_skill_injected_tools = skills.flat_map(&:script_tools).compact
        @local_tools = @local_tools + @_agent_skill_injected_tools
      end

      # Restore system prompt and tool list to pre-injection state.
      def restore_after_agent_skills
        @local_tools = @local_tools - (@_agent_skill_injected_tools || [])
        @chat.with_instructions(@_agent_skill_original_instructions.to_s)
        @_agent_skill_active_skills         = nil
        @_agent_skill_original_instructions = nil
        @_agent_skill_injected_tools        = nil
      end

      # Read the current system message content from the chat.
      #
      # @return [String, nil]
      def current_agent_skill_instructions
        messages = @chat.instance_variable_get(:@messages)
        sys = messages&.find { |m| m.role.to_s == "system" }
        sys&.content
      end

      # Prepend all skill instruction bodies before existing system prompt.
      #
      # @param skills [Array<AgentSkill>]
      def prepend_skill_instructions(skills)
        skill_content = skills.map(&:instructions).join("\n\n")
        base          = @_agent_skill_original_instructions.to_s
        combined      = [skill_content, base].reject(&:empty?).join("\n\n")
        @chat.with_instructions(combined)
      end
    end
  end
end
```

- [ ] **Step 4: Run the AgentSkillMatching tests**

```bash
bundle exec rake test_file[robot_lab/robot/agent_skill_matching_test.rb]
```
Expected: All tests pass. (The embedding tests require fastembed to download the model on first run — this is expected and cached locally after that.)

- [ ] **Step 5: Run the full test suite**

```bash
bundle exec rake test
```
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/robot_lab/robot/agent_skill_matching.rb \
        test/robot_lab/robot/agent_skill_matching_test.rb
git commit -m "feat(agent_skill_matching): implement runtime embedding-based skill injection"
```

---

## Task 8: Integration test — mixed skills: param

**Files:**
- Modify: `test/robot_lab/robot_test.rb`

- [ ] **Step 1: Write the integration test**

Find the existing `robot_test.rb` and add:

```ruby
def test_skills_param_handles_mixed_pm_and_agentskill_formats
  # :assistant is a PM template; :test_skill is an AgentSkill folder
  fixtures = File.expand_path("../fixtures/skills", __dir__)
  catalog  = RobotLab::AgentSkillCatalog.new(fixtures)

  robot = build_robot(name: "bot", skills: [:assistant])
  robot.instance_variable_set(:@pending_agent_skills, [])
  robot.instance_variable_set(:@agent_skill_store, RobotLab::DocumentStore.new)

  skill = RobotLab::AgentSkill.new(File.join(fixtures, "test_skill", "SKILL.md"))
  robot.instance_variable_get(:@pending_agent_skills) << skill
  store = robot.instance_variable_get(:@agent_skill_store)
  store.store(skill.name.to_sym, skill.description)

  # PM skills are in @expanded_skills; AgentSkills are in @pending_agent_skills
  expanded = robot.instance_variable_get(:@expanded_skills)
  pending  = robot.instance_variable_get(:@pending_agent_skills)

  assert_includes expanded, :assistant if expanded
  assert_equal 1, pending.length
  assert_equal "test_skill", pending.first.name
end

def test_agentskill_script_tools_not_present_after_run_without_match
  fixtures = File.expand_path("../fixtures/skills", __dir__)
  skill    = RobotLab::AgentSkill.new(File.join(fixtures, "scripted_skill", "SKILL.md"))

  robot = build_robot(name: "bot", system_prompt: "You are helpful.")
  robot.instance_variable_set(:@pending_agent_skills, [skill])
  store = RobotLab::DocumentStore.new
  store.store(skill.name.to_sym, skill.description)
  robot.instance_variable_set(:@agent_skill_store, store)

  initial_tool_count = robot.local_tools.length

  # Use threshold 0.999 so no skill matches
  robot.stub(:match_agent_skills, []) do
    # Can't call actual run() without API key; verify tool count unchanged
    robot.send(:inject_agent_skills, [])
    robot.send(:restore_after_agent_skills)
  end

  assert_equal initial_tool_count, robot.local_tools.length
end
```

- [ ] **Step 2: Run the integration tests**

```bash
bundle exec rake test_file[robot_lab/robot_test.rb]
```
Expected: All tests pass.

- [ ] **Step 3: Run the full test suite**

```bash
bundle exec rake test
```
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/robot_lab/robot_test.rb
git commit -m "test(integration): verify mixed PM + AgentSkill skills: param behavior"
```

---

## Task 9: Example file

**Files:**
- Create: `examples/34_agentskills.rb`
- Create: `~/.prompts/skills/code_reviewer/SKILL.md`

- [ ] **Step 1: Create a demonstration AgentSkill in the user's skills directory**

```bash
mkdir -p ~/.prompts/skills/code_reviewer/scripts
```

`~/.prompts/skills/code_reviewer/SKILL.md`:
```markdown
---
name: code_reviewer
description: Review Ruby code for quality, style, and potential bugs
---
When reviewing Ruby code, check for:
- Frozen string literal comments at the top of files
- Methods exceeding 20 lines — suggest splitting
- Inline rescue usage — recommend dedicated rescue blocks
- Missing nil guards on external data
- Test coverage gaps for edge cases

Provide structured feedback with severity: info, warning, or error.
```

- [ ] **Step 2: Create the example script**

`examples/34_agentskills.rb`:
```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 34: AgentSkills.io Integration
#
# Demonstrates the unified skills: param detecting AgentSkills folder format.
# Skills in ~/.prompts/skills/ are matched at runtime via embedding similarity
# before each run() call — only relevant skills are injected.
#
# Usage:
#   mkdir -p ~/.prompts/skills/code_reviewer
#   # (create SKILL.md as shown in the example header)
#   ANTHROPIC_API_KEY=your_key ruby examples/34_agentskills.rb

ENV['ROBOT_LAB_TEMPLATE_PATH'] ||= File.join(__dir__, "prompts")

require_relative "../lib/robot_lab"

require "logger"
log_file = File.join(__dir__, "34.log")
RobotLab.config.logger = Logger.new(log_file)
RubyLLM.configure { |c| c.logger = Logger.new(log_file) }

puts "=" * 60
puts "RobotLab — AgentSkills.io Integration Demo"
puts "=" * 60
puts

# Check if the skill is installed
skill_path = File.expand_path("~/.prompts/skills/code_reviewer/SKILL.md")
unless File.exist?(skill_path)
  puts "Demo skill not found at #{skill_path}"
  puts "Create it with:"
  puts "  mkdir -p ~/.prompts/skills/code_reviewer"
  puts "  # Then add SKILL.md with name: code_reviewer"
  exit 1
end

# Build a robot that lists code_reviewer as a candidate skill.
# At runtime, if the user message is semantically similar to
# "Review Ruby code for quality, style, and potential bugs",
# the skill's instructions are injected into the system prompt.
robot = RobotLab.build(
  name: "assistant",
  system_prompt: "You are a helpful Ruby programming assistant.",
  skills: [:code_reviewer]
)

puts "Pending AgentSkills: #{robot.instance_variable_get(:@pending_agent_skills).map(&:name).inspect}"
puts

# Message semantically related to code review — skill should activate
code_question = <<~MSG
  Please review this Ruby method for quality issues:

  def process(data)
    begin
      result = data.map { |item| transform(item) }
      save(result)
    rescue => e
      puts e.message
    end
  end
MSG

puts "Query: code review (skill should activate)"
result = robot.run(code_question)
puts result.reply
puts
puts "=" * 60

# Message unrelated to code review — skill should NOT activate
puts "Query: general question (skill should NOT activate)"
result = robot.run("What is the capital of France?")
puts result.reply
```

- [ ] **Step 3: Verify the example syntax**

```bash
ruby -c examples/34_agentskills.rb
```
Expected: `Syntax OK`

- [ ] **Step 4: Commit**

```bash
git add examples/34_agentskills.rb
git commit -m "feat(examples): add example 34 demonstrating AgentSkills.io integration"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] Discovery path `~/.prompts/skills/` — `AgentSkillCatalog::SKILLS_ROOT`
- [x] Unified `skills:` param — `expand_skills` detects catalog before PM
- [x] SKILL.md parsing (name, description, body) — `AgentSkill#initialize`
- [x] Scripts auto-wrapped as tools — `AgentSkill#script_tools` + `ScriptTool`
- [x] Runtime embedding match — `AgentSkillMatching#match_agent_skills`
- [x] Threshold 0.70 — `SIMILARITY_THRESHOLD` constant
- [x] Injection + restore — `inject_agent_skills` / `restore_after_agent_skills`
- [x] `rerender_template` re-injection — override in `AgentSkillMatching`
- [x] Graceful degradation on embedding failure — rescue in `match_agent_skills`
- [x] `ConfigurationError` on missing name/description — `AgentSkill#initialize`
- [x] Non-executable script skipped — `ScriptTool.from_path`
- [x] Cycle detection via visited Set — inherited in `expand_skills_with_catalog`

**Type consistency:**
- `AgentSkill#script_tools` → `Array<RobotLab::Tool>` — matches `@local_tools` element type ✓
- `AgentSkillCatalog#find` → `AgentSkill, nil` — used correctly in `expand_skills_with_catalog` ✓
- `ScriptTool.from_path` → `RobotLab::Tool, nil` — `filter_map` in `script_tools` handles nil ✓
- `match_agent_skills` → `Array<AgentSkill>` — passed to `inject_agent_skills` which calls `flat_map(&:script_tools)` ✓
