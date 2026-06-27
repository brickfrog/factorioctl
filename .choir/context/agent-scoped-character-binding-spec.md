# Spec: agent-scoped-character-binding

Bead: `factorioctl-upj.1` (feature) — covers `upj.1.1` (B3), `upj.1.2` (B2), `upj.1.3` (B8), `upj.1.4` (B4).
Revised after spec-audit (Sarcasmotron, 15 findings); see `## Clarifications` and `## Audit resolutions`.

## Context
factorioctl resolves "the first connected player's character, else `global.factorioctl_character`"
across ~25 sites in `src/client/lua.rs` plus inline copies in `src/client/mod.rs`. With a human
connected this puppets **their** body; with none it falls back to `global.*`, which in Factorio 2.0
is a non-persistent plain global (the persistent table is `storage.*`, as the working
`storage.blueprints` code already uses — `lua.rs:1557`). factorioctl also has **no agent concept**:
`FactorioClient` only holds RCON state (`mod.rs:25-30`) and ignores the `FACTORIO_AGENT_ID` the bridge
passes. We want: a named AI agent drives **its own** character body while a connected human keeps theirs
— the foundation for "play multiplayer with the LLM" — without breaking the existing single-agent /
claude-in-factorio flow.

## Clarifications
> Q&A from crystallize + the spec audit. Durable; leaves read this.

**Q: Who owns the agent's character entity in factorioctl?**
A: factorioctl owns it — per-agent in `storage.factorioctl_characters[agent_id]`, keyed by
`FACTORIO_AGENT_ID`. Standalone; mod reconciliation is a follow-up.

**Q: What happens to the old "first connected human" fallback?**
A: Flag-gated, NOT killed outright (audit F1/F2/F13: killing it breaks the working bridge).
A **resolution mode** keyed on `agent_id`: legacy ids resolve the connected player (back-compat);
**named** agents are strict agent-scoped and never touch a connected human. Details in Design.

**Q: When a tool needs the agent's character and none exists yet?**
A: Explicit spawn (`init_character`), else a structured error. No implicit creation by non-init tools.
Named agents require an explicit spawn position (no `(0,0)` pile); the legacy default may use `(0,0)`.

**Q: Bead B4 (±500 unit_number scan) — include now, and how?**
A: Yes. Registry `storage.factorioctl_entities[unit_number]` populated by **every** factorioctl creator,
O(1) for own entities, with the existing bounded scan as fallback for unregistered/external entities.

**Q: (audit) Strict mode breaks the bridge — how to handle?**
A: Flag-gated compat. Legacy connected-player behavior stays the DEFAULT (active for `agent_id` ∈
{unset, "", "default", "__player__"}); strict per-agent bodies are opt-in for any other `agent_id`.
The existing bridge (sends `FACTORIO_AGENT_ID="default"`) keeps working **unchanged**.

