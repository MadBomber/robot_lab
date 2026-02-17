# Writers' Room Output

This directory contains the creative works produced by the Writers' Room
self-organizing robot teams (Demo 16). No human wrote any of the prose,
outlines, or screenplay content — it all emerged from robots coordinating
through bus messages and shared memory.

## The Works

### opus_001.md — First Book

The first novella ever produced by the Writers' Room. A team of writer
robots self-organized to create a 10-chapter science fiction story. They
discussed the premise, built a story bible, outlined the plot, claimed
chapters, and wrote them — all without orchestration or assigned roles.

`opus_001_notes.log` contains the session log from that run.

### opus_002.md — Second Book

The second novella produced by the Writers' Room. Same process, same
self-organizing pattern, different story.

`opus_002_notes.log` contains the session log.

### opus_002_screenplay.md — First Screenplay

The first screenplay the robots ever created. After opus_002 was written,
the Writers' Room was extended with a screenplay mode that adapts a
finished book into a 4-act made-for-TV movie pilot.

The workflow:

1. Book mode runs and produces a novella (opus_002.md)
2. Book mode also dumps all creative artifacts (story bible, outline,
   chapters) to `memory.json`
3. Screenplay mode is launched with `--screenplay-from memory.json`,
   which reloads that memory into the room before the screenwriters start
4. The screenwriters read the source material, discuss adaptation choices,
   build a scene outline, and write individual scenes in standard
   screenplay format

```bash
# Step 1: Write the book (memory.json is saved automatically)
bundle exec ruby examples/16_writers_room/writers_room.rb

# Step 2: Adapt it to a screenplay
bundle exec ruby examples/16_writers_room/writers_room.rb \
  --screenplay-from examples/16_writers_room/output/memory.json
```

Screenplay writers work at the scene level — each robot claims and writes
individual scenes rather than entire acts. They maintain a `scene_registry`
in shared memory listing all planned scenes, and can drop or reorder
scenes as the adaptation takes shape. When unclaimed scenes pile up, the
robots spawn additional writers to help.

`opus_002_screenplay_notes.md` is the log of the robots discussing the
screenplay adaptation process — debating what to keep, what to cut, how
to restructure the story for screen, and how to handle act breaks.

## Working Files

These files are generated each run and git-ignored:

- `book.md` — latest book mode output
- `screenplay.md` — latest screenplay mode output
- `memory.json` — memory dump from the latest book mode run
- `room.log` — structured log from the Room (timestamps, tool calls, heartbeats)
