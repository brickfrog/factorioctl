# FLE Study (bead factorioctl-q6u) — design note for the agent harness

Research spike studying **Factorio Learning Environment** (FLE) to inform the
remaining `factorioctl-6wk` children (dzx skills, avo journal/reflection, biw
self-verify, fea eval). Sources: github.com/JackHopkins/factorio-learning-environment
(NeurIPS'25, ~1k★, Hopkins/Bakler/Khan; Akbir Khan @ Anthropic), arxiv 2503.09617,
docs at jackhopkins.github.io/factorio-learning-environment (v0.3.0/0.4.x).

## 1. What FLE is

An open-ended LLM benchmark on Factorio. Two settings:
- **lab-play** — bounded throughput tasks with fixed resources (paper: 8 → 24 →
  docs now ~33 across three settings). Tasks are "make 16 X per minute": iron
  plate, iron gear, battery, **red/automation science**, sulfur, plastic bar,
  sulfuric acid, electronic circuits. Gym env ids like `iron_ore_throughput`.
- **open-play** — unbounded "build the largest factory", scored by a
  **production score** (≈ value of items produced/sec), scaling to millions of
  units/sec.

Notably: they **bridged Claude Code into Factorio via FLE and livestreamed it** —
the same idea as this project. v0.3.0 added multi-agency, backtracking agents,
and vision.

## 2. Architecture (the important part)

**Action surface = Python program synthesis via a REPL**, NOT discrete tool calls:
- The agent writes a Python *program* each step; the env executes it, **assigns
  returned values to a persistent namespace**, adds functions/classes to that
  namespace, and returns **stdout/stderr** as the observation.
- Tools are ~30 functions returning **typed objects** reused as variables:
  `place_entity`, `place_entity_next_to`, `pickup_entity`, `rotate_entity`,
  `get_entity`/`get_entities`, `nearest`, `nearest_buildable`,
  `get_resource_patch`, `harvest_resource`, **`connect_entities`** (auto-routes
  belts/pipes/power between two entities — analogous to our `route_belt`),
  `get_connection_amount`, `craft_item`, `get_prototype_recipe`,
  `set_entity_recipe`, `set_research`, `get_research_progress`, `insert_item`,
  `extract_item`, `inspect_inventory`, `move_to`, `sleep`, `launch_rocket`,
  `print`. Returns carry attributes: `drill.drop_position`, `drill.status ==
  EntityStatus.WORKING`.
- Verification idiom is `assert drill.status == EntityStatus.WORKING` then
  `print(get_entities())` and read the output stream.

**Memory = `RecursiveReportFormatter`** (fle/agents/formatters), their context
strategy and the most directly reusable idea for us:
- Compacts every `chunk_size = 16` steps; older chunks → LLM-summarized
  **"historical report"** with fixed sections **"EXISTING STRUCTURES"** and
  **"ERROR TIPS"**; newest 16 messages kept **verbatim**.
- Namespace utility functions are appended to the system message
  (`"# Your utility functions:\n\n" + function_definitions`) — i.e. learned
  procedures persist by being re-injected.
- Stale observations truncated to `<STALE_ENTITY_DATA_OMITTED/>`; hard cap
  `max_chars = 200000`; summaries **SHA-256 cached** to avoid recompute.
- Agent (`fle/agents/gym_agent.py`) parses a `Policy` from the response;
  system prompt stresses long-horizon planning, spatial reasoning, systematic
  automation.

## 3. Findings (where LLMs fail — tells us where to invest)

- **Spatial reasoning is weak** across all models (both settings).
- **Good short-horizon, bad long-horizon / constrained envs**; the headline
  weakness is **error analysis & recovery** — models can't diagnose and adapt.
- Open-play: they discover basic wins (electric-powered drilling) but **fail at
  complex automation (electronic-circuit manufacturing)**.

## 4. How we compare

| Dimension | FLE | factorioctl (us) |
|---|---|---|
| Action surface | Python program synthesis + persistent namespace | discrete MCP tool calls over RCON-Lua |
| Spatial offload | `connect_entities` auto-route; `nearest_buildable` | A* pathing, `route_belt` (zones/underground), `get_machine_belt_positions`, zones — comparable/strong |
| Procedural reuse | namespace functions re-injected | **none yet** (← dzx) |
| Memory | recursive chunked report (STRUCTURES + ERROR TIPS) | ledger (working mem) only (← avo) |
| Verify | typed `entity.status`, assert + stdout | honest feedback, but no production-verify tool (← biw) |
| Eval | lab-play throughput + open-play production score | **none yet** (← fea) |

Our spatial offloading is genuinely competitive; our gaps are exactly the
remaining beads.

## 5. Recommendations per remaining bead

- **dzx (skill library)** — FLE validates "skill = reusable procedure", but they
  get it for free from program-synthesis namespace functions. Since we use
  discrete tool calls, implement a skill as a **named, parameterized macro = an
  ordered sequence of our MCP tool calls** (`build_burner_drill_on_patch`,
  `lay_smelting_line`, `feed_lab`). Inject available **skill signatures** into the
  prompt the way FLE re-injects `# Your utility functions`. Persist as procedural
  memory; grow over sessions.
- **avo (journal + reflection)** — **Adopt the RecursiveReportFormatter shape
  directly.** Periodic reflection should emit two buckets: **EXISTING STRUCTURES**
  (what's built where = semantic/base memory, much of which our engine already
  offloads via zones/scan) and **ERROR TIPS** (what failed + how to avoid —
  directly targets the #1 model weakness, error recovery). Borrow the practical
  tricks: chunked compaction, keep recent N verbatim, truncate stale entity dumps,
  cache summaries.
- **biw (outcome self-verify)** — Highest leverage given "error analysis is the
  key weakness." Expose entity **status** (working / no_power / no_fuel /
  output_full) and a short-window throughput query so the agent can `assert` the
  intended *outcome* (plates actually coming out; science accumulating) and
  self-correct, instead of fire-and-forget. Mirror FLE's status-assert idiom.
- **fea (eval harness)** — Adopt FLE's milestones as our yardstick: the
  "make 16 X/min" throughput targets (iron plate, gear, battery, red science,
  sulfur, plastic) + an open-play-style production score over a run. Run
  before/after each harness change. Stretch goal: run our agent against FLE's own
  gym tasks as an external, non-saturating benchmark (their tasks are
  open-source).

## 6. Strategic call: program-synthesis vs tool-calls

FLE's program-synthesis + persistent namespace is powerful for composition and
reuse, and is arguably the single biggest design difference from us. **Recommend
NOT migrating now** — it's a large rewrite, and `dzx` (macros) + namespace-style
skill injection captures most of the compositional benefit inside our existing
tool-call model. Keep program-synthesis on the table as a future direction if
macros prove too rigid.

**Net:** our spatial/engine layer is competitive; the FLE-validated priorities
for the rest of the epic are **biw (verify/error-recovery)** and **avo
(reflection → ERROR TIPS)** first, then **dzx (skills)**, with **fea** adopting
FLE's throughput milestones as the scoreboard.