## Goals
- **Resolution mode** (single shared Rust helper emits the snippet):
  - legacy id (`unset|""|"default"|"__player__"`) → first connected player's character, else
    `storage.factorioctl_characters["__player__"]`, else structured error. (preserves today's behavior, via `storage` not `global`)
  - named id → `storage.factorioctl_characters[agent_id]` ONLY; never reads `game.connected_players`; structured error if absent.
- No character-resolving path reads/writes `global.*` anywhere. (static builder test)
- `agent_id` threaded from `FACTORIO_AGENT_ID` (default `"__player__"`) and a `--agent-id` CLI flag,
  validated against `^[A-Za-z0-9_.:-]{1,64}$` (reject otherwise, before any Lua is emitted). (unit tests incl. hostile ids)
- The ~25 `lua.rs` lookups AND all `mod.rs` inline snippets (enumerated in Design) call the one helper.
- `extract_items` (B8) and research inventory reads (`lua.rs:1912`) use the resolved character, not `game.players[1]`/connected-first.
- Entity registry populated by every creator (enumerated in Design); unit_number lookups resolve it first, then bounded-scan fallback; reads nil invalid entries; deletes clear entries.
- `cargo test` green (CI gate); existing `tests/lua_golden.rs` invariants still pass.
- A **required local smoke test** (headless server) proves: two named agents get two distinct bodies that move independently; a connected player is untouched in named-agent mode; the stored character survives across separate RCON calls.

## Non-Goals
- No change to the claude-in-factorio mod and no `remote.call` coupling (standalone). Mod-side per-agent reconciliation is a follow-up.
- Blueprint/clipboard ops (`create_native_blueprint`, `save_blueprint`, `place_blueprint`,
  `import_blueprint`; `lua.rs:1477/1527/1621/1665`) **remain `game.players[1]`-coupled** this wave —
  explicitly out of scope (audit F5), tracked as a follow-up.
- Not fixing the Lua-injection escaper generally (B5/`cjf.3`); but agent_id validation here must not regress it.
- No `rcon.rs` changes (landed in `upj.4.1`).
- Registry: no background GC/sweeper; only read-time nil + delete-time clear (audit F15).
- Goal is **own/registered** entities beyond ±500 (audit F12); external unregistered entities keep today's scan behavior.

## Design
Files: `src/client/lua.rs`, `src/client/mod.rs`, client construction (`mod.rs` + `src/cli/mod.rs` conn args + `src/bin/mcp.rs`), `src/cli/character.rs`, `tests/lua_golden.rs`, `scripts/` (smoke test).
Storage (lazy-init like `storage.blueprints`): `storage.factorioctl_characters = storage.factorioctl_characters or {}`, `storage.factorioctl_entities = storage.factorioctl_entities or {}`.
**Recommended: a single leaf** — all changes concentrate in `lua.rs`/`mod.rs`; parallel leaves would collide.

### agent_id plumbing (audit F6 — concrete)
- Add field `agent_id: String` to `FactorioClient` (`mod.rs:25-30`). Keep `connect(host,port,password)`; set agent_id via a `with_agent_id(self, &str) -> Self` builder used right after `connect`.
- `src/cli/mod.rs` connection args gain `--agent-id` (global), defaulting to `env FACTORIO_AGENT_ID` else `"__player__"`; validated at parse (reject invalid). `mcp.rs:567-570` reads the same env and calls `with_agent_id`.
- `LuaCommand` builders that resolve a character or look up an entity take `agent_id: &str` as their first param. The client passes `&self.agent_id`. `tests/lua_golden.rs` updates call sites to pass an id.

### agent_id validation/escaping (audit F7 — concrete)
- Validate once at the Rust boundary: `^[A-Za-z0-9_.:-]{1,64}$`. Invalid → hard error (`anyhow::bail!`), no Lua emitted. Because the charset excludes `"`, `\`, newline, `]`, `-` -leading-`--`-in-context, interpolation into `["<id>"]` and into JSON error strings is then safe. Tests: reject `"`, `\n`, `]`, `a--b`, `a"b`, empty, >64 chars; accept `default`, `__player__`, `doug-nauvis`, `a.b:c`.

### Character-resolve helper (audit F8 — exact executor-safe form)
The executor joins lines with spaces and drops `--`-leading lines (`mod.rs:55-61`). The helper emits a
single space-join-safe block ending in a bound `local c` and an early `return` on failure, with NO
same-line comments and balanced quotes, e.g. (rendered with the resolved `agent_id`):
```
storage.factorioctl_characters = storage.factorioctl_characters or {}
local c = nil
<MODE BLOCK>
if not (c and c.valid) then rcon.print('{"error":"no character for agent <agent_id>; spawn first"}') return end
```
where `<MODE BLOCK>` for a legacy id iterates `game.connected_players` then
`storage.factorioctl_characters["__player__"]`, and for a named id is just
`c = storage.factorioctl_characters["<agent_id>"]`. Callers prepend this block; it binds `c` and must
be followed by a newline before caller `local`s. Snapshot the exact emitted string in golden tests.

### Complete site inventory (audit F3/F4/F11 — no grep prayers)
- `lua.rs` character lookups to replace: 379,401,431,457,489,548,567,589,690,757,791,810,925,997,**1912-1919 (research)**,2760.
- `mod.rs` inline snippets to replace: `mine_at` 406-415, `mine_nearest` 502-510, `get_character_position` 811-830, `walk_to` stop/move 933-934/1015-1022/1027-1030, `gather_resource` 1052-1057/1106-1114/1140-1144, high-level builders 1189-1196/1310-1317.
- `extract_items` `lua.rs:1195-1203` (B8): deposit into resolved character.
- Research `get_available_research` `lua.rs:1912-1934`: count science from the **resolved** character's inventory (named agent → its own; legacy → connected/stored). Document this explicitly.

### Entity registry (audit F11/F12/F15)
- Register on EVERY creator: `place_entity`, `place_underground_belt`, `place_ghost`, `init_character` (its char), `build_drill_array` (`mod.rs:1250-1267`), `build_smelter_line` (`mod.rs:1344-1358`), blueprint ghosts via `build_blueprint` (`lua.rs:1639/1689`). Emit `storage.factorioctl_entities[e.unit_number] = e` for each created entity/ghost.
- Lookups (`get_entity`, `remove_entity`, `rotate_entity`, `insert_items`, `extract_items`, `set_recipe`): `local e = storage.factorioctl_entities and storage.factorioctl_entities[n]; if e and not e.valid then storage.factorioctl_entities[n]=nil e=nil end` then fallback to the existing bounded scan if `e` nil. Deletes (`remove_entity`, `remove_entity_at`) clear the entry.

### Return-shape contract (audit F10 — per-tool)
Preserve each tool's EXISTING shape; only standardize the **error** string where a tool already
returned an ad-hoc no-character error (e.g. `{"error":"No character"}` → `{"error":"no character for agent <id>; spawn first"}`).
Tools with graceful no-char shapes keep them, now agent-scoped: `character_status` → `{"valid":false}`,
`character_inventory` → empty inventory, `get_mining_status` → `{"mining":false}`, `wait_for_crafting` → `"0"`, `stop_mining` → `"error"`, `clear_area` → embedded error. No tool changes its success shape.

### Spawn (audit F9)
`init_character(agent_id, x, y)`: create at `(x,y)`, store under `storage.factorioctl_characters[agent_id]`
(legacy ids store under `"__player__"`), idempotent (return existing valid char), register in entity
registry. CLI `character init` gains optional `--x/--y` (default `0,0` only for legacy ids; named agents
without a position → error "named agent requires --x/--y"). Resolves the F9 contradiction.

## Verify
- `cargo test` (CI) — plumbing + golden + new static builder tests pass.
- Static builder tests (no live game): for a named agent, the character-op Lua **contains**
  `storage.factorioctl_characters["doug"]` and **contains no** `connected_players`/`global.`; for a
  legacy id it contains the connected-player block AND `storage.factorioctl_characters["__player__"]`;
  `extract_items` targets the resolved character not `game.players[1]`; a unit_number op references
  `storage.factorioctl_entities[`. (replaces the gameable grep — audit F14)
- agent_id validation tests with hostile ids (reject) and valid ids (accept).
- Golden snapshot of the exact resolve-helper string (executor-safe: no inline comments, balanced quotes).
- **Required local smoke test** `scripts/smoke_agent_binding.sh` (headless server; NOT in GitHub CI):
  start server, `init_character a --x 5 --y 0`, `init_character b --x 30 --y 0`, walk each, assert two
  distinct `unit_number`s moved; with a connected player present assert its character is untouched under
  named-agent mode; re-resolve after a fresh RCON connection to prove `storage` persistence. (audit F13)

## Boundary (do not)
- Named-agent mode must NEVER read `game.connected_players`. Legacy mode may, by design.
- NO `global.*` for persistence anywhere — only `storage.*`.
- NO implicit character creation by non-init tools; absence → structured error.
- NO same-line trailing Lua comments; balanced quotes (the executor joins lines / strips `--`-leading lines). New Lua must keep `tests/lua_golden.rs` invariants green.
- `agent_id` MUST be validated to `^[A-Za-z0-9_.:-]{1,64}$` before any interpolation; reject otherwise. No injection regression.
- Do NOT touch `src/client/rcon.rs`, `.beads/`, `.choir/`.
- Bridge stays working UNCHANGED: `FACTORIO_AGENT_ID="default"` (and unset) → legacy connected-player mode.
- Preserve every tool's existing success/return shape; only the ad-hoc no-character error string is standardized.
- Blueprint/clipboard stay `game.players[1]`-coupled this wave (out of scope; do not half-migrate them).

## Audit resolutions
F1/F2/F13 → flag-gated compat (legacy default keeps bridge working). F3/F4/F11 → explicit site +
creator inventory above. F5 → blueprints out of scope, documented. F6 → concrete client/builder API.
F7 → concrete charset + reject + test vectors. F8 → exact executor-safe helper string + snapshot.
F9 → spawn position rule. F10 → per-tool return-shape contract. F12 → goal narrowed to own/registered.
F13 → required local smoke test. F14 → static builder tests replace grep. F15 → read-nil + delete-clear.

## Follow-Ups
- Mod reconciliation: bridge spawns/registers via factorioctl `init_character` so engine + mod share one body per named agent (new bead).
- Agent-scope the blueprint/clipboard family (new bead).
- Apply B5/`cjf.3` escaper to all interpolated args once it lands.
- Entity-registry GC/sweep for very long sessions.
