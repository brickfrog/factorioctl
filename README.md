# Factorioctl

This project was vibe coded in a weekend from my phone. It works better than you might expect but use it at your own risk. I make no guarantees about this code -- I haven't even read it.

## What it is

This repo contains the code for a CLI tool "like kubectl" and an MCP server for controlling Factorio via RCON. Designed for AI agents (like Claude) to play Factorio autonomously.

[![Demo Video](https://img.youtube.com/vi/TQvqkc7ivIw/maxresdefault.jpg)](https://www.youtube.com/watch?v=TQvqkc7ivIw)

**[Watch the demo on YouTube](https://www.youtube.com/watch?v=TQvqkc7ivIw)**

## Background

After reading [Ramp's RCT agent](https://labs.ramp.com/rct) article, I wanted to give it a try too. I thought some problems they described would be more easily solvable. Spatial layout is a major pain point despite a lot of focused effort to add more tools to help here. More tools help, but it's fundamentally very difficult to get LLMs to solve these problems.

Big shout out to [rberg27/doom-coding](https://github.com/rberg27/doom-coding) which is how I vibe coded this on my phone and what got me interested in trying out vibe coding for real.

## Lessons Learned

**Examples and hand-holding go a long way**. Left to its own devices, Claude will happily destroy your code and break your correct unit tests with the belief that it's fixing things. Getting into the game and laying things out (i.e. NESW all orientations of drills with belts at their drop zones) lets Claude have a solid baseline from which it can debug and fix everything. If I were doing this again, I'd build from the ground up with exhaustive examples of all foundational behaviors from the very start, have them committed and running as test cases.

For gameplay, **speed is key**. Claude Sonnet is much less intelligent but it's more entertaining to watch play. I didn't get to sub-agents or having an async task orchestration system for the gameplay so at least for a single LLM sending commands, speed is more important than making good decisions.

**Creativity is heavily rewarded with vibe coding**. There's often little correlation between effort and reward.  If you can suggest the right idea, Claude can have it implemented in minutes and it can have a huge impact. Other ideas take a long time to get working and have much less impact. There's an art to finding this balance.

**LLMs are pretty clever**: the more generic and multi-use a tool is, the more it will be used in surprising ways.

**CLAUDE.md and prompts are critical**. Mixing CLAUDE.md rules for both coding and playing the game is a mistake. The prompting and rules have a huge impact in how the agent will play the game. In some ways the agent shown in the YouTube video is more entertaining than what's in the repo at the time of writing. I think there are huge gains to be made here by refocusing on what's most important.

**Claude likes MCP a lot more than CLI tools** but iterating with MCP is annoying, you have to constantly restart claude. MCP seemed to help make Claude play the game much more actively and responsively (though I did make multiple changes when adding MCP so I may be misattributing the gains to that).

## Quick Start

Set things up:
```bash
# Create a save file (simple, seeded world with no enemies)
python3 scripts/create_map.py --name some_name
# Start the server. This will run until you run the cleanup script
SAVE_PATH=saves/some_name.zip ./tests/setup.sh
```

```bash
# Configure connection
export FACTORIO_RCON_HOST=localhost
export FACTORIO_RCON_PORT=27015
export FACTORIO_RCON_PASSWORD=yourpassword

# Or save to config file
factorioctl config set --host localhost --port 27015 --password yourpassword

# Check connection
factorioctl character status
```

## MCP Server

The MCP server exposes Factorio control as tools for AI agents.

```bash
# Run the MCP server
cargo run --bin mcp

# Or build and run directly
cargo build --release
./target/release/mcp
```

### MCP Tools

**Movement & Actions:**
- `walk_to` - Pathfind to a position
- `place_entity` - Place entity from inventory
- `mine_at` - Mine entities/resources at a position
- `craft` - Craft items
- `insert_items` / `extract_items` - Move items into/from entities
- `set_recipe` - Set recipe on assemblers
- `remove_entity` - Remove an entity
- `clear_area` - Clear trees and rocks

**Belt Routing:**
- `route_belt` - A* pathfinding for belt placement (supports underground belts, zone awareness)
- `get_machine_belt_positions` - Get correct belt/inserter positions for machines

**Queries:**
- `get_entities` - Get entities in an area
- `get_resources` / `find_nearest_resource` - Find resource patches
- `get_character` / `get_inventory` - Character state
- `render_map` - ASCII map visualization
- `get_tick` - Game time

**Research:**
- `get_research_status` / `get_available_research` - Research info
- `start_research` - Queue research

**Power:**
- `get_power_status` / `get_power_networks` - Power grid info
- `find_power_issues` - Find unpowered entities

**Belt Analysis:**
- `analyze_belt_reach` / `analyze_belt_networks` / `analyze_belt_gaps`
- `get_belt_lane_contents` / `detect_sushi_belts` / `trace_belt_sources`
- `analyze_inserters`

**Factory Organization:**
- `create_zone` / `list_zones` / `get_zone` / `update_zone` / `delete_zone` - Zone management
- `scan_resources` / `get_protected_resources` - Protect ore patches
- `check_placement` / `find_build_area` - Smart placement
- `get_blank_slate` - View constraints without existing buildings

**Other:**
- `get_alerts` - Check for problems (empty drills, no fuel, enemies)
- `broadcast_thought` - In-game TTS/console messages
- `execute_lua` - Raw Lua execution

## CLI Commands

The CLI mirrors MCP functionality for manual use:

```bash
# Movement and building
factorioctl walk-to --to 50,-30
factorioctl place --entity transport-belt --at 5,5 --direction east
factorioctl mine --at 5,5 --count 3
factorioctl craft --recipe iron-gear-wheel --count 10

# High-level building
factorioctl belt line --from 0,0 --to 10,0
factorioctl build drill-array --count 4 --resource iron-ore --near 50,-30
factorioctl build smelter-line --count 4 --at 45,-30
factorioctl power line --from 0,0 --to 20,0

# Queries
factorioctl get entities --area 0,0,100,100
factorioctl get resources --area 0,0,50,50 --type iron-ore
factorioctl character inventory
factorioctl map --x 0 --y 0 --radius 20

# Analysis
factorioctl analyze belt-reach --at 50,-30
factorioctl analyze belt-networks --area 0,0,100,100
factorioctl research status

# Raw Lua
factorioctl exec "rcon.print(game.tick)"
```

## Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────────┐
│   Claude     │────▶│  MCP Server  │────▶│  FactorioClient  │
│   (Agent)    │     │  (stdio)     │     └────────┬─────────┘
└──────────────┘     └──────────────┘              │ RCON
                                                   ▼
┌──────────────┐                          ┌────────────────┐
│     CLI      │─────────────────────────▶│   Factorio     │
│  (human use) │                          │   (headless)   │
└──────────────┘                          └────────────────┘
```

### Design Principles

**Lua-over-RCON**: All game interaction happens by sending Lua commands over Factorio's RCON interface. The `FactorioClient` wraps this with typed Rust functions, but under the hood it's constructing Lua snippets and parsing JSON responses.

**Stateless queries, stateful actions**: Query tools (`get_entities`, `get_resources`, etc.) read game state without side effects. Action tools (`place_entity`, `walk_to`, etc.) modify the world. The agent memory system (zones, protected resources) lives in a JSON file alongside the game, not in Factorio itself.

**High-level tools for common patterns**: Rather than making the agent figure out belt routing from scratch, `route_belt` uses A* pathfinding with collision detection. `get_machine_belt_positions` knows where drills/furnaces actually output items. These encode Factorio-specific knowledge the agent would otherwise learn slowly through trial and error.

### Key Components

**Pathfinding (`world/pathfind.rs`)**: A* implementation for belt routing and character movement. Builds a collision map from entity queries, then finds paths that avoid obstacles. Supports underground belts and zone-aware routing.

**Belt Analysis (`analyze/`)**: Tools for understanding belt networks - tracing item flow, finding gaps, detecting sushi belts (mixed items on same lane). Helps the agent debug logistics issues.

**Zone System (`memory/`)**: Persistent spatial organization. The agent can reserve areas for smelting, assembly, etc., and tools like `check_placement` and `route_belt` respect these boundaries. Stored in `.agent_memory.json`.

**Resource Protection**: `scan_resources` marks ore patches as protected. Subsequent `check_placement` calls warn before building non-mining structures on ore. Prevents the classic mistake of building over your iron patch.

### MCP Integration

The MCP server (`src/bin/mcp.rs`) exposes tools via the Model Context Protocol. Each tool is a Rust async function with typed parameters, marshaled to/from JSON. The agent sees tool descriptions and calls them by name.

Tools are designed to be:
- **Self-documenting**: Descriptions explain not just what the tool does, but when to use it
- **Failure-tolerant**: Return errors as data rather than crashing
- **Composable**: Low-level tools for flexibility, high-level tools for common workflows

## Development

```bash
cargo build          # Build
cargo test           # Run tests
cargo build --release  # Release build
```

## License

MIT
