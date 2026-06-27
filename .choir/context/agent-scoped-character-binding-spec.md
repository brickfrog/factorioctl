# Spec: agent-scoped-character-binding

Bead: `factorioctl-upj.1` (feature) — covers `upj.1.1` (B3), `upj.1.2` (B2), `upj.1.3` (B8), `upj.1.4` (B4).

## Context
factorioctl drives a Factorio character by resolving "the first connected player's
character, else `global.factorioctl_character`" — copy-pasted across ~25 sites in
`src/client/lua.rs` (+ inline copies in `src/client/mod.rs`). Two consequences from the
audit (HEAD c3abe9e): with a human connected, every action (walk/mine/place/craft) puppets
**the human's body**; with none connected it falls back to `global.*`, which in Factorio 2.0
is a non-persistent plain global (the persistent table is `storage.*`, as the working
`storage.blueprints` code already uses), so the handle is unreliable/dead headless. factorioctl
also has **no concept of an agent id** — it ignores the `FACTORIO_AGENT_ID` the bridge passes.
The observable outcome we want: an AI agent drives **its own** character body, addressed by
`agent_id`, while a connected human keeps theirs — the foundation for "play multiplayer with the LLM."

## Clarifications
> Q&A from the crystallize step. Durable; leaves read this.

**Q: Who owns the agent's character entity in factorioctl?**
A: factorioctl owns it. Manage per-agent characters in its own 2.0 storage namespace
(`storage.factorioctl_characters[agent_id]`), keyed by `FACTORIO_AGENT_ID`. Keep the engine
standalone; integrating with the claude-in-factorio mod's `storage.characters` is a separate follow-up.

**Q: What happens to the old "first connected human" fallback?**
A: Kill it — strict agent-scoped. factorioctl NEVER drives a connected human's character. If the
agent has no character, tools return a clear error.

**Q: When a tool needs the agent's character and none exists yet?**
A: Explicit spawn, else error. An init/spawn call (agent_id + position) creates the character;
other tools return `no character for agent <id> — spawn first`. No surprise bodies at (0,0).

**Q: Bead B4 (entity-by-unit_number is a ±500 area scan) — include now, and how?**
A: Include it. factorioctl maintains a registry `storage.factorioctl_entities[unit_number]` for
entities it creates, with a bounded scan fallback. O(1) for own entities, correct beyond ±500.

## Goals
- Generated character-resolving Lua reads **only** `storage.factorioctl_characters[agent_id]`;
  it never iterates `game.connected_players` and never reads/writes `global.*`. (golden test)
- `agent_id` is threaded from `FACTORIO_AGENT_ID` (default `"default"` when unset) through the
  `Client` into every character/entity Lua builder. (unit test on plumbing)
- A single shared Rust helper emits the character-resolve snippet; the ~25 copy-paste sites call
  it instead of re-inlining the lookup. (grep: ≤1 definition site)
- Explicit spawn (`init_character` with agent_id + optional position) creates/returns the agent's
  character idempotently; character-requiring tools return a structured `{"error": "..."}` when absent. (golden + behavior test)
- `extract_items` deposits into the **agent's** character inventory, not `game.players[1]`. (golden test)
- Entity-by-unit_number resolves via `storage.factorioctl_entities[unit_number]` (populated on
  create) with a bounded-scan fallback; works for entities outside ±500. (golden + behavior test)
- `cargo test` green (CI gate); the existing `tests/lua_golden.rs` invariants still pass.

## Non-Goals
- No change to the claude-in-factorio mod, and no `remote.call` coupling to it (standalone only).
- Not fixing the Lua injection escaper (B5/`cjf.3`) here — but agent_id interpolation must not
  regress it (see Boundary).
- No new transport/RCON work (that landed in `upj.4.1`); do not touch `src/client/rcon.rs`.
- No multi-surface/planet logic; characters resolve on the agent's current surface as today.
- Not building a full entity GC for the registry (stale entries tolerated; validity-checked on read).

## Design
Primary file: `src/client/lua.rs` (the Lua builders) + `src/client/mod.rs` (inline copies + call
sites) + `src/client/server.rs`/client construction for `agent_id` plumbing + `tests/lua_golden.rs`.

Storage namespace (lazy-init in each snippet, mirroring existing `storage.blueprints` usage):
`storage.factorioctl_characters = storage.factorioctl_characters or {}` and
`storage.factorioctl_entities = storage.factorioctl_entities or {}`.

