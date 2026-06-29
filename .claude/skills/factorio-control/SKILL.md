---
name: factorio-control
description: Use when controlling Factorio through factorioctl MCP tools; gives live-state, placement, recipe, and verification discipline without hard-coded layouts.
---

# Factorio Control

Use the game tools as the source of truth. Do not rely on memorized recipe names,
fixed entity orientations, or hard-coded build coordinates when a factorioctl
tool can inspect the current game state.

## Operating Rules

1. Inspect before mutating.
   Use `situation_report`, `render_map`, `get_inventory`, recipe/prototype
   lookups, `check_placement`, or `find_entity_placements` to choose the next
   action from live state. If the current position is far from the objective
   site, local absence is not global absence; inspect the target/resource/build
   area with read-only tools before deciding infrastructure is missing.

2. Mutate one dependent step at a time.
   Wait for the result of a world- or inventory-changing tool before issuing the
   next dependent mutating command. Use `count` parameters for repeated mining,
   crafting, or extraction instead of many tiny repeated calls.

3. Prefer derived placement.
   For drills, assemblers, power, fluids, belts, and inserters, use the helper
   tools to derive input, output, and valid placement positions. Do not assume a
   fixed orientation or copied coordinate layout.

4. Reuse existing infrastructure before building duplicates.
   For power and fluid work, audit existing `offshore-pump`, `boiler`,
   `steam-engine`, `pipe`, and electric pole entities before crafting or
   placing new ones. Search near the base, near known water, and near any
   partially built power plant. If relevant entities exist, inspect and repair
   their connections first; only place a duplicate after verifying the existing
   entity cannot be reused.

5. Verify what changed.
   After placing or changing production, call `verify_production` or the
   relevant status tool. If verification reports a problem, fix that concrete
   problem before expanding the build.

6. Treat research and recipes as runtime data.
   If a craft fails or a recipe seems unavailable, query the recipe/technology
   state and follow the reported blockers. Avoid guessing alternate recipe
   names.

7. Keep replies short.
   The player sees in-game text. Report the operational result and any real
   blocker, not an internal chain of thought.
