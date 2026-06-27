# Spec: agent-scoped-character-binding

Bead: `factorioctl-upj.1` (feature) — covers `upj.1.1` (B3), `upj.1.2` (B2), `upj.1.3` (B8), `upj.1.4` (B4).
Revised twice after Sarcasmotron spec-audits (15 findings, then 7 blockers). See `## Audit resolutions`.

## Context
factorioctl resolves "the first connected player's character, else `global.factorioctl_character`"
across ~25 sites in `src/client/lua.rs` plus inline copies in `src/client/mod.rs`. With a human
connected this puppets **their** body; with none it falls back to `global.*`, which in Factorio 2.0 is a
non-persistent plain global (the persistent table is `storage.*`, as the working `storage.blueprints`
code already uses — `lua.rs:1557`). factorioctl also has **no agent concept**: `FactorioClient` holds
only RCON state (`mod.rs:25-30`) and ignores the `FACTORIO_AGENT_ID` the bridge passes. We want the
*engine capability* for a **named** agent to drive its **own** body while a connected human keeps theirs
— the foundation for "play multiplayer with the LLM" — without breaking today's single-agent flow.

## Clarifications
> Q&A from crystallize + two spec audits. Durable; leaves read this.

**Q: Who owns the agent's character?** A: factorioctl, in `storage.factorioctl_characters[agent_id]`,
keyed by `FACTORIO_AGENT_ID`. Standalone; bridge/mod reconciliation is a follow-up.

**Q: The old connected-human fallback?** A: Flag-gated by resolution mode (killing it outright breaks
the working bridge): *legacy* ids resolve the connected player (back-compat); *named* ids are strict and
never touch a human.

**Q: No character yet?** A: Explicit `init_character`, else structured error. No implicit creation.
Named agents require a spawn position (no `(0,0)` pile); legacy default may use `(0,0)`.

**Q: B4 (±500 scan)?** A: Registry `storage.factorioctl_entities[unit_number]` populated by every
creator; O(1) for own entities, bounded-scan fallback for external/unregistered.

**Q: Does this keep the claude-in-factorio bridge working?** A: The **single-agent / connected-player**
path: yes, unchanged. The **multi-agent named** bridge path (run.sh defaults to group mode; pipe.py
sends `FACTORIO_AGENT_ID=<planet-name>`): **NO — explicitly out of scope.** That path is already
half-broken today (the bridge pre-places via the mod's `storage.characters`, not factorioctl's). This
wave delivers the engine capability; wiring the bridge to call factorioctl `init_character` for named
agents is a tracked follow-up. Do not claim the named bridge path works.

## Goals
- **Two resolve helpers** (one Rust source each; exact Lua in Design):
  - `resolve_required(agent_id)` — binds `c`; on absence emits `{"error":"no character for agent <id>; spawn first"}` and `return`. Used by action tools.
  - `resolve_optional(agent_id)` — binds `c` (may be nil/invalid); NO print, NO return. The caller keeps its own graceful shape.
  Both honor resolution mode: legacy id → connected player then `storage.factorioctl_characters["__player__"]`; named id → `storage.factorioctl_characters[agent_id]` only (never `connected_players`).
- No character/entity path reads or writes `global.*`. (static builder test)
- `AgentId` newtype is the single validation boundary (see Design); `FACTORIO_AGENT_ID` and `--agent-id` and MCP all construct through it; invalid ids hard-error before any Lua is emitted.
- Every `lua.rs` lookup AND every `mod.rs` inline snippet (enumerated in Design) routes through the helpers.
- `extract_items` (B8) and `get_available_research` inventory read use the **resolved** character, not `game.players[1]`/connected-first.
- Entity registry populated by every creator (enumerated); unit_number lookups (incl. `get_entity_inventory`) resolve registry-first, then bounded-scan; reads nil invalid entries; deletes clear entries.
- `cargo test` green (CI); existing `tests/lua_golden.rs` invariants still pass.
- The leaf delivers `scripts/smoke_agent_binding.sh` and the static tests; the **live** smoke run is a TL/human pre-merge gate (see Verify Done criteria).

## Non-Goals
- No change to the claude-in-factorio mod / no `remote.call` coupling. The **named** bridge path is NOT wired here (follow-up).
- Blueprint/clipboard ops (`create_native_blueprint`/`save_blueprint`/`place_blueprint`/`import_blueprint`; `lua.rs:1477/1527/1621/1665`) stay `game.players[1]`-coupled — out of scope (follow-up).
- Not the general Lua-injection escaper (B5/`cjf.3`); but `AgentId` validation must not regress it.
- No `rcon.rs` changes. No background registry GC (read-nil + delete-clear only).
- "Beyond ±500" applies to **own/registered** entities only; external entities keep today's scan behavior.