**Recommended decomposition: a single leaf.** All changes concentrate in `src/client/lua.rs` and
its call sites; splitting B3/B2/B8/B4 across parallel leaves would collide on the same file. The
golden harness already on `main` is the test scaffold.

- **agent_id plumbing.** Add `agent_id: String` to the client (read `FACTORIO_AGENT_ID`, default
  `"default"`); add a CLI `--agent-id` override. Pass it into every builder that resolves a
  character or creates/looks-up an entity.
- **Character resolve helper (B3+B2).** One Rust fn emits:
  `local c = storage.factorioctl_characters and storage.factorioctl_characters["<agent_id>"]; if not (c and c.valid) then rcon.print('{"error":"no character for agent <id>; spawn first"}') return end`
  Replace all ~25 inline lookups (`for _,p in pairs(game.connected_players)... else global.factorioctl_character`)
  with a call to this helper. Delete the `connected_players` and `global.*` lookups.
- **Spawn (`init_character`).** Create at given position (default (0,0)); store in
  `storage.factorioctl_characters[agent_id]`; idempotent (return existing valid char). Register the
  created character entity in the entity registry too.
- **extract_items (B8).** Resolve via the helper; deposit into that character's
  `get_main_inventory()`. Remove the `game.players[1]` hardcode.
- **Entity registry (B4).** On every factorioctl create (`place_entity`, `place_underground_belt`,
  `place_ghost`, spawn): `storage.factorioctl_entities[e.unit_number] = e`. Replace the seven
  `find_entities_filtered{area=±500}` unit_number scans with: look up
  `storage.factorioctl_entities[n]` (valid-check), else a bounded scan fallback. Keep the public
  behavior/return shapes identical.

## Verify
- `cargo test` (CI) — unit + golden + new behavior tests pass.
- Golden assertions (observable, no live game):
  - `cargo test lua_golden 2>&1 | grep -q "test result: ok"` — suite green.
  - A test asserting a character op's generated Lua **contains** `storage.factorioctl_characters[`
    and **does not contain** `connected_players` or `global.factorioctl_character`.
  - A test asserting `extract_items` Lua targets the resolved character, not `game.players[1]`.
  - A test asserting a unit_number lookup references `storage.factorioctl_entities[`.
- Static observable: `! grep -rn "connected_players\|global.factorioctl_character" src/client/`
  returns no hits in character-resolving code (only the helper, if anywhere).
- Plumbing: `cargo test` includes a test that `Client` defaults `agent_id` to `"default"` and
  honors `FACTORIO_AGENT_ID`.
- (Manual / optional, needs live server) spawn two agent_ids, walk each, confirm two distinct
  characters move independently and a connected human is untouched.

## Boundary (do not)
- Do NOT iterate `game.connected_players` in any character-resolving path. Strict agent-scoped.
- Do NOT use `global.*` for persistence anywhere — use `storage.*`.
- Do NOT implicitly auto-create characters; spawn must be explicit, else structured error.
- Do NOT regress `tests/lua_golden.rs` invariants: new Lua must have NO same-line trailing
  comments and balanced quotes (the executor joins lines and strips `--`-leading lines).
- Do NOT introduce a Lua-injection vector via `agent_id`: validate/escape it before interpolation
  (restrict to a safe charset or quote-escape); B5's full escaper is separate but this must not regress.
- Do NOT touch `src/client/rcon.rs` (just landed) or `.beads/` / `.choir/`.
- Keep CLI single-agent usage working unchanged when `FACTORIO_AGENT_ID` is unset (agent_id `"default"`).
- Preserve every tool's existing JSON return shape and error contract.

## Follow-Ups
- Integration: reconcile factorioctl's `storage.factorioctl_characters` with the claude-in-factorio
  mod's `storage.characters` so the bridge and engine share one body per agent (new bead).
- Apply B5/`cjf.3` Lua escaper to `agent_id` (and all interpolated args) once it lands.
- Entity-registry GC / staleness sweep if the registry grows unbounded in long sessions.
- Remaining audit beads: `cjf.2` (get_contents), `cjf.5/6` (cheap Lua fixes), `cjf.4` (execute_lua gate),
  `upj.2.1`/`upj.3.1` (chat / error feedback).
