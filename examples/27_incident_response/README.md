# Example 27: Production Incident War Room

A simulated payment-service outage, used to demonstrate RobotLab's Phase 5
infrastructure features: **reactive memory**, **BusPoller serialized
delivery**, and **poller groups**.

## What it does

A network runs four robots against one incident ("elevated HTTP 500s, p99
latency spiked to 8s"):

- **Three SRE scouts** (`db_scout`, `net_scout`, `app_scout`) investigate the
  database, network, and application layers in parallel. Each makes one LLM
  call, writes its two-sentence finding to shared **reactive memory**
  (`:db_finding`, `:net_finding`, `:app_finding`), and broadcasts a status
  line to the war room over TypedBus.
- **The war room** receives those bus messages through **BusPoller**, which
  serializes delivery — if two scouts finish at the same instant, their
  updates queue and are processed one at a time, in arrival order, with no
  re-entrancy and nothing dropped.
- **The incident commander** depends on all three scouts and blocks on
  `memory.get(:db_finding, :net_finding, :app_finding, wait: 60)` — an
  IO.pipe-backed waiter woken by `IO.select`, so there is no busy-wait and it
  cooperates with Async. When all findings land it makes one synthesis call
  and writes a 3-5 bullet action plan.

Also on display:

- **Poller groups** — the scouts run in `poller_group: :investigation`, the
  commander in `:command`, declared per task on the network.
- **Memory subscriptions** — a `memory.subscribe` callback prints a line as
  each finding is written.
- **Timeout degradation** — `Memory#get(wait:)` raises
  `RobotLab::AwaitTimeout` rather than returning a sentinel; the commander
  rescues it and re-reads without `wait:`, so a slow scout degrades the
  report instead of killing the run.

## How to run

From the gem root (an LM Studio server must be running — `lms server start`;
provider/model come from `examples/common.rb`):

```bash
bundle exec ruby examples/27_incident_response/incident_response.rb
```

Note that `examples/run_all.rb` does **not** include this demo — it only runs
the top-level `NN_*.rb` files, so run it explicitly as above.

The run makes four LLM calls (three scout diagnoses plus the commander's
synthesis), so expect a few minutes on the default local model;
`LLM_PROFILE=small` shortens it.

## Output

- Console: the network graph, each memory write as it happens, the war-room
  updates in BusPoller delivery order, the scouts' findings, and the final
  action plan.
- `output/incident_report.md` — the commander's incident action plan.

## Files

- `incident_response.rb` — the whole demo: `SREScout`, `WarRoom`, and
  `IncidentCommander` robot classes plus network wiring and the run itself
- `output/` — where the incident report is written