## Design
Files: `src/client/lua.rs`, `src/client/mod.rs`, `src/cli/mod.rs` (conn args), `src/bin/mcp.rs`,
`src/cli/character.rs`, `tests/lua_golden.rs`, `scripts/smoke_agent_binding.sh`.
Storage (lazy-init like `storage.blueprints`): `storage.factorioctl_characters = storage.factorioctl_characters or {}`;
`storage.factorioctl_entities = storage.factorioctl_entities or {}`. **Single leaf** (changes concentrate in `lua.rs`/`mod.rs`).

### AgentId newtype + plumbing (closes B3/B4/F6/F7)
- New `struct AgentId(String)` with `AgentId::new(raw: Option<&str>) -> anyhow::Result<AgentId>`:
  1. Normalize: `None`/`""` → `"__player__"`.
  2. Validate the normalized value against `^[A-Za-z0-9_.:-]{1,64}$`; else `anyhow::bail!("invalid agent id")`. (So validation never sees empty; the legacy set after normalization is `{"default","__player__"}`.)
  3. `fn is_legacy(&self) -> bool` → id is `"default"` or `"__player__"`.
- `FactorioClient` holds `agent_id: AgentId`. `connect(...)` stays; add `with_agent_id(self, AgentId) -> Self` (infallible — validation already happened in `AgentId::new`). Single enforcement boundary = `AgentId::new`, called by: CLI `--agent-id` parse (default `env FACTORIO_AGENT_ID`), and `mcp.rs:567-570` (env), both surfacing the error.
- Character/entity `LuaCommand` builders take `agent_id: &AgentId` (or its `&str` + `is_legacy`). The client passes `&self.agent_id`. `tests/lua_golden.rs` updates call sites.
- Reject vectors (tests): `"`, `\n`, `]`, `a"b`, 65×`a`. Accept: `default`, `__player__`, `doug-nauvis`, `a.b:c`, `a--b` (double-hyphen is SAFE inside a quoted Lua string index and a single-quoted JSON string — it is NOT a reject case; the prior spec was wrong).

### Resolve helpers — EXACT emitted Lua (closes B2/B7/F8/F10)
Executor joins lines with spaces and drops `--`-leading lines (`mod.rs:55-61`); every line below is space-join-safe, comment-free, balanced-quoted. `<id>` is the validated AgentId.

`resolve_required`, **named** id `<id>`:
```
storage.factorioctl_characters = storage.factorioctl_characters or {}
local c = storage.factorioctl_characters["<id>"]
if not (c and c.valid) then rcon.print('{"error":"no character for agent <id>; spawn first"}') return end
```
`resolve_required`, **legacy**:
```
storage.factorioctl_characters = storage.factorioctl_characters or {}
local c = nil
for _, p in pairs(game.connected_players) do if p.character and p.character.valid then c = p.character break end end
if not c then c = storage.factorioctl_characters["__player__"] end
if not (c and c.valid) then rcon.print('{"error":"no character for agent __player__; spawn first"}') return end
```
`resolve_optional` = the same two blocks **minus** the final `if not (c and c.valid) then ... return end`
line. The caller then branches on `c and c.valid` and emits its own existing shape.

Per-tool mapping:
- **resolve_required**: `walk_character`, `teleport_character`, `mine_at`, `mine_nearest`, `start_mining`, `craft`, `place_entity`, `place_underground_belt`, `place_ghost`, `extract_items`, `clear_area`, `init`-adjacent placement.
- **resolve_optional** (keep existing graceful shape): `character_status`→`{"valid":false}`, `character_inventory`→empty inv, `get_mining_status`→`{"mining":false}`, `wait_for_crafting`→`"0"`, `stop_mining`→`"error"`, `get_available_research` (skips inventory science when `c` absent).
No tool changes its **success** shape.

### Complete site inventory (closes B5/F3/F4/F11)
- `lua.rs` lookups to replace: 379,401,431,457,489,548,567,589,690,757,791,810,925,997,1912-1919(research),2760.
- `mod.rs` inline snippets: `mine_at` 406-415, `mine_nearest` 502-510, `get_character_position` 811-830, `walk_to` 933-934/1015-1022/1027-1030, `gather_resource` 1052-1057/1106-1114/1140-1144, builders 1189-1196/1310-1317.
- `extract_items` `lua.rs:1195-1203`: deposit into resolved character. **Legacy-mode note:** in legacy mode the resolved character is the connected player (then stored `__player__`), so legacy `extract_items`/`get_available_research` still deposit into / read the connected human's inventory **by design** (preserves today's behavior; named mode never does this).
- Research `get_available_research` `lua.rs:1912-1934`: count science from the resolved character (`resolve_optional`).

