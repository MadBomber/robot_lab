# Example 15: OS Research Editorial Pipeline

A multi-robot editorial pipeline that showcases RobotLab's three coordination
mechanisms — **Network**, **Memory**, and **Bus** — plus dynamic robot
creation with **spawn()**, all in one demo.

## What it does

Three writer robots each advocate for a different operating system (macOS,
Windows, Linux/BSD) as the base for a home AI research lab:

1. **Phase 1 — Writing pipeline (Network + Memory + Spawn).** The network runs
   the three writers in parallel; each stores its draft in shared memory
   (`:mac_draft`, `:windows_draft`, `:linux_draft`). The Linux writer first
   `spawn()`s distro specialists and folds their analyses into its draft. An
   editor robot then synthesizes the drafts into one combined article.
2. **Phase 2 — Editorial review (Bus).** An editor-in-chief robot lives
   *outside* the network and talks to the editor only over the message bus.
   It reviews the article and replies `APPROVED` or `REVISE: <feedback>`,
   looping until approval or `MAX_REVISIONS` (3) is reached.

The demo is lightly interactive: at startup an `AskUser` prompt asks for the
article's research focus. Press Enter to accept the default ("LLM
fine-tuning, image generation, and local inference").

## How to run

From the gem root (an LM Studio server must be running — `lms server start`;
see `examples/common.rb` for the provider/model configuration):

```bash
bundle exec ruby examples/15_memory_network_and_bus/editorial_pipeline.rb
```

Note that `examples/run_all.rb` does **not** include this demo — it only runs
the top-level `NN_*.rb` files, so run it explicitly as above.

This is one of the heavier examples (roughly 20-30 LLM calls). On the default
model expect a long run; `LLM_PROFILE=small` trades answer quality for a much
shorter one:

```bash
LLM_PROFILE=small bundle exec ruby examples/15_memory_network_and_bus/editorial_pipeline.rb
```

## Output

Everything lands in `output/`:

| File | Content |
|------|---------|
| `mac_draft.md`, `windows_draft.md`, `linux_draft.md` | each writer's advocacy draft |
| `combined_article.md` | the editor's synthesis of the three drafts |
| `revision_N.md` | one file per bus-driven revision round |
| `final_article.md` | the approved article (header notes APPROVED or NOT APPROVED) |
| `memory.json` | dump of the shared memory at the end of the run |

## Files

- `editorial_pipeline.rb` — entry point; builds the robots, network, and bus, then runs both phases
- `os_writer.rb` — base writer; runs the LLM and stores its draft in shared memory
- `linux_writer.rb` — extends `OsWriter`; spawns distro specialists before drafting
- `os_editor.rb` — synthesizes drafts; handles revision requests from the bus
- `editor_in_chief.rb` — bus-only reviewer; approves or requests revisions
- `prompts/` — templates for the writers (`os_advocate.md`), editor, and chief
- `.envrc` — sets `ROBOT_LAB_TEMPLATE_PATH` to `prompts/` for direnv users (the script sets the same fallback itself, so direnv is optional)