### Entity registry (closes B5/F11/F12/F15)
- Register on EVERY creator: `place_entity`, `place_underground_belt`, `place_ghost`, `init_character` (its char), `build_drill_array` (`mod.rs:1250-1267`), `build_smelter_line` (`mod.rs:1344-1358`), blueprint ghosts via `build_blueprint` (`lua.rs:1639/1689`). For multi-entity builders, register EACH created entity/ghost: `storage.factorioctl_entities[e.unit_number] = e`.
- Lookups — **including `get_entity_inventory` (`lua.rs:105-118`)** alongside `get_entity`, `remove_entity`, `rotate_entity`, `insert_items`, `extract_items`, `set_recipe`: `local e = storage.factorioctl_entities and storage.factorioctl_entities[n] if e and not e.valid then storage.factorioctl_entities[n] = nil e = nil end` then existing bounded scan if `e` nil.
- Deletes (`remove_entity`, `remove_entity_at`) clear the entry after destroy.

### Spawn (closes B?/F9)
`init_character(agent_id, x, y)`: create at `(x,y)`, store under `storage.factorioctl_characters[<key>]`
(`__player__` for legacy), idempotent (return existing valid char), register in entity registry. CLI
`character init` gains `--x/--y`: optional for legacy (default `0,0`); **required for named agents**
(absent → error "named agent requires --x/--y").

## Verify
- `cargo test` (CI): `AgentId` tests (accept/reject vectors above); static builder tests; golden snapshots.
- Static builder tests (no live game): named-agent op Lua **contains** `storage.factorioctl_characters["doug"]`, **no** `connected_players`/`global.`; legacy op contains the connected-player loop AND `storage.factorioctl_characters["__player__"]`; `extract_items` targets the resolved char (not `game.players[1]`); a unit_number op (incl. `get_entity_inventory`) references `storage.factorioctl_entities[`. (replaces grep — F14)
- Golden snapshots of the EXACT `resolve_required`/`resolve_optional` strings for one named + one legacy id (must match the Lua blocks above byte-for-byte modulo the id).
- **Smoke test Done criteria (closes B6/F13):** the leaf MUST (a) create `scripts/smoke_agent_binding.sh` implementing the scenario below, (b) shellcheck/`bash -n` it clean, (c) if a headless Factorio is reachable in its env, run it and paste pass/fail output in the PR; (d) if not reachable, say so explicitly. The **live run is a required pre-merge gate the TL performs** against the project's headless server; a failing live run blocks merge. Scenario: start server; `character init --agent-id a --x 5 --y 0`; `--agent-id b --x 30 --y 0`; walk each; assert two distinct moved `unit_number`s; with a player connected assert its character is untouched under named mode; reconnect RCON and re-resolve to prove `storage` persistence.

## Boundary (do not)
- Named mode must NEVER read `game.connected_players`. Legacy mode may, by design.
- NO `global.*` persistence — `storage.*` only. NO implicit character creation by non-init tools.
- NO same-line trailing Lua comments; balanced quotes; keep `tests/lua_golden.rs` invariants green.
- All agent ids go through `AgentId::new`; never interpolate an unvalidated id.
- Do NOT touch `src/client/rcon.rs`, `.beads/`, `.choir/`.
- Preserve every tool's **success** shape and every graceful no-char shape (use `resolve_optional` there); only ad-hoc `{"error":"No character"}` strings standardize.
- Blueprint/clipboard stay `game.players[1]`-coupled (do not half-migrate).
- Do NOT claim the multi-agent/named claude-in-factorio bridge path works — it doesn't until the follow-up.

## Audit resolutions
Round 1 (F1–F15) and Round 2 (Part B 1–7) all addressed:
B1→bridge claim narrowed to single-agent only, named path explicit out-of-scope. B2/B10→two helpers
(`resolve_required`/`resolve_optional`) + per-tool map. B3→`AgentId::new` normalizes empty→`__player__`
before validating; `a--b` removed from reject vectors. B4→`AgentId` newtype is the fallible boundary;
`with_agent_id` is infallible. B5→`get_entity_inventory` added to registry lookups. B6→concrete
smoke-test Done criteria + TL live-run gate. B7→exact legacy + named Lua pinned for snapshot. Nits:
legacy extract/research human-inventory behavior documented; multi-entity builder registration spelled out.

## Follow-Ups
- Bridge reconciliation: claude-in-factorio spawns/registers named agents via factorioctl `init_character` (new bead) — makes the multi-agent companion path actually work.
- Agent-scope the blueprint/clipboard family (new bead).
- Apply B5/`cjf.3` escaper to all interpolated args once it lands.
- Entity-registry GC/sweep for very long sessions.
